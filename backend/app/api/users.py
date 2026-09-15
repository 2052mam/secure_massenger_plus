from app.services.request_validation import validate_object_body
from app.services.timestamps import utc_iso
from flask import Blueprint, request, jsonify, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity
from app import db
from app.models.user import User, BlockList, UserDevice
from app.models.chat import Chat
from app.models.profile import SearchHistory, UserPhoto
from app.models.audit import AuditLog
from app.services.archive_lock import ARCHIVE_TOKEN_TTL, create_archive_token
from datetime import datetime
import re

users_bp = Blueprint('users', __name__)

users_bp.before_request(validate_object_body)

MAX_PROFILE_PHOTOS = 30
MAX_SEARCH_HISTORY = 20


def get_client_ip():
    return request.headers.get('X-Forwarded-For', request.remote_addr)

@users_bp.route('/me', methods=['GET'])
@jwt_required()
def get_me():
    user_id = get_jwt_identity()
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    return jsonify(user.to_dict(include_private=True)), 200


@users_bp.route('/me', methods=['PUT'])
@jwt_required()
def update_me():
    user_id = get_jwt_identity()
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404

    data = request.get_json() or {}
    if 'allow_group_adds' in data:
        if type(data['allow_group_adds']) is not bool:
            return jsonify({'error': 'allow_group_adds must be boolean'}), 400
        user.allow_group_adds = data['allow_group_adds']
    if 'allow_forwarding' in data:
        if type(data['allow_forwarding']) is not bool:
            return jsonify({'error': 'allow_forwarding must be boolean'}), 400
        user.allow_forwarding = data['allow_forwarding']
    if 'display_name' in data:
        display_name = (data['display_name'] or '').strip()[:100]
        if not display_name:
            return jsonify({'error': 'نام نمایشی نمی‌تواند خالی باشد'}), 400
        user.display_name = display_name
    if 'bio' in data:
        # Saving the bio must never depend on the other fields of the request:
        # an empty string clears it, any text is stored trimmed to 500 chars.
        raw_bio = data['bio']
        if raw_bio is not None and not isinstance(raw_bio, str):
            return jsonify({'error': 'بایو نامعتبر است'}), 400
        bio = (raw_bio or '').strip()[:500]
        user.bio = bio or None
    if 'username' in data:
        # Telegram-like: username is OPTIONAL. Empty string / null removes it.
        raw = data['username']
        new_username = (raw or '').strip().lower() if isinstance(raw, str) else ''
        new_username = new_username or None
        current = (user.username or '').lower() or None
        # Resending the unchanged username must not fail the whole update.
        if new_username != current:
            if new_username is None:
                user.username = None
            else:
                if not re.match(r'^[a-z0-9_]{3,30}$', new_username):
                    return jsonify({'error': 'نام کاربری نامعتبر'}), 400
                existing = User.query.filter(User.username == new_username, User.id != user.id, User.is_deleted == False).first()
                if existing:
                    return jsonify({'error': 'نام کاربری قبلاً گرفته شده'}), 409
                user.username = new_username
    if 'show_last_seen' in data:
        user.show_last_seen = bool(data['show_last_seen'])
    if 'show_profile_photo' in data:
        user.show_profile_photo = bool(data['show_profile_photo'])
    if 'show_bio' in data:
        user.show_bio = bool(data['show_bio'])
    if 'avatar_url' in data:
        user.avatar_url = data['avatar_url'] or None
        _sync_album_with_avatar(user)

    user.updated_at = datetime.utcnow()
    db.session.add(AuditLog(
        actor_id=user.id, action='profile_update', entity_type='user', entity_id=user.id,
        ip_address=get_client_ip()
    ))
    db.session.commit()
    return jsonify(user.to_dict(include_private=True)), 200


# ----- Profile photo album (users only; groups/channels keep one avatar) ----

def _album(user_id):
    return UserPhoto.query.filter_by(user_id=user_id, is_deleted=False).order_by(
        UserPhoto.is_main.desc(), UserPhoto.position.desc(),
        UserPhoto.created_at.desc())


