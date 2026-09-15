from app.services.request_validation import validate_object_body
from app.services.timestamps import utc_iso
import re
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from app import db
from app.models.user import User, BlockList
from app.models.chat import Chat, ChatMember, ChatBackground
from app.models.folder import ChatFolder, ChatFolderItem
from app.models.message import Message, MessageStatus, PinnedMessage
from app.models.media import MediaFile
from app.models.audit import AuditLog
from app.services.archive_lock import archive_unlocked
from app.services.message_payloads import visible_messages, serialize_messages, user_in_chat
from datetime import datetime
import uuid
from werkzeug.exceptions import HTTPException
from app.services.chat_permissions import (can, capabilities, group_permissions,
    admin_permissions, validate_permissions, GROUP_DEFAULTS, ADMIN_DEFAULTS)
from app.services.member_invitations import add_or_invite

chats_bp = Blueprint('chats', __name__)

chats_bp.before_request(validate_object_body)

MAX_FOLDERS = 20
MAX_FOLDER_CHATS = 200


def get_client_ip():
    return request.headers.get('X-Forwarded-For', request.remote_addr)


def _truthy(value):
    return (value or '').strip().lower() in ('1', 'true', 'yes', 'on')


@chats_bp.route('/', methods=['GET'])
@jwt_required()
def list_chats():
    """لیست چت‌های کاربر با آخرین پیام (برای Polling)

    ``?archived=1`` returns the archived folder instead of the main list. When
    an archive PIN is configured the caller must also send a valid
    ``X-Archive-Token`` obtained from ``/users/me/archive-pin/verify``.
    """
    user_id = get_jwt_identity()
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    want_archived = _truthy(request.args.get('archived'))
    unlocked = archive_unlocked(user)
    if want_archived and not unlocked:
        return jsonify({'error': 'آرشیو قفل است', 'archive_locked': True}), 423

    memberships = ChatMember.query.filter_by(user_id=user_id, is_deleted=False).all()

    result = []
    archived_total = 0
    archived_unread = 0
    archived_chats_unread = 0
    for m in memberships:
        chat = Chat.query.filter_by(id=m.chat_id, is_deleted=False).first()
        if not chat:
            continue

        visible = visible_messages(user_id).filter(Message.chat_id == chat.id)
        last_msg = visible.order_by(Message.created_at.desc(), Message.id.desc()).first()
        unread_query = visible.filter(Message.sender_id != user_id)
        if m.last_read_message_id:
            read_msg = db.session.get(Message, m.last_read_message_id)
            if read_msg and read_msg.chat_id == chat.id:
                unread_query = unread_query.filter(Message.created_at > read_msg.created_at)
        unread = unread_query.count()

        if m.is_archived:
            archived_total += 1
            archived_unread += unread
            if unread:
                archived_chats_unread += 1
        if bool(m.is_archived) != want_archived:
            continue

        # برای چت خصوصی طرف مقابل را پیدا کن
        other_user = None
        title = chat.title
        avatar = chat.avatar_url
        if chat.chat_type == 'private':
            other_member = ChatMember.query.filter(
                ChatMember.chat_id == chat.id,
                ChatMember.user_id != user_id,
                ChatMember.is_deleted == False
            ).first()
            if other_member:
                other_user = User.query.filter_by(id=other_member.user_id, is_deleted=False).first()
                if other_user:
                    title = other_user.display_name
                    avatar = other_user.avatar_url if other_user.show_profile_photo else None

        result.append({
            'id': chat.id,
            'chat_type': chat.chat_type,
            'title': title,
            'username': chat.username,
            'avatar_url': avatar,
            'is_pinned': bool(m.is_pinned),
            'pinned_at': utc_iso(m.pinned_at) if m.pinned_at else None,
            'is_archived': bool(m.is_archived),
            'is_muted': m.is_muted,
            'is_sponsored': bool(getattr(chat, 'is_sponsored', False)),
            'allow_forwarding': bool(getattr(chat, 'allow_forwarding', True)) if getattr(chat, 'allow_forwarding', True) is not None else True,
            'unread_count': unread,
            'last_message': {
                'id': last_msg.id if last_msg else None,
                'content': last_msg.content if last_msg else None,
                'message_type': last_msg.message_type if last_msg else None,
                'sender_id': (chat.id if chat.chat_type == 'channel' else last_msg.sender_id) if last_msg else None,
                'created_at': utc_iso(last_msg.created_at) if last_msg else None,
            } if last_msg else None,
            'updated_at': utc_iso(chat.updated_at),
            'other_user': other_user.to_dict() if other_user else None,
        })

    # مرتب‌سازی: پین‌شده‌ها اول (تازه‌ترین پین بالاتر)، بعد بر اساس آخرین پیام
    def sort_key(item):
        activity = (item['last_message']['created_at'] if item['last_message']
                    else item['updated_at']) or ''
        return (1 if item['is_pinned'] else 0, item['pinned_at'] or '', activity)

    result.sort(key=sort_key, reverse=True)
    # Sponsored channels are visible to everyone (Telegram-like). They are
    # returned separately so the app can render a banner/section on top.
    sponsored = []
    if not want_archived:
        for c in Chat.query.filter_by(chat_type='channel', is_deleted=False,
                                      is_sponsored=True).order_by(
                Chat.sponsored_at.desc()).limit(20).all():
            members_count = ChatMember.query.filter_by(chat_id=c.id,
                                                       is_deleted=False).count()
            sponsored.append({
                'id': c.id, 'chat_type': c.chat_type, 'title': c.title,
                'username': c.username, 'description': c.description,
                'avatar_url': c.avatar_url, 'is_public': bool(c.is_public),
                'is_sponsored': True,
                'sponsored_at': utc_iso(c.sponsored_at) if c.sponsored_at else None,
                'members_count': members_count,
            })
    return jsonify({
        'chats': result,
        'sponsored': sponsored,
        'archived': {
            'total': archived_total,
            'unread': archived_unread,
            'chats_with_unread': archived_chats_unread,
        },
        'archive_locked': bool(user.has_archive_pin) and not unlocked,
        'has_archive_pin': user.has_archive_pin,
    }), 200


