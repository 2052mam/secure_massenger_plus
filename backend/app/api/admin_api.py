from app.services.timestamps import utc_iso
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from app import db
from app.models.user import User, UserDevice, BlockList
from app.models.chat import Chat, ChatMember
from app.models.message import Message
from app.models.media import MediaFile
from app.models.audit import AuditLog
from datetime import datetime, timedelta

admin_api_bp = Blueprint('admin_api', __name__)

def require_admin():
    user_id = get_jwt_identity()
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user or not user.is_admin:
        return None
    return user


@admin_api_bp.route('/dashboard', methods=['GET'])
@jwt_required()
def dashboard():
    admin = require_admin()
    if not admin:
        return jsonify({'error': 'دسترسی ادمین ندارید'}), 403

    users_count = User.query.filter_by(is_deleted=False).count()
    chats_count = Chat.query.filter_by(is_deleted=False).count()
    messages_count = Message.query.filter_by(is_deleted=False).count()
    online_count = User.query.filter_by(is_online=True, is_deleted=False).count()
    media_count = MediaFile.query.filter_by(is_deleted=False).count()
    devices_count = UserDevice.query.filter_by(is_deleted=False).count()

    return jsonify({
        'users': users_count,
        'chats': chats_count,
        'messages': messages_count,
        'online': online_count,
        'media': media_count,
        'devices': devices_count,
    }), 200