def _sync_album_with_avatar(user):
    """Keep the legacy single avatar_url and the album consistent both ways."""
    photos = _album(user.id).all()
    if user.avatar_url:
        match = next((p for p in photos if p.photo_url == user.avatar_url), None)
        if match is None:
            match = UserPhoto(user_id=user.id, photo_url=user.avatar_url,
                              position=len(photos))
            db.session.add(match)
        for photo in photos:
            photo.is_main = False
        match.is_main = True
    else:
        for photo in photos:
            photo.is_main = False


@users_bp.route('/me/photos', methods=['GET'])
@jwt_required()
def list_my_photos():
    user_id = get_jwt_identity()
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    # Backfill installations created before the album existed.
    if user.avatar_url and not _album(user_id).first():
        _sync_album_with_avatar(user)
        db.session.commit()
    return jsonify({'photos': [p.to_dict() for p in _album(user_id).all()]}), 200


@users_bp.route('/me/photos', methods=['POST'])
@jwt_required()
def add_my_photo():
    """Add another profile photo; the newest one becomes the main avatar."""
    user_id = get_jwt_identity()
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    data = request.get_json() or {}
    photo_url = (data.get('photo_url') or '').strip()
    if not photo_url or len(photo_url) > 500:
        return jsonify({'error': 'آدرس عکس نامعتبر است'}), 400
    photos = _album(user_id).all()
    if len(photos) >= MAX_PROFILE_PHOTOS:
        return jsonify({'error': f'حداکثر {MAX_PROFILE_PHOTOS} عکس پروفایل مجاز است'}), 400
    for photo in photos:
        photo.is_main = False
    photo = UserPhoto(user_id=user_id, photo_url=photo_url,
                      media_id=data.get('media_id') if isinstance(data.get('media_id'), str) else None,
                      is_main=True, position=len(photos))
    db.session.add(photo)
    user.avatar_url = photo_url
    user.updated_at = datetime.utcnow()
    db.session.add(AuditLog(actor_id=user_id, action='add_profile_photo',
                            entity_type='user', entity_id=user_id,
                            ip_address=get_client_ip()))
    db.session.commit()
    return jsonify({'photo': photo.to_dict(),
                    'photos': [p.to_dict() for p in _album(user_id).all()],
                    'avatar_url': user.avatar_url}), 201


@users_bp.route('/me/photos/<photo_id>/main', methods=['POST'])
@jwt_required()
def set_main_photo(photo_id):
    user_id = get_jwt_identity()
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    photo = UserPhoto.query.filter_by(id=photo_id, user_id=user_id, is_deleted=False).first()
    if not user or not photo:
        return jsonify({'error': 'عکس یافت نشد'}), 404
    for other in _album(user_id).all():
        other.is_main = other.id == photo.id
    photo.is_main = True
    user.avatar_url = photo.photo_url
    user.updated_at = datetime.utcnow()
    db.session.commit()
    return jsonify({'photos': [p.to_dict() for p in _album(user_id).all()],
                    'avatar_url': user.avatar_url}), 200


@users_bp.route('/me/photos/<photo_id>/delete', methods=['POST'])
@jwt_required()
def delete_my_photo(photo_id):
    user_id = get_jwt_identity()
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    photo = UserPhoto.query.filter_by(id=photo_id, user_id=user_id, is_deleted=False).first()
    if not user or not photo:
        return jsonify({'error': 'عکس یافت نشد'}), 404
    photo.is_deleted = True
    photo.deleted_at = datetime.utcnow()
    photo.is_main = False
    db.session.flush()
    remaining = _album(user_id).all()
    # Telegram promotes the previous photo when the main one is removed.
    for index, other in enumerate(remaining):
        other.is_main = index == 0
    user.avatar_url = remaining[0].photo_url if remaining else None
    user.updated_at = datetime.utcnow()
    db.session.add(AuditLog(actor_id=user_id, action='delete_profile_photo',
                            entity_type='user', entity_id=user_id,
                            ip_address=get_client_ip()))
    db.session.commit()
    return jsonify({'photos': [p.to_dict() for p in _album(user_id).all()],
                    'avatar_url': user.avatar_url}), 200