@chats_bp.route('/sponsored', methods=['GET'])
@jwt_required()
def list_sponsored():
    """Sponsored channels visible to everyone (set by the general admin)."""
    channels = Chat.query.filter_by(chat_type='channel', is_deleted=False,
                                    is_sponsored=True).order_by(
        Chat.sponsored_at.desc()).all()
    out = []
    for c in channels:
        members_count = ChatMember.query.filter_by(chat_id=c.id,
                                                   is_deleted=False).count()
        out.append({
            'id': c.id, 'chat_type': c.chat_type, 'title': c.title,
            'username': c.username, 'description': c.description,
            'avatar_url': c.avatar_url, 'is_public': bool(c.is_public),
            'is_sponsored': True,
            'sponsored_at': utc_iso(c.sponsored_at) if c.sponsored_at else None,
            'members_count': members_count,
        })
    return jsonify({'channels': out}), 200


@chats_bp.route('/<chat_id>/forwarding', methods=['POST'])
@jwt_required()
def toggle_forwarding(chat_id):
    """Block / allow forwarding from a group/channel (Telegram-like).

    Owner or admin with manage rights can toggle. Private chats use the
    per-user privacy switch instead (see /users/me allow_forwarding).
    """
    user_id = get_jwt_identity()
    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'چت یافت نشد'}), 404
    if chat.chat_type not in ('group', 'channel'):
        return jsonify({'error': 'فقط گروه و کانال این تنظیم را دارند'}), 400
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id,
                                        is_deleted=False).first()
    if not member or member.role not in ('owner', 'admin'):
        return jsonify({'error': 'فقط مدیر می‌تواند این تنظیم را تغییر دهد'}), 403
    if member.role != 'owner' and not can(chat, user_id, 'manage_permissions'):
        return jsonify({'error': 'دسترسی ندارید'}), 403
    data = request.get_json() or {}
    value = data.get('allow_forwarding')
    if type(value) is not bool:
        return jsonify({'error': 'allow_forwarding must be boolean'}), 400
    chat.allow_forwarding = value
    db.session.add(AuditLog(actor_id=user_id, action='toggle_forwarding',
                            entity_type='chat', entity_id=chat_id,
                            ip_address=get_client_ip()))
    db.session.commit()
    return jsonify({'ok': True, 'allow_forwarding': chat.allow_forwarding}), 200


@chats_bp.route('/<chat_id>/archive', methods=['POST'])
@jwt_required()
def archive_chat(chat_id):
    """Move a chat in or out of the archived folder (per user, like Telegram)."""
    user_id = get_jwt_identity()
    member = ChatMember.query.join(Chat).filter(
        ChatMember.chat_id == chat_id, ChatMember.user_id == user_id,
        ChatMember.is_deleted.is_(False), Chat.is_deleted.is_(False)).first()
    if not member:
        return jsonify({'error': 'دسترسی ندارید'}), 403
    data = request.get_json() or {}
    value = data.get('is_archived', True)
    if type(value) is not bool:
        return jsonify({'error': 'is_archived must be boolean'}), 400
    member.is_archived = value
    member.archived_at = datetime.utcnow() if value else None
    if value:
        # Telegram never keeps a chat pinned inside the main list once archived.
        member.is_pinned = False
        member.pinned_at = None
    db.session.add(AuditLog(
        actor_id=user_id, action='archive_chat' if value else 'unarchive_chat',
        entity_type='chat', entity_id=chat_id, ip_address=get_client_ip()))
    db.session.commit()
    return jsonify({'ok': True, 'is_archived': member.is_archived}), 200


# ----- Chat folders --------------------------------------------------------

def _folder_payload(folder):
    chat_ids = [item.chat_id for item in ChatFolderItem.query.filter_by(
        folder_id=folder.id, is_deleted=False).all()]
    return folder.to_dict(chat_ids=chat_ids)


def _folder_body():
    data = request.get_json() or {}
    name = (data.get('name') or '').strip()
    if not name or len(name) > 60:
        raise ValueError('نام پوشه باید بین ۱ تا ۶۰ کاراکتر باشد')
    flags = {}
    for key in ('include_private', 'include_groups', 'include_channels', 'include_archived'):
        value = data.get(key, False)
        if type(value) is not bool:
            raise ValueError(f'{key} must be boolean')
        flags[key] = value
    chat_ids = data.get('chat_ids', [])
    if (not isinstance(chat_ids, list) or len(chat_ids) > MAX_FOLDER_CHATS
            or any(not isinstance(cid, str) or not cid for cid in chat_ids)):
        raise ValueError(f'حداکثر {MAX_FOLDER_CHATS} چت در هر پوشه مجاز است')
    return name, flags, list(dict.fromkeys(chat_ids))


def _sync_folder_items(folder, user_id, chat_ids):
    allowed = {m.chat_id for m in ChatMember.query.filter_by(
        user_id=user_id, is_deleted=False).all()}
    keep = [cid for cid in chat_ids if cid in allowed]
    existing = {item.chat_id: item for item in ChatFolderItem.query.filter_by(
        folder_id=folder.id).all()}
    for chat_id, item in existing.items():
        should_keep = chat_id in keep
        if item.is_deleted == (not should_keep):
            continue
        item.is_deleted = not should_keep
        item.deleted_at = None if should_keep else datetime.utcnow()
    for chat_id in keep:
        if chat_id not in existing:
            db.session.add(ChatFolderItem(folder_id=folder.id, chat_id=chat_id))
    return keep


@chats_bp.route('/folders', methods=['GET'])
@jwt_required()
def list_folders():
    user_id = get_jwt_identity()
    folders = ChatFolder.query.filter_by(user_id=user_id, is_deleted=False).order_by(
        ChatFolder.position.asc(), ChatFolder.created_at.asc()).all()
    return jsonify({'folders': [_folder_payload(folder) for folder in folders]}), 200