@admin_api_bp.route('/users', methods=['GET'])
@jwt_required()
def list_users():
    admin = require_admin()
    if not admin:
        return jsonify({'error': 'دسترسی ادمین ندارید'}), 403

    page = int(request.args.get('page', 1))
    per_page = min(int(request.args.get('per_page', 50)), 100)
    q = request.args.get('q', '').strip()

    query = User.query.filter_by(is_deleted=False)
    if q:
        query = query.filter(
            (User.username.ilike(f'%{q}%')) |
            (User.email.ilike(f'%{q}%')) |
            (User.display_name.ilike(f'%{q}%'))
        )

    pagination = query.order_by(User.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    users = [u.to_dict(include_private=True) for u in pagination.items]
    return jsonify({
        'users': users,
        'total': pagination.total,
        'page': page,
        'pages': pagination.pages,
    }), 200


@admin_api_bp.route('/users/<user_id>/ban', methods=['POST'])
@jwt_required()
def ban_user(user_id):
    admin = require_admin()
    if not admin:
        return jsonify({'error': 'دسترسی ادمین ندارید'}), 403

    user = User.query.get(user_id)
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404

    user.is_active = False
    db.session.add(AuditLog(actor_id=admin.id, action='admin_ban_user', entity_type='user', entity_id=user_id))
    db.session.commit()
    return jsonify({'message': 'کاربر غیرفعال شد'}), 200


@admin_api_bp.route('/users/<user_id>/unban', methods=['POST'])
@jwt_required()
def unban_user(user_id):
    admin = require_admin()
    if not admin:
        return jsonify({'error': 'دسترسی ادمین ندارید'}), 403

    user = User.query.get(user_id)
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404

    user.is_active = True
    db.session.add(AuditLog(actor_id=admin.id, action='admin_unban_user', entity_type='user', entity_id=user_id))
    db.session.commit()
    return jsonify({'message': 'کاربر فعال شد'}), 200


@admin_api_bp.route('/messages', methods=['GET'])
@jwt_required()
def list_messages():
    admin = require_admin()
    if not admin:
        return jsonify({'error': 'دسترسی ادمین ندارید'}), 403

    page = int(request.args.get('page', 1))
    per_page = min(int(request.args.get('per_page', 50)), 100)
    chat_id = request.args.get('chat_id')

    query = Message.query
    if chat_id:
        query = query.filter_by(chat_id=chat_id)

    pagination = query.order_by(Message.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    msgs = []
    for m in pagination.items:
        msgs.append({
            'id': m.id,
            'chat_id': m.chat_id,
            'sender_id': m.sender_id,
            'content': m.content,
            'message_type': m.message_type,
            'is_deleted': m.is_deleted,
            'is_deleted_for_all': m.is_deleted_for_all,
            'created_at': utc_iso(m.created_at),
        })
    return jsonify({'messages': msgs, 'total': pagination.total, 'page': page}), 200


@admin_api_bp.route('/audit', methods=['GET'])
@jwt_required()
def list_audit():
    admin = require_admin()
    if not admin:
        return jsonify({'error': 'دسترسی ادمین ندارید'}), 403

    page = int(request.args.get('page', 1))
    per_page = min(int(request.args.get('per_page', 50)), 100)

    pagination = AuditLog.query.order_by(AuditLog.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    logs = [{
        'id': l.id,
        'actor_id': l.actor_id,
        'action': l.action,
        'entity_type': l.entity_type,
        'entity_id': l.entity_id,
        'ip_address': l.ip_address,
        'created_at': utc_iso(l.created_at),
    } for l in pagination.items]
    return jsonify({'logs': logs, 'total': pagination.total}), 200


@admin_api_bp.route('/chats', methods=['GET'])
@jwt_required()
def list_chats_admin():
    admin = require_admin()
    if not admin:
        return jsonify({'error': 'دسترسی ادمین ندارید'}), 403

    page = int(request.args.get('page', 1))
    per_page = min(int(request.args.get('per_page', 50)), 100)

    pagination = Chat.query.order_by(Chat.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    chats = [{
        'id': c.id,
        'chat_type': c.chat_type,
        'title': c.title,
        'username': c.username,
        'created_by': c.created_by,
        'is_deleted': c.is_deleted,
        'is_sponsored': bool(getattr(c, 'is_sponsored', False)),
        'sponsored_at': utc_iso(c.sponsored_at) if getattr(c, 'sponsored_at', None) else None,
        'created_at': utc_iso(c.created_at),
    } for c in pagination.items]
    return jsonify({'chats': chats, 'total': pagination.total}), 200


@admin_api_bp.route('/sponsored', methods=['GET'])
@jwt_required()
def list_sponsored_admin():
    """All sponsored channels (general app admin only)."""
    admin = require_admin()
    if not admin:
        return jsonify({'error': 'دسترسی ادمین ندارید'}), 403
    channels = Chat.query.filter_by(chat_type='channel', is_deleted=False,
                                    is_sponsored=True).order_by(
        Chat.sponsored_at.desc()).all()
    return jsonify({'channels': [{
        'id': c.id, 'title': c.title, 'username': c.username,
        'description': c.description, 'avatar_url': c.avatar_url,
        'is_public': bool(c.is_public), 'is_sponsored': True,
        'sponsored_at': utc_iso(c.sponsored_at) if c.sponsored_at else None,
        'sponsored_by': c.sponsored_by,
    } for c in channels]}), 200


@admin_api_bp.route('/chats/<chat_id>/sponsor', methods=['POST'])
@jwt_required()
def sponsor_channel(chat_id):
    """Sponsor / unsponsor a channel (general app admin only).

    Body: {"is_sponsored": true|false}. Sponsored channels are visible to
    everyone in their accounts (see GET /chats/sponsored).
    """
    admin = require_admin()
    if not admin:
        return jsonify({'error': 'دسترسی ادمین ندارید'}), 403
    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'چت یافت نشد'}), 404
    if chat.chat_type != 'channel':
        return jsonify({'error': 'فقط کانال‌ها می‌توانند اسپانسر شوند'}), 400
    data = request.get_json() or {}
    value = data.get('is_sponsored', True)
    if type(value) is not bool:
        return jsonify({'error': 'is_sponsored must be boolean'}), 400
    chat.is_sponsored = value
    chat.sponsored_at = datetime.utcnow() if value else None
    chat.sponsored_by = admin.id if value else None
    db.session.add(AuditLog(actor_id=admin.id,
                            action='sponsor_channel' if value else 'unsponsor_channel',
                            entity_type='chat', entity_id=chat_id))
    db.session.commit()
    return jsonify({'ok': True, 'is_sponsored': chat.is_sponsored}), 200
