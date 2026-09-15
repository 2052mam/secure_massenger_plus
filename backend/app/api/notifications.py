"""Polling-based notifications that work without Google/Apple push.

Telegram and Instagram stay reliable in Iran because they do not depend on
a single push channel: when FCM/APNs is sanctioned, filtered or simply
absent (phones without Play Services), their own background connection
still delivers messages. This blueprint is the server half of that idea:

* ``GET /pending`` is a tiny "what is new since X" feed. The Flutter app
  calls it from the foreground every few seconds and from a background
  service / WorkManager task while it is closed, then raises *local*
  notifications. No Firebase project, no APNs certificate and no extra
  firewall hole is required.
* ``POST /register`` stores an optional future push token and the user's
  notification preference on the current device row.
* Optional FCM layer (``app.services.push_service``): when the server has
  Firebase credentials, new messages also emit a data-only wake-up tick.
  ``POST /test`` fires a self-test tick for the settings screen.
"""
from datetime import datetime

from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required

from app import db
from app.models.chat import Chat, ChatMember
from app.models.message import Message
from app.models.user import User, UserDevice
from app.services.message_payloads import user_in_chat, visible_messages
from app.services.timestamps import utc_iso

notifications_bp = Blueprint('notifications', __name__)

_PREVIEW_LEN = 140


def _preview(message):
    """Safe one-line preview: never leaks view-once / encrypted content."""
    if message.is_view_once:
        duration = getattr(message, 'view_duration', None)
        if duration:
            return f'📷 عکس زمان‌دار ({duration} ثانیه)'
        return '📷 عکس یک‌بارمصرف'
    if getattr(message, 'is_encrypted', False):
        return '🔒 پیام رمزدار'
    kind = message.message_type or 'text'
    if kind == 'text':
        return (message.content or '').strip()[:_PREVIEW_LEN] or '💬 پیام جدید'
    labels = {
        'image': '📷 عکس',
        'video': '🎬 ویدیو',
        'voice': '🎤 پیام صوتی',
        'audio': '🎵 موسیقی',
        'music': '🎵 موسیقی',
        'file': '📎 فایل',
        'sticker': '😀 استیکر',
        'gif': '🎞 گیف',
        'video_note': '⭕ پیام ویدیویی',
        'round_video': '⭕ پیام ویدیویی',
        'location': '📍 موقعیت مکانی',
        'live_location': '📍 موقعیت زنده',
    }
    base = labels.get(kind, '💬 پیام جدید')
    caption = (message.content or '').strip()
    if caption and kind in ('image', 'video', 'file', 'audio', 'music', 'gif'):
        return f'{base}: {caption[:100]}'
    return base


@notifications_bp.route('/pending', methods=['GET'])
@jwt_required()
def pending():
    user_id = get_jwt_identity()
    try:
        limit = max(1, min(int(request.args.get('limit', 20)), 50))
    except (TypeError, ValueError):
        return jsonify({'error': 'limit نامعتبر است'}), 400

    # First run has no baseline: return only the server clock so the client
    # never floods the user with the whole history as "new" notifications.
    since_raw = (request.args.get('since') or '').strip()
    server_now = datetime.utcnow()
    if not since_raw:
        return jsonify({
            'messages': [],
            'unread_total': 0,
            'server_time': utc_iso(server_now),
        }), 200
    try:
        since_dt = datetime.fromisoformat(since_raw.replace('Z', '+00:00'))
        if since_dt.tzinfo is not None:
            import datetime as _dt
            since_dt = since_dt.astimezone(_dt.timezone.utc).replace(tzinfo=None)
    except (TypeError, ValueError):
        return jsonify({'error': 'since نامعتبر است'}), 400

    memberships = ChatMember.query.filter_by(
        user_id=user_id, is_deleted=False,
    ).all()
    if not memberships:
        return jsonify({
            'messages': [], 'unread_total': 0,
            'server_time': utc_iso(server_now),
        }), 200
    member_by_chat = {m.chat_id: m for m in memberships}
    chats = {
        c.id: c for c in Chat.query.filter(
            Chat.id.in_(list(member_by_chat)),
            Chat.is_deleted.is_(False),
            Chat.is_deleted_for_all.is_(False),
        ).all()
    }
    if not chats:
        return jsonify({
            'messages': [], 'unread_total': 0,
            'server_time': utc_iso(server_now),
        }), 200

    # Titles for private chats come from the peer, exactly like /chats/.
    peer_by_chat = {}
    private_ids = [cid for cid, c in chats.items() if c.chat_type == 'private']
    if private_ids:
        peers = ChatMember.query.filter(
            ChatMember.chat_id.in_(private_ids),
            ChatMember.user_id != user_id,
            ChatMember.is_deleted.is_(False),
        ).all()
        peer_ids = {p.user_id for p in peers}
        users = {u.id: u for u in User.query.filter(
            User.id.in_(peer_ids),
        ).all()} if peer_ids else {}
        for p in peers:
            peer_by_chat[p.chat_id] = users.get(p.user_id)

    rows = visible_messages(user_id).filter(
        Message.chat_id.in_(list(chats)),
        Message.sender_id != user_id,
        Message.created_at > since_dt,
    ).order_by(Message.created_at.asc(), Message.id.asc()).limit(limit).all()

    sender_ids = {m.sender_id for m in rows}
    senders = {u.id: u for u in User.query.filter(
        User.id.in_(sender_ids),
    ).all()} if sender_ids else {}

    items = []
    for msg in rows:
        chat = chats.get(msg.chat_id)
        if chat is None:
            continue
        member = member_by_chat.get(msg.chat_id)
        if chat.chat_type == 'private':
            peer = peer_by_chat.get(msg.chat_id)
            title = peer.display_name if peer else (chat.title or 'چت')
        elif chat.chat_type == 'saved':
            title = 'پیام‌های ذخیره‌شده'
        else:
            title = chat.title or 'گروه'
        sender = senders.get(msg.sender_id)
        items.append({
            'id': msg.id,
            'chat_id': msg.chat_id,
            'chat_type': chat.chat_type,
            'chat_title': title,
            'is_muted': bool(member.is_muted) if member else False,
            'sender_id': msg.sender_id,
            'sender_name': sender.display_name if sender else None,
            'message_type': msg.message_type,
            'preview': _preview(msg),
            'created_at': utc_iso(msg.created_at),
        })

    # Total unread across all chats (bounded: one query per chat is too
    # heavy for background polling, so count globally with one query).
    unread_total = visible_messages(user_id).filter(
        Message.chat_id.in_(list(chats)),
        Message.sender_id != user_id,
    ).count()
    # Cap the counter: the phone only needs "9+" style badges.
    unread_total = min(unread_total, 999)

    return jsonify({
        'messages': items,
        'unread_total': unread_total,
        'server_time': utc_iso(server_now),
    }), 200