@chats_bp.route('/folders', methods=['POST'])
@jwt_required()
def create_folder():
    user_id = get_jwt_identity()
    try:
        name, flags, chat_ids = _folder_body()
    except ValueError as error:
        return jsonify({'error': str(error)}), 400
    count = ChatFolder.query.filter_by(user_id=user_id, is_deleted=False).count()
    if count >= MAX_FOLDERS:
        return jsonify({'error': f'حداکثر {MAX_FOLDERS} پوشه مجاز است'}), 400
    folder = ChatFolder(user_id=user_id, name=name, position=count, **flags)
    db.session.add(folder)
    db.session.flush()
    _sync_folder_items(folder, user_id, chat_ids)
    db.session.add(AuditLog(actor_id=user_id, action='create_chat_folder',
                            entity_type='chat_folder', entity_id=folder.id))
    db.session.commit()
    return jsonify({'folder': _folder_payload(folder)}), 201


@chats_bp.route('/folders/<folder_id>', methods=['POST'])
@jwt_required()
def update_folder(folder_id):
    user_id = get_jwt_identity()
    folder = ChatFolder.query.filter_by(id=folder_id, user_id=user_id, is_deleted=False).first()
    if not folder:
        return jsonify({'error': 'پوشه یافت نشد'}), 404
    try:
        name, flags, chat_ids = _folder_body()
    except ValueError as error:
        return jsonify({'error': str(error)}), 400
    folder.name = name
    for key, value in flags.items():
        setattr(folder, key, value)
    _sync_folder_items(folder, user_id, chat_ids)
    db.session.add(AuditLog(actor_id=user_id, action='update_chat_folder',
                            entity_type='chat_folder', entity_id=folder.id))
    db.session.commit()
    return jsonify({'folder': _folder_payload(folder)}), 200


@chats_bp.route('/folders/<folder_id>/delete', methods=['POST'])
@jwt_required()
def delete_folder(folder_id):
    user_id = get_jwt_identity()
    folder = ChatFolder.query.filter_by(id=folder_id, user_id=user_id, is_deleted=False).first()
    if not folder:
        return jsonify({'error': 'پوشه یافت نشد'}), 404
    folder.is_deleted = True
    folder.deleted_at = datetime.utcnow()
    db.session.add(AuditLog(actor_id=user_id, action='delete_chat_folder',
                            entity_type='chat_folder', entity_id=folder.id))
    db.session.commit()
    return jsonify({'ok': True}), 200


@chats_bp.route('/folders/reorder', methods=['POST'])
@jwt_required()
def reorder_folders():
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    ids = data.get('folder_ids')
    if not isinstance(ids, list) or any(not isinstance(fid, str) for fid in ids):
        return jsonify({'error': 'folder_ids نامعتبر است'}), 400
    folders = {f.id: f for f in ChatFolder.query.filter_by(
        user_id=user_id, is_deleted=False).all()}
    for position, folder_id in enumerate(dict.fromkeys(ids)):
        folder = folders.get(folder_id)
        if folder:
            folder.position = position
    db.session.commit()
    return jsonify({'ok': True}), 200



@chats_bp.route('/private', methods=['POST'])
@jwt_required()
def create_private_chat():
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    target_id = data.get('user_id')

    if not target_id or target_id == user_id:
        return jsonify({'error': 'کاربر هدف نامعتبر'}), 400

    target = User.query.filter_by(id=target_id, is_deleted=False).first()
    if not target:
        return jsonify({'error': 'کاربر یافت نشد'}), 404

    # Telegram-like limited account: cannot start new chats with strangers
    requester = User.query.get(user_id)
    if requester and requester.is_limited and requester.limited_until and requester.limited_until > datetime.utcnow():
        # Check if they have prior chat history (any private/group chat where target has messaged them, or they share a chat)
        from app.models.message import Message
        # Look for any existing private chat between them with messages
        existing_private = db.session.query(Chat).join(ChatMember).filter(
            Chat.chat_type == 'private', Chat.is_deleted==False, ChatMember.user_id==user_id, ChatMember.is_deleted==False
        ).all()
        has_history = False
        for ch in existing_private:
            other = ChatMember.query.filter(ChatMember.chat_id==ch.id, ChatMember.user_id==target_id, ChatMember.is_deleted==False).first()
            if other:
                # check if there is at least one message in that chat, or target sent you a message before
                if Message.query.filter_by(chat_id=ch.id, is_deleted=False).first():
                    has_history = True
                    break
        # Also allow if target ever sent a message to requester in any chat (e.g., they contacted first)
        if not has_history:
            # Check if target has ever sent a message to requester in any common chat or direct?
            # Simplified: if no prior private chat, block
            return jsonify({'error': 'حساب شما محدود شده است. فقط می‌توانید به افرادی که قبلاً با شما چت کرده‌اند پیام دهید. مانند تلگرام، محدودیت موقت است.', 'limited': True, 'reason': requester.limited_reason, 'until': utc_iso(requester.limited_until)}), 403

    # چک بلاک
    blocked = BlockList.query.filter(
        ((BlockList.blocker_id == user_id) & (BlockList.blocked_id == target_id)) |
        ((BlockList.blocker_id == target_id) & (BlockList.blocked_id == user_id)),
        BlockList.is_deleted == False
    ).first()
    if blocked:
        return jsonify({'error': 'امکان ایجاد چت وجود ندارد'}), 403

    # چک وجود چت خصوصی قبلی
    existing = db.session.query(Chat).join(ChatMember).filter(
        Chat.chat_type == 'private',
        Chat.is_deleted == False,
        ChatMember.user_id == user_id,
        ChatMember.is_deleted == False
    ).all()

    for chat in existing:
        other = ChatMember.query.filter(
            ChatMember.chat_id == chat.id,
            ChatMember.user_id == target_id,
            ChatMember.is_deleted == False
        ).first()
        if other:
            return jsonify({'chat_id': chat.id, 'message': 'چت از قبل وجود دارد'}), 200

    chat = Chat(chat_type='private', created_by=user_id)
    db.session.add(chat)
    db.session.flush()

    db.session.add(ChatMember(chat_id=chat.id, user_id=user_id, role='member'))
    db.session.add(ChatMember(chat_id=chat.id, user_id=target_id, role='member'))
    db.session.add(AuditLog(actor_id=user_id, action='create_private_chat', entity_type='chat', entity_id=chat.id))
    db.session.commit()

    return jsonify({'chat_id': chat.id}), 201