@users_bp.route('/<user_id>/photos', methods=['GET'])
@jwt_required()
def list_user_photos(user_id):
    """Another user's album, honouring their profile-photo privacy switch."""
    viewer_id = get_jwt_identity()
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    if user_id != viewer_id and not user.show_profile_photo:
        return jsonify({'photos': []}), 200
    photos = _album(user_id).all()
    if not photos and user.avatar_url:
        return jsonify({'photos': [{'id': 'avatar', 'photo_url': user.avatar_url,
                                    'media_id': None, 'is_main': True,
                                    'position': 0, 'created_at': None}]}), 200
    return jsonify({'photos': [p.to_dict() for p in photos]}), 200


# ----- Archive PIN ---------------------------------------------------------

def _valid_pin(value):
    return isinstance(value, str) and re.fullmatch(r'\d{4}', value) is not None


@users_bp.route('/me/archive-pin', methods=['POST'])
@jwt_required()
def set_archive_pin():
    """Set or change the 4 digit archive PIN (changing needs the current one)."""
    user_id = get_jwt_identity()
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    data = request.get_json() or {}
    pin = data.get('pin')
    if not _valid_pin(pin):
        return jsonify({'error': 'رمز آرشیو باید دقیقاً ۴ رقم باشد'}), 400
    if user.has_archive_pin and not user.check_archive_pin(data.get('current_pin') or ''):
        return jsonify({'error': 'رمز فعلی آرشیو نادرست است'}), 403
    user.set_archive_pin(pin)
    db.session.add(AuditLog(actor_id=user_id, action='set_archive_pin',
                            entity_type='user', entity_id=user_id,
                            ip_address=get_client_ip()))
    db.session.commit()
    return jsonify({'ok': True, 'has_archive_pin': True,
                    'archive_token': create_archive_token(user),
                    'expires_in': int(ARCHIVE_TOKEN_TTL.total_seconds())}), 200


@users_bp.route('/me/archive-pin/verify', methods=['POST'])
@jwt_required()
def verify_archive_pin():
    """Exchange the PIN for a short lived unlock token; the PIN is never stored."""
    user_id = get_jwt_identity()
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    if not user.has_archive_pin:
        return jsonify({'ok': True, 'has_archive_pin': False, 'archive_token': None}), 200
    data = request.get_json() or {}
    if not user.check_archive_pin(data.get('pin') or ''):
        db.session.add(AuditLog(actor_id=user_id, action='archive_pin_failed',
                                entity_type='user', entity_id=user_id,
                                ip_address=get_client_ip()))
        db.session.commit()
        return jsonify({'error': 'رمز آرشیو نادرست است'}), 403
    return jsonify({'ok': True, 'has_archive_pin': True,
                    'archive_token': create_archive_token(user),
                    'expires_in': int(ARCHIVE_TOKEN_TTL.total_seconds())}), 200


@users_bp.route('/me/archive-pin/remove', methods=['POST'])
@jwt_required()
def remove_archive_pin():
    user_id = get_jwt_identity()
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    if user.has_archive_pin:
        data = request.get_json() or {}
        if not user.check_archive_pin(data.get('pin') or ''):
            return jsonify({'error': 'رمز آرشیو نادرست است'}), 403
        user.clear_archive_pin()
        db.session.add(AuditLog(actor_id=user_id, action='remove_archive_pin',
                                entity_type='user', entity_id=user_id,
                                ip_address=get_client_ip()))
        db.session.commit()
    return jsonify({'ok': True, 'has_archive_pin': False}), 200


# ----- Recent searches -----------------------------------------------------

def _history_payload(entry):
    user = (User.query.filter_by(id=entry.target_user_id, is_deleted=False).first()
            if entry.target_user_id else None)
    chat = (Chat.query.filter_by(id=entry.target_chat_id, is_deleted=False).first()
            if entry.target_chat_id else None)
    return {
        'id': entry.id,
        'query': entry.term,
        'created_at': utc_iso(entry.updated_at or entry.created_at),
        'user': user.to_dict() if user else None,
        'chat': {'id': chat.id, 'chat_type': chat.chat_type, 'title': chat.title,
                 'username': chat.username, 'avatar_url': chat.avatar_url} if chat else None,
    }