@notifications_bp.route('/register', methods=['POST'])
@jwt_required()
def register():
    """Store notification preference (+ optional future push token)."""
    user_id = get_jwt_identity()
    device_id = get_jwt().get('device_id')
    data = request.get_json(silent=True) or {}
    enabled = data.get('notifications_enabled', True)
    if type(enabled) is not bool:
        return jsonify({'error': 'notifications_enabled must be boolean'}), 400
    push_token = data.get('push_token')
    if push_token is not None and (
            not isinstance(push_token, str) or len(push_token) > 512):
        return jsonify({'error': 'push_token نامعتبر است'}), 400
    platform = data.get('platform')
    if platform is not None and platform not in ('android', 'ios', 'other'):
        return jsonify({'error': 'platform نامعتبر است'}), 400

    device = None
    if device_id:
        device = UserDevice.query.filter_by(
            id=device_id, user_id=user_id,
        ).first()
    if device is None:
        # Legacy tokens carry no device claim: update the most recently
        # active row instead of failing the whole registration.
        device = UserDevice.query.filter_by(
            user_id=user_id, is_deleted=False,
        ).order_by(UserDevice.last_active.desc()).first()
    if device is None:
        return jsonify({'error': 'دستگاهی یافت نشد'}), 404
    device.notifications_enabled = enabled
    # An explicit empty/null token clears the stored one (logout path), so
    # a signed-out phone stops buzzing. Omitting the key leaves it alone.
    if 'push_token' in data:
        if push_token:
            device.push_token = push_token
            device.push_platform = platform or 'android'
        else:
            device.push_token = None
            device.push_platform = None
    device.last_active = datetime.utcnow()
    db.session.commit()
    return jsonify({'ok': True, 'notifications_enabled': enabled}), 200


@notifications_bp.route('/test', methods=['POST'])
@jwt_required()
def test():
    """Fire a self-test FCM tick at the caller's own devices.

    Powers the "send test notification" button in the app's connection
    settings. 404 when the server has no FCM credentials so the app can
    explain that push is not configured instead of failing silently.
    """
    from app.services.push_service import notify_test, push_configured
    if not push_configured():
        return jsonify({
            'ok': False, 'error': 'push_not_configured',
        }), 404
    user_id = get_jwt_identity()
    delivered = notify_test(current_app._get_current_object(), user_id)
    return jsonify({'ok': True, 'delivered': delivered}), 200


@notifications_bp.route('/unread', methods=['GET'])
@jwt_required()
def unread():
    """Badge counter for the app icon (one cheap aggregated query)."""
    user_id = get_jwt_identity()
    chat_ids = [
        m.chat_id for m in ChatMember.query.join(Chat).filter(
            ChatMember.user_id == user_id,
            ChatMember.is_deleted.is_(False),
            Chat.is_deleted.is_(False),
            Chat.is_deleted_for_all.is_(False),
        ).all()
    ]
    if not chat_ids:
        return jsonify({'unread_total': 0}), 200
    total = visible_messages(user_id).filter(
        Message.chat_id.in_(chat_ids),
        Message.sender_id != user_id,
    ).count()
    return jsonify({'unread_total': min(total, 999)}), 200