@chats_bp.route('/group', methods=['POST'])
@jwt_required()
def create_group():
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    title = (data.get('title') or '').strip()
    member_ids = data.get('member_ids') or []
    description = data.get('description')

    if not title or len(title) < 2:
        return jsonify({'error': 'عنوان گروه الزامی است'}), 400

    chat = Chat(
        chat_type='group',
        title=title,
        description=description,
        created_by=user_id,
        is_public=False
    )
    db.session.add(chat)
    db.session.flush()

    db.session.add(ChatMember(chat_id=chat.id, user_id=user_id, role='owner'))
    if not isinstance(member_ids, list) or len(member_ids) > 100 or any(
        not isinstance(mid, str) for mid in member_ids
    ):
        db.session.rollback()
        return jsonify({'error': 'Invalid member_ids (maximum 100)'}), 400
    results = {}
    try:
        for mid in dict.fromkeys(member_ids):
            if mid != user_id:
                results[mid] = add_or_invite(chat, user_id, mid, can_restore=True)
    except HTTPException as error:
        db.session.rollback()
        return jsonify({'error': error.description}), error.code

    db.session.add(AuditLog(actor_id=user_id, action='create_group', entity_type='chat', entity_id=chat.id))
    db.session.commit()
    return jsonify({'chat_id': chat.id, 'title': title, 'members': results}), 201


@chats_bp.route('/channel', methods=['POST'])
@jwt_required()
def create_channel():
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    title = (data.get('title') or '').strip()
    username = (data.get('username') or '').strip().lower()
    description = data.get('description')
    is_public = data.get('is_public', bool(username))

    if not title:
        return jsonify({'error': 'عنوان کانال الزامی است'}), 400
    if is_public and not username:
        return jsonify({'error': 'A public channel requires a username'}), 400

    if username:
        if not re.match(r'^[a-z0-9_]{3,30}$', username):
            return jsonify({'error': 'نام کاربری کانال نامعتبر'}), 400
        if Chat.query.filter_by(username=username, is_deleted=False).first():
            return jsonify({'error': 'این نام کاربری کانال قبلاً گرفته شده'}), 409

    chat = Chat(
        chat_type='channel',
        title=title,
        username=username or None,
        description=description,
        created_by=user_id,
        is_public=is_public
    )
    db.session.add(chat)
    db.session.flush()
    db.session.add(ChatMember(chat_id=chat.id, user_id=user_id, role='owner'))
    db.session.add(AuditLog(actor_id=user_id, action='create_channel', entity_type='chat', entity_id=chat.id))
    db.session.commit()
    return jsonify({'chat_id': chat.id, 'title': title, 'username': username}), 201


@chats_bp.route('/<chat_id>/members', methods=['GET'])
@jwt_required()
def get_members(chat_id):
    user_id = get_jwt_identity()
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member:
        return jsonify({'error': 'دسترسی ندارید'}), 403

    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'Chat not found'}), 404
    if chat.chat_type == 'channel' and member.role not in ('owner', 'admin'):
        return jsonify({'error': 'Subscriber list is private'}), 403
    # Telegram-like: admin can hide members list from regular members
    if chat.chat_type == 'group' and chat.hide_members and member.role not in ('owner', 'admin'):
        return jsonify({'error': 'Members list is hidden by administrator', 'hide_members': True, 'members': []}), 403
    members = ChatMember.query.filter_by(chat_id=chat_id, is_deleted=False).all()
    result = []
    for m in members:
        u = User.query.get(m.user_id)
        if u and not u.is_deleted:
            d = u.to_dict()
            d['role'] = m.role
            if member.role in ('owner', 'admin') and m.role == 'admin':
                d['permissions'] = admin_permissions(m)
            d['joined_at'] = utc_iso(m.joined_at)
            result.append(d)
    return jsonify({'members': result, 'hide_members': bool(chat.hide_members)}), 200


@chats_bp.route('/<chat_id>/pin', methods=['POST'])
@jwt_required()
def pin_chat(chat_id):
    """Pin a chat to the top of the list. Several chats can be pinned at once."""
    user_id = get_jwt_identity()
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member:
        return jsonify({'error': 'دسترسی ندارید'}), 403
    data = request.get_json(silent=True) or {}
    value = data.get('is_pinned', True)
    if type(value) is not bool:
        return jsonify({'error': 'is_pinned must be boolean'}), 400
    member.is_pinned = value
    member.pinned_at = datetime.utcnow() if value else None
    db.session.commit()
    return jsonify({'ok': True, 'is_pinned': member.is_pinned}), 200


@chats_bp.route('/<chat_id>/unpin', methods=['POST'])
@jwt_required()
def unpin_chat(chat_id):
    user_id = get_jwt_identity()
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member:
        return jsonify({'error': 'دسترسی ندارید'}), 403
    member.is_pinned = False
    member.pinned_at = None
    db.session.commit()
    return jsonify({'ok': True, 'is_pinned': False}), 200


@chats_bp.route('/<chat_id>/background', methods=['POST'])
@jwt_required()
def set_background(chat_id):
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    bg_type = data.get('type', 'color')
    value = data.get('value')
    if not value:
        return jsonify({'error': 'مقدار بک‌گراند الزامی است'}), 400

    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member:
        return jsonify({'error': 'دسترسی ندارید'}), 403

    member.custom_background = value
    existing = ChatBackground.query.filter_by(chat_id=chat_id, user_id=user_id).first()
    if existing:
        existing.background_type = bg_type
        existing.value = value
    else:
        db.session.add(ChatBackground(chat_id=chat_id, user_id=user_id, background_type=bg_type, value=value))
    db.session.commit()
    return jsonify({'ok': True}), 200

@chats_bp.route('/<chat_id>/background', methods=['GET'])
@jwt_required()
def get_background(chat_id):
    user_id = get_jwt_identity()
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member:
        return jsonify({'error': 'یسرتسد دیرادن'}), 403
    bg = ChatBackground.query.filter_by(chat_id=chat_id, user_id=user_id).first()
    if not bg:
        return jsonify({'background': None}), 200
    return jsonify({'background': {'type': bg.background_type, 'value': bg.value}}), 200