def _recent_searches(user_id):
    return db.session.query(SearchHistory).filter_by(
        user_id=user_id, is_deleted=False
    ).order_by(SearchHistory.updated_at.desc(), SearchHistory.created_at.desc())


@users_bp.route('/search-history', methods=['GET'])
@jwt_required()
def get_search_history():
    """Recent searches, newest first: find someone again after deleting the chat."""
    user_id = get_jwt_identity()
    entries = _recent_searches(user_id).limit(MAX_SEARCH_HISTORY).all()
    return jsonify({'items': [_history_payload(entry) for entry in entries]}), 200


@users_bp.route('/search-history', methods=['POST'])
@jwt_required()
def add_search_history():
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    term = (data.get('query') or '').strip()[:120]
    target_user_id = data.get('user_id')
    target_chat_id = data.get('chat_id')
    if target_user_id is not None and not isinstance(target_user_id, str):
        return jsonify({'error': 'user_id نامعتبر است'}), 400
    if target_chat_id is not None and not isinstance(target_chat_id, str):
        return jsonify({'error': 'chat_id نامعتبر است'}), 400
    if not term and not target_user_id and not target_chat_id:
        return jsonify({'error': 'مورد جستجو خالی است'}), 400

    duplicates = db.session.query(SearchHistory).filter_by(
        user_id=user_id, is_deleted=False,
        target_user_id=target_user_id, target_chat_id=target_chat_id)
    if not target_user_id and not target_chat_id:
        duplicates = duplicates.filter(SearchHistory.term == term)
    entry = duplicates.first()

    now = datetime.utcnow()
    if entry:
        entry.term = term or entry.term
        entry.updated_at = now
    else:
        entry = SearchHistory(user_id=user_id, term=term or None,
                              target_user_id=target_user_id,
                              target_chat_id=target_chat_id,
                              created_at=now, updated_at=now)
        db.session.add(entry)
    db.session.flush()

    # Keep the list short: soft delete everything past the newest entries.
    for old in _recent_searches(user_id).offset(MAX_SEARCH_HISTORY).all():
        old.is_deleted = True
        old.deleted_at = now
    db.session.commit()
    return jsonify({'item': _history_payload(entry)}), 201


@users_bp.route('/search-history/<entry_id>/delete', methods=['POST'])
@jwt_required()
def delete_search_history_entry(entry_id):
    user_id = get_jwt_identity()
    entry = db.session.query(SearchHistory).filter_by(
        id=entry_id, user_id=user_id, is_deleted=False).first()
    if entry:
        entry.is_deleted = True
        entry.deleted_at = datetime.utcnow()
        db.session.commit()
    return jsonify({'ok': True}), 200


@users_bp.route('/search-history/clear', methods=['POST'])
@jwt_required()
def clear_search_history():
    user_id = get_jwt_identity()
    db.session.query(SearchHistory).filter_by(user_id=user_id, is_deleted=False).update({
        'is_deleted': True, 'deleted_at': datetime.utcnow(),
    }, synchronize_session=False)
    db.session.commit()
    return jsonify({'ok': True}), 200


@users_bp.route('/search', methods=['GET'])
@jwt_required()
def search_users():
    q = (request.args.get('q') or '').strip().lower()
    if len(q) < 2:
        return jsonify({'users': [], 'chats': []}), 200

    current_id = get_jwt_identity()

    users = User.query.filter(
        User.is_deleted == False,
        User.is_active == True,
        User.id != current_id,
        (User.id == q) | User.username.ilike(f'%{q.lstrip("@")}%') | User.display_name.ilike(f'%{q}%')
    ).limit(30).all()

    result_users = []
    for u in users:
        blocked = BlockList.query.filter(
            ((BlockList.blocker_id == current_id) & (BlockList.blocked_id == u.id)) |
            ((BlockList.blocker_id == u.id) & (BlockList.blocked_id == current_id)),
            BlockList.is_deleted == False
        ).first()
        if not blocked:
            result_users.append(u.to_dict())

    from app.models.chat import Chat
    chats = Chat.query.filter(
        Chat.is_deleted == False,
        Chat.is_public == True,
        Chat.chat_type == 'channel',
        (Chat.title.ilike(f'%{q}%') | Chat.username.ilike(f'%{q}%'))
    ).limit(20).all()

    result_chats = [{
        'id': c.id,
        'chat_type': c.chat_type,
        'title': c.title,
        'username': c.username,
        'avatar_url': c.avatar_url,
    } for c in chats]

    return jsonify({'users': result_users, 'chats': result_chats}), 200