@chats_bp.route('/support', methods=['POST'])
@jwt_required()
def get_or_create_support():
    """چت با پشتیبانی"""
    user_id = get_jwt_identity()
    # پیدا کردن یا ساخت چت پشتیبانی
    support_user = User.query.filter_by(is_support=True, is_deleted=False).first()
    if not support_user:
        # اگر کاربر پشتیبانی وجود ندارد، یکی بساز (در migration یا seed)
        return jsonify({'error': 'پشتیبانی در دسترس نیست'}), 503

    # مشابه create_private_chat
    existing = db.session.query(Chat).join(ChatMember).filter(
        Chat.chat_type == 'support',
        Chat.is_deleted == False,
        ChatMember.user_id == user_id
    ).first()
    if existing:
        return jsonify({'chat_id': existing.id}), 200

    chat = Chat(chat_type='support', title='پشتیبانی', created_by=user_id)
    db.session.add(chat)
    db.session.flush()
    db.session.add(ChatMember(chat_id=chat.id, user_id=user_id, role='member'))
    db.session.add(ChatMember(chat_id=chat.id, user_id=support_user.id, role='admin'))
    db.session.commit()
    return jsonify({'chat_id': chat.id}), 201


@chats_bp.route('/<chat_id>/delete', methods=['POST'])
@jwt_required()
def delete_chat(chat_id):
    """حذف یک‌طرفه یا دوطرفه کل چت"""
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    for_all = bool(data.get('for_all', False))

    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member:
        return jsonify({'error': 'دسترسی ندارید'}), 403

    if for_all:
        chat = db.session.get(Chat, chat_id)
        if not chat:
            return jsonify({'error': 'چت یافت نشد'}), 404
        if chat.chat_type in ('group', 'channel') and member.role != 'owner':
            return jsonify({'error': 'فقط ادمین/مالک می‌تواند برای همه حذف کند'}), 403
        chat.is_deleted = True
        chat.is_deleted_for_all = True
        chat.deleted_at = datetime.utcnow()
        chat.deleted_by = user_id
        # soft delete all members
        ChatMember.query.filter_by(chat_id=chat_id).update({
            'is_deleted': True,
            'deleted_at': datetime.utcnow(),
            'deleted_by': user_id,
        })
    else:
        member.is_deleted = True
        member.deleted_at = datetime.utcnow()
        member.deleted_by = user_id

    db.session.add(AuditLog(
        actor_id=user_id,
        action='delete_chat_for_all' if for_all else 'delete_chat',
        entity_type='chat',
        entity_id=chat_id,
        ip_address=get_client_ip()
    ))
    db.session.commit()
    return jsonify({'ok': True, 'for_all': for_all}), 200


@chats_bp.route('/saved', methods=['POST'])
@jwt_required()
def get_or_create_saved_messages():
    """پیام‌های ذخیره‌شده (چت با خود)"""
    user_id = get_jwt_identity()

    # پیدا کردن چت saved موجود
    existing = db.session.query(Chat).join(ChatMember).filter(
        Chat.chat_type == 'saved',
        Chat.is_deleted == False,
        ChatMember.user_id == user_id,
        ChatMember.is_deleted == False,
    ).first()

    if existing:
        return jsonify({'chat_id': existing.id, 'title': 'Saved Messages'}), 200

    chat = Chat(
        chat_type='saved',
        title='Saved Messages',
        created_by=user_id,
    )
    db.session.add(chat)
    db.session.flush()
    db.session.add(ChatMember(chat_id=chat.id, user_id=user_id, role='owner'))
    db.session.add(AuditLog(actor_id=user_id, action='create_saved_messages', entity_type='chat', entity_id=chat.id))
    db.session.commit()
    return jsonify({'chat_id': chat.id, 'title': 'Saved Messages'}), 201

@chats_bp.route('/<chat_id>/add-member', methods=['POST'])
@jwt_required()
def add_member(chat_id):
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    target_id = data.get('user_id')
    member = ChatMember.query.filter_by(
        chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'چت یافت نشد'}), 404
    if chat.chat_type not in ('group', 'channel'):
        return jsonify({'error': 'This chat does not support invitations'}), 400
    if not isinstance(target_id, str):
        return jsonify({'error': 'user_id is required'}), 400
    if target_id == user_id:
        if member:
            return jsonify({'ok': True, 'action': 'already_member'}), 200
        if not chat.is_public:
            return jsonify({'error': 'Use an invitation to join a private chat'}), 403
        return _legacy_join(chat, user_id)
    if not member or not can(chat, user_id, 'invite_users'):
        return jsonify({'error': 'Inviting members is not permitted'}), 403
    source = data.get('source', 'chat_list')
    if source not in ('chat_list', 'search'):
        return jsonify({'error': 'Invalid invitation source'}), 400
    try:
        action = add_or_invite(chat, user_id, target_id,
                               invite_only=source == 'search',
                               can_restore=can(chat, user_id, 'restrict_members'))
        db.session.commit()
    except HTTPException as error:
        db.session.rollback()
        return jsonify({'error': error.description}), error.code
    return jsonify({'ok': True, 'action': action}), 200 if action == 'already_member' else 201


@chats_bp.route('/<chat_id>/remove-member', methods=['POST'])
@jwt_required()
def remove_member(chat_id):
    user_id = get_jwt_identity()
    target_id = (request.get_json() or {}).get('user_id')
    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat or chat.chat_type not in ('group', 'channel') or not can(chat, user_id, 'restrict_members'):
        return jsonify({'error': 'Removing members is not permitted'}), 403
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    target = ChatMember.query.filter_by(chat_id=chat_id, user_id=target_id, is_deleted=False).first()
    if not target:
        return jsonify({'error': 'Member not found'}), 404
    if target.role == 'owner' or target_id == user_id or (target.role == 'admin' and member.role != 'owner'):
        return jsonify({'error': 'Cannot remove this administrator or owner'}), 403
    target.is_deleted = True
    target.deleted_at = datetime.utcnow()
    target.deleted_by = user_id
    target.permissions = None
    db.session.add(AuditLog(actor_id=user_id, action='remove_member', entity_type='chat', entity_id=chat_id))
    db.session.commit()
    return jsonify({'ok': True}), 200


@chats_bp.route('/<chat_id>/leave', methods=['POST'])
@jwt_required()
def leave_chat(chat_id):
    user_id = get_jwt_identity()
    member = ChatMember.query.filter_by(
        chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member:
        return jsonify({'error': 'عضو نیستید'}), 403
    member.is_deleted = True
    member.deleted_at = datetime.utcnow()
    member.deleted_by = user_id
    db.session.commit()
    return jsonify({'ok': True}), 200

@chats_bp.route('/<chat_id>/promote', methods=['POST'])
@jwt_required()
def promote_member(chat_id):
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    target_id = data.get('user_id')
    new_role = data.get('role', 'admin')
    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat or chat.chat_type not in ('group', 'channel'):
        return jsonify({'error': 'Group or channel not found'}), 404
    if new_role not in ('admin', 'member', 'subscriber'):
        return jsonify({'error': 'Invalid role'}), 400
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member or not can(chat, user_id, 'promote_members'):
        return jsonify({'error': 'Promoting administrators is not permitted'}), 403
    target = ChatMember.query.filter_by(chat_id=chat_id, user_id=target_id, is_deleted=False).first()
    if not target:
        return jsonify({'error': 'Member not found'}), 404
    if target.role == 'owner' or target_id == user_id or (target.role == 'admin' and member.role != 'owner'):
        return jsonify({'error': 'Cannot change this administrator or owner'}), 403
    if new_role == 'admin':
        try:
            patch = validate_permissions(data['permissions'], ADMIN_DEFAULTS) if 'permissions' in data else {}
        except ValueError as error:
            return jsonify({'error': str(error)}), 400
        # New admins receive explicit rights, never implicit future privileges.
        rights = {**(admin_permissions(target) if target.role == 'admin' else ADMIN_DEFAULTS), **patch}
        own = capabilities(chat, member)
        if member.role != 'owner' and any(flag and not own.get(key, False) for key, flag in rights.items()):
            return jsonify({'error': 'Cannot grant rights you do not have'}), 403
        target.permissions = rights
        target.role = 'admin'
    else:
        target.role = 'subscriber' if chat.chat_type == 'channel' else 'member'
        target.permissions = None
    db.session.add(AuditLog(actor_id=user_id, action='change_admin_rights', entity_type='chat', entity_id=chat_id))
    db.session.commit()
    return jsonify({'ok': True, 'role': target.role, 'permissions': target.permissions}), 200

@chats_bp.route('/<chat_id>/info', methods=['GET'])
@jwt_required()
def get_chat_info(chat_id):
    user_id = get_jwt_identity()
    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'چت یافت نشد'}), 404
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member and not chat.is_public:
        return jsonify({'error': 'دسترسی ندارید'}), 403
    # If suspended/closed, still return info but flag it for banner
    # The header must work before either participant has sent a message.
    # Use the same privacy-filtered user serializer as profiles and the list.
    other_user = None
    if member and chat.chat_type in ('private', 'support'):
        other_user = User.query.join(ChatMember, ChatMember.user_id == User.id).filter(
            ChatMember.chat_id == chat_id,
            ChatMember.user_id != user_id,
            ChatMember.is_deleted.is_(False),
            User.is_deleted.is_(False),
        ).first()
    members_count = ChatMember.query.filter_by(chat_id=chat_id, is_deleted=False).count()
    # Online members count (Telegram-like) - count members where user is online (last_seen within 60s)
    online_count = 0
    if chat.chat_type in ('group', 'channel'):
        try:
            from datetime import timedelta
            # Get member user_ids
            member_user_ids = [m.user_id for m in ChatMember.query.filter_by(chat_id=chat_id, is_deleted=False).all()]
            if member_user_ids:
                online_users = User.query.filter(User.id.in_(member_user_ids), User.is_online==True, User.is_deleted==False).all()
                # Apply privacy & heartbeat expiry like User.to_dict()
                now = datetime.utcnow()
                for u in online_users:
                    if u.last_seen and timedelta(0) <= now - u.last_seen < timedelta(seconds=60):
                        if u.show_last_seen:
                            online_count += 1
        except Exception:
            online_count = 0
    my_role = member.role if member else None
    return jsonify({
        'id': chat.id,
        'chat_type': chat.chat_type,
        'title': chat.title,
        'username': chat.username,
        'description': chat.description,
        'avatar_url': chat.avatar_url,
        'is_public': chat.is_public,
        'created_by': chat.created_by,
        'members_count': members_count,
        'online_count': online_count,
        'hide_members': bool(chat.hide_members),
        'allow_forwarding': bool(getattr(chat, 'allow_forwarding', True)) if getattr(chat, 'allow_forwarding', True) is not None else True,
        'is_sponsored': bool(getattr(chat, 'is_sponsored', False)),
        'is_suspended': bool(chat.is_suspended),
        'suspension_reason': chat.suspension_reason,
        'suspended_at': utc_iso(chat.suspended_at) if chat.suspended_at else None,
        'is_closed': bool(chat.is_closed),
        'closed_reason': chat.closed_reason,
        'closed_at': utc_iso(chat.closed_at) if chat.closed_at else None,
        'my_role': my_role,
        'is_muted': member.is_muted if member else False,
        'slow_mode_delay': chat.slow_mode_delay or 0,
        'permissions': group_permissions(chat) if chat.chat_type == 'group' else None,
        'capabilities': capabilities(chat, member),
        'other_user': other_user.to_dict() if other_user else None,
        'created_at': utc_iso(chat.created_at),
    }), 200