@users_bp.route('/by-username/<username>', methods=['GET'])
@jwt_required()
def get_user_by_username(username):
    """Resolve an @id mention to a user (tap @username in chat → profile/chat)."""
    handle = (username or '').strip().lstrip('@').lower()
    if not handle or not re.match(r'^[a-z0-9_]{3,30}$', handle):
        return jsonify({'error': 'شناسه نامعتبر است'}), 400
    user = User.query.filter_by(username=handle, is_deleted=False).first()
    if not user or not user.is_active:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    return jsonify(user.to_dict()), 200


@users_bp.route('/me/terms', methods=['POST'])
@jwt_required()
def accept_terms():
    """Record rules acceptance (registration dialog + settings page)."""
    user_id = get_jwt_identity()
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    data = request.get_json() or {}
    try:
        version = int(data.get('terms_version', 1) or 1)
    except (TypeError, ValueError):
        version = 1
    user.terms_version = version
    user.terms_accepted_at = datetime.utcnow()
    db.session.add(AuditLog(actor_id=user_id, action='accept_terms',
                            entity_type='user', entity_id=user_id,
                            ip_address=get_client_ip()))
    db.session.commit()
    return jsonify({'ok': True, 'terms_version': version,
                    'terms_accepted_at': utc_iso(user.terms_accepted_at)}), 200


@users_bp.route('/<user_id>', methods=['GET'])
@jwt_required()
def get_user(user_id):
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    return jsonify(user.to_dict()), 200


@users_bp.route('/block/<user_id>', methods=['POST'])
@jwt_required()
def block_user(user_id):
    current_id = get_jwt_identity()
    if current_id == user_id:
        return jsonify({'error': 'نمی‌توانید خودتان را بلاک کنید'}), 400

    target = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not target:
        return jsonify({'error': 'کاربر یافت نشد'}), 404

    existing = BlockList.query.filter_by(blocker_id=current_id, blocked_id=user_id).first()
    if existing and not existing.is_deleted:
        return jsonify({'message': 'قبلاً بلاک شده'}), 200

    if existing:
        existing.is_deleted = False
        existing.deleted_at = None
    else:
        db.session.add(BlockList(blocker_id=current_id, blocked_id=user_id))

    db.session.add(AuditLog(
        actor_id=current_id, action='block_user', entity_type='user', entity_id=user_id,
        ip_address=get_client_ip()
    ))
    db.session.commit()
    return jsonify({'message': 'کاربر بلاک شد'}), 200


@users_bp.route('/unblock/<user_id>', methods=['POST'])
@jwt_required()
def unblock_user(user_id):
    current_id = get_jwt_identity()
    block = BlockList.query.filter_by(blocker_id=current_id, blocked_id=user_id, is_deleted=False).first()
    if not block:
        return jsonify({'message': 'بلاک نبود'}), 200

    block.is_deleted = True
    block.deleted_at = datetime.utcnow()
    db.session.add(AuditLog(
        actor_id=current_id, action='unblock_user', entity_type='user', entity_id=user_id,
        ip_address=get_client_ip()
    ))
    db.session.commit()
    return jsonify({'message': 'آنبلاک شد'}), 200


@users_bp.route('/online-status', methods=['POST'])
@jwt_required()
def update_online_status():
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    is_online = bool(data.get('is_online', True))

    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404

    user.is_online = is_online
    user.last_seen = datetime.utcnow()
    db.session.commit()
    return jsonify({'ok': True}), 200


@users_bp.route('/blocked', methods=['GET'])
@jwt_required()
def get_blocked():
    current_id = get_jwt_identity()
    blocks = BlockList.query.filter_by(blocker_id=current_id, is_deleted=False).all()
    users = []
    for b in blocks:
        u = User.query.get(b.blocked_id)
        if u and not u.is_deleted:
            users.append(u.to_dict())
    return jsonify({'users': users}), 200