@chats_bp.route('/<chat_id>/update', methods=['POST'])
@jwt_required()
def update_chat(chat_id):
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'چت یافت نشد'}), 404
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if chat.chat_type not in ('group', 'channel') or not can(chat, user_id, 'change_info'):
        return jsonify({'error': 'دسترسی ندارید'}), 403
    public = data.get('is_public', chat.is_public) if member.role == 'owner' else chat.is_public
    username = (data.get('username', chat.username) or '').strip() if member.role == 'owner' else chat.username
    if public and not username:
        return jsonify({'error': 'Public chats require a username'}), 400
    if 'title' in data and data['title']:
        chat.title = data['title'].strip()[:200]
    if 'description' in data:
        chat.description = data['description']
    if 'avatar_url' in data:
        avatar = data['avatar_url']
        if avatar is not None and not isinstance(avatar, str):
            return jsonify({'error': 'آدرس عکس نامعتبر است'}), 400
        # An empty string clears the picture instead of storing a blank URL.
        chat.avatar_url = (avatar or '').strip() or None
    if 'is_public' in data and member.role == 'owner':
        chat.is_public = bool(data['is_public'])
    if 'username' in data and member.role == 'owner':
        new_username = (data['username'] or '').strip().lower()
        if new_username:
            if not re.match(r'^[a-z0-9_]{3,30}$', new_username):
                return jsonify({'error': 'یوزرنیم نامعتبر'}), 400
            existing = Chat.query.filter(
                Chat.username == new_username,
                Chat.id != chat_id,
                Chat.is_deleted == False
            ).first()
            if existing:
                return jsonify({'error': 'این یوزرنیم قبلاً گرفته شده'}), 409
            chat.username = new_username
        else:
            chat.username = None
    if 'slow_mode_delay' in data and member.role in ('owner', 'admin'):
        try:
            delay = int(data['slow_mode_delay'])
            if delay < 0:
                return jsonify({'error': 'slow_mode_delay must be non-negative'}), 400
            chat.slow_mode_delay = delay
        except (ValueError, TypeError):
            return jsonify({'error': 'Invalid slow_mode_delay'}), 400
    db.session.add(AuditLog(actor_id=user_id, action='update_chat', entity_type='chat', entity_id=chat_id))
    db.session.commit()
    return jsonify({'ok': True}), 200


@chats_bp.route('/<chat_id>/hide-members', methods=['POST'])
@jwt_required()
def toggle_hide_members(chat_id):
    user_id = get_jwt_identity()
    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'چت یافت نشد'}), 404
    if chat.chat_type != 'group':
        return jsonify({'error': 'فقط گروه‌ها این تنظیم را دارند'}), 400
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member or member.role not in ('owner', 'admin'):
        return jsonify({'error': 'فقط مدیر گروه می‌تواند این تنظیم را تغییر دهد'}), 403
    # Check capability manage_permissions or restrict_members
    if not can(chat, user_id, 'manage_permissions') and member.role != 'owner':
        return jsonify({'error': 'دسترسی ندارید'}), 403
    data = request.get_json() or {}
    hide = data.get('hide_members')
    if type(hide) is not bool:
        return jsonify({'error': 'hide_members must be boolean'}), 400
    chat.hide_members = hide
    db.session.add(AuditLog(actor_id=user_id, action='toggle_hide_members', entity_type='chat', entity_id=chat_id, ip_address=get_client_ip()))
    db.session.commit()
    return jsonify({'ok': True, 'hide_members': chat.hide_members}), 200


@chats_bp.route('/<chat_id>/visibility', methods=['GET'])
@jwt_required()
def get_visibility(chat_id):
    user_id = get_jwt_identity()
    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'چت یافت نشد'}), 404
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member:
        return jsonify({'error': 'دسترسی ندارید'}), 403
    return jsonify({'hide_members': bool(chat.hide_members), 'is_suspended': bool(chat.is_suspended), 'is_closed': bool(chat.is_closed),
                    'allow_forwarding': bool(getattr(chat, 'allow_forwarding', True)) if getattr(chat, 'allow_forwarding', True) is not None else True,
                    'is_sponsored': bool(getattr(chat, 'is_sponsored', False))}), 200


@chats_bp.route('/<chat_id>/invite-link', methods=['GET'])
@jwt_required()
def get_invite_link(chat_id):
    user_id = get_jwt_identity()
    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'چت یافت نشد'}), 404
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not can(chat, user_id, 'invite_users'):
        return jsonify({'error': 'دسترسی ندارید'}), 403
    if chat.chat_type not in ('group', 'channel'):
        return jsonify({'error': 'این چت لینک دعوت ندارد'}), 400
    from app.services.chat_invites import create_invite_link
    link = create_invite_link(chat)
    return jsonify({'invite_link': link, 'chat_id': chat_id}), 200


@chats_bp.route('/join/<chat_id>', methods=['POST'])
@jwt_required()
def join_by_link(chat_id):
    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'Chat not found'}), 404
    if not chat.is_public or chat.chat_type not in ('group', 'channel'):
        return jsonify({'error': 'Use a valid invitation'}), 403
    return _legacy_join(chat, get_jwt_identity())


@chats_bp.route('/<chat_id>/set-permissions', methods=['POST'])
@jwt_required()
def set_permissions(chat_id):
    user_id = get_jwt_identity()
    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'Chat not found'}), 404
    if chat.chat_type != 'group':
        return jsonify({'error': 'Channels use administrator publishing rights, not group permissions'}), 400
    if not can(chat, user_id, 'manage_permissions'):
        return jsonify({'error': 'Changing permissions is not permitted'}), 403
    data = request.get_json() or {}
    # Keep old clients compatible, but strictly validate booleans.
    aliases = {'members_can_send': 'send_messages', 'members_can_add_members': 'invite_users'}
    if not isinstance(data, dict):
        return jsonify({'error': 'Invalid permissions'}), 400
    data = {aliases.get(key, key): value for key, value in data.items()}
    try:
        patch = validate_permissions(data, GROUP_DEFAULTS)
    except ValueError as error:
        return jsonify({'error': str(error)}), 400
    chat.permissions = {**group_permissions(chat), **patch}
    db.session.add(AuditLog(actor_id=user_id, action='set_group_permissions', entity_type='chat', entity_id=chat_id))
    db.session.commit()
    return jsonify({'ok': True, 'permissions': chat.permissions}), 200


def _invite_chat_for_request():
    """Resolve a bearer invite without granting access merely by previewing it."""
    from app.services.chat_invites import InvalidInvite, resolve_invite

    user = User.query.filter_by(id=get_jwt_identity(), is_deleted=False,
                                is_active=True).first()
    if user is None:
        return None, (jsonify({'error': 'دسترسی ندارید'}), 403)
    data = request.get_json() or {}
    if not isinstance(data, dict):
        return None, (jsonify({'error': 'درخواست نامعتبر است'}), 400)
    try:
        chat = resolve_invite(data.get('invite_link'))
    except InvalidInvite:
        return None, (jsonify({'error': 'لینک دعوت نامعتبر است یا دیگر در دسترس نیست'}), 404)
    member = ChatMember.query.filter_by(chat_id=chat.id, user_id=user.id).first()
    if (member and member.is_deleted and member.deleted_by
            and member.deleted_by != user.id):
        return None, (jsonify({'error': 'امکان عضویت با این لینک وجود ندارد'}), 403)
    return chat, None


def _invite_preview(chat, user_id):
    member = ChatMember.query.filter_by(chat_id=chat.id, user_id=user_id,
                                       is_deleted=False).first()
    return {
        'id': chat.id,
        'chat_type': chat.chat_type,
        'title': chat.title,
        'description': chat.description,
        'avatar_url': chat.avatar_url,
        'members_count': ChatMember.query.filter_by(chat_id=chat.id, is_deleted=False).count(),
        'is_member': member is not None,
    }


@chats_bp.route('/invite-preview', methods=['POST'])
@jwt_required()
def preview_invite():
    chat, error = _invite_chat_for_request()
    if error is not None:
        return error
    return jsonify(_invite_preview(chat, get_jwt_identity())), 200


@chats_bp.route('/join', methods=['POST'])
@jwt_required()
def join_by_invite():
    chat, error = _invite_chat_for_request()
    if error is not None:
        return error
    return _join_chat(chat, get_jwt_identity())


def _join_chat(chat, user_id, created_status=200):
    from sqlalchemy.exc import IntegrityError
    chat_id = chat.id
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id).with_for_update().first()
    if member and member.is_deleted and member.deleted_by not in (None, user_id):
        return jsonify({'error': 'Cannot rejoin after removal'}), 403
    if member and not member.is_deleted:
        return jsonify(_invite_preview(chat, user_id)), 200

    role = ('owner' if chat.created_by == user_id else
            'subscriber' if chat.chat_type == 'channel' else 'member')
    if member:
        # Reuse the soft-deleted row (uq_chat_member), never insert a duplicate
        # or restore a former admin's privileges after leaving.
        member.is_deleted = False
        member.deleted_at = None
        member.deleted_by = None
        member.joined_at = datetime.utcnow()
        member.role = role
        member.permissions = None
    else:
        db.session.add(ChatMember(chat_id=chat_id, user_id=user_id, role=role))
    db.session.add(AuditLog(
        actor_id=user_id, action='join_chat_by_invite', entity_type='chat',
        entity_id=chat_id, ip_address=get_client_ip(),
    ))
    try:
        db.session.commit()
    except IntegrityError:
        # A repeated tap / second device may have inserted the same membership
        # while this request was in flight. Success is idempotent.
        db.session.rollback()
        member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id,
                                           is_deleted=False).first()
        if member is None:
            raise
    return jsonify(_invite_preview(chat, user_id)), created_status


@chats_bp.route('/<chat_id>/shared-media', methods=['GET'])
@jwt_required()
def get_shared_media(chat_id):
    user_id = get_jwt_identity()
    if not user_in_chat(user_id, chat_id):
        return jsonify({'error': 'دسترسی ندارید'}), 403

    m_type = request.args.get('type')
    query = visible_messages(user_id).filter(
        Message.chat_id == chat_id,
        Message.media_id.isnot(None),
        Message.is_view_once.is_(False),
    )

    if m_type and m_type != 'all':
        if m_type == 'media':
            query = query.filter(Message.message_type.in_(['image', 'video']))
        elif m_type == 'files':
            query = query.filter(Message.message_type == 'file')
        elif m_type == 'voice':
            query = query.filter(Message.message_type.in_(['voice', 'audio', 'music']))
        elif m_type == 'music':
            query = query.filter(Message.message_type.in_(['audio', 'music']))
        else:
            query = query.filter(Message.message_type == m_type)

    # Location messages have no media; include them when type=all via second query.
    messages = query.order_by(Message.created_at.desc()).limit(200).all()
    serialized = serialize_messages(messages, user_id)

    # Attach original_name, file_size, mime_type from MediaFile to each serialized message
    media_ids = [m.media_id for m in messages if m.media_id]
    media_files = {m.id: m for m in MediaFile.query.filter(MediaFile.id.in_(media_ids)).all()} if media_ids else {}

    for item in serialized:
        mid = item.get('media_id')
        if mid and mid in media_files:
            mf = media_files[mid]
            item['original_name'] = mf.original_name
            item['file_size'] = mf.file_size
            item['mime_type'] = mf.mime_type
            item['duration'] = mf.duration
            if not item.get('audio_title') and getattr(mf, 'title', None):
                item['audio_title'] = mf.title
            if not item.get('audio_artist') and getattr(mf, 'artist', None):
                item['audio_artist'] = mf.artist
            if not item.get('audio_duration') and mf.duration:
                item['audio_duration'] = mf.duration

    media_items = [m for m in serialized if m['message_type'] in ('image', 'video')]
    file_items = [m for m in serialized if m['message_type'] == 'file']
    voice_items = [m for m in serialized if m['message_type'] in ('voice', 'audio', 'music')]
    music_items = [m for m in serialized if m['message_type'] in ('audio', 'music')]

    return jsonify({
        'media': media_items,
        'files': file_items,
        'voice': voice_items,
        'music': music_items,
        'all': serialized,
    }), 200


@chats_bp.route('/<chat_id>/mute', methods=['POST'])
@jwt_required()
def mute_chat(chat_id):
    member = ChatMember.query.join(Chat).filter(
        ChatMember.chat_id == chat_id, ChatMember.user_id == get_jwt_identity(),
        ChatMember.is_deleted.is_(False), Chat.is_deleted.is_(False)).first()
    if not member:
        return jsonify({'error': 'Access denied'}), 403
    value = (request.get_json() or {}).get('is_muted')
    if type(value) is not bool:
        return jsonify({'error': 'is_muted must be boolean'}), 400
    member.is_muted = value
    db.session.commit()
    return jsonify({'is_muted': member.is_muted}), 200


def _legacy_join(chat, user_id):
    response, status = _join_chat(chat, user_id, created_status=201)
    if status < 300:
        return jsonify({**response.get_json(), 'chat_id': chat.id, 'ok': True}), status
    return response, status
