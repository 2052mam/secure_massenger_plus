"""Direct additions only for existing private-chat peers who consent.

Search-only invitations never silently subscribe another user. Delivery and
membership changes use the caller's transaction, including group creation.
"""
from datetime import datetime
from sqlalchemy.orm import aliased
from werkzeug.exceptions import Forbidden, NotFound
from app import db
from app.models.chat import Chat, ChatMember
from app.models.message import Message, MessageStatus
from app.models.user import User, BlockList
from app.models.audit import AuditLog
from app.services.chat_invites import create_invite_link


def add_or_invite(chat, actor_id, target_id, invite_only=False, can_restore=False):
    target = User.query.filter_by(id=target_id, is_deleted=False, is_active=True).with_for_update().first()
    if not target:
        raise NotFound('User not found')
    blocked = BlockList.query.filter(
        BlockList.is_deleted.is_(False),
        ((BlockList.blocker_id == actor_id) & (BlockList.blocked_id == target_id)) |
        ((BlockList.blocker_id == target_id) & (BlockList.blocked_id == actor_id)),
    ).first()
    if blocked:
        raise Forbidden('Cannot add or invite a blocked user')
    existing = ChatMember.query.filter_by(chat_id=chat.id, user_id=target_id).first()
    if existing and not existing.is_deleted:
        return 'already_member'
    if existing and existing.deleted_by not in (None, target_id) and not can_restore:
        raise Forbidden('Only an authorized administrator can restore a removed member')
    peer = aliased(ChatMember)
    private = Chat.query.join(ChatMember).join(peer, peer.chat_id == Chat.id).filter(
        Chat.chat_type == 'private', Chat.is_deleted.is_(False),
        ChatMember.user_id == actor_id, ChatMember.is_deleted.is_(False),
        peer.user_id == target_id, peer.is_deleted.is_(False),
    ).first()
    if private and target.allow_group_adds and not invite_only:
        role = ('owner' if chat.created_by == target_id else
                'subscriber' if chat.chat_type == 'channel' else 'member')
        if existing:
            existing.is_deleted = False
            existing.deleted_at = None
            existing.deleted_by = None
            existing.joined_at = datetime.utcnow()
            existing.role = role
            existing.permissions = None
        else:
            db.session.add(ChatMember(chat_id=chat.id, user_id=target_id, role=role))
        action = 'added'
    else:
        if private is None:
            private = Chat(chat_type='private', created_by=actor_id)
            db.session.add(private)
            db.session.flush()
            db.session.add_all([ChatMember(chat_id=private.id, user_id=uid)
                                for uid in (actor_id, target_id)])
        link = create_invite_link(chat)
        # Idempotent retries must not spam identical invitations. A previous
        # deleted/hidden invitation may intentionally be sent again.
        from app.services.message_payloads import visible_messages
        prior = visible_messages(target_id).filter_by(
            chat_id=private.id, sender_id=actor_id, content=link).first()
        if prior is None:
            msg = Message(chat_id=private.id, sender_id=actor_id, content=link, message_type='text')
            db.session.add(msg)
            db.session.flush()
            db.session.add_all([
                MessageStatus(message_id=msg.id, user_id=actor_id, status='sent'),
                MessageStatus(message_id=msg.id, user_id=target_id, status='delivered',
                              delivered_at=datetime.utcnow()),
            ])
            private.updated_at = datetime.utcnow()
        # Explicit admin invitation lifts a removal ban but does not join the
        # user against their privacy setting. They still confirm the link.
        if existing and can_restore:
            existing.deleted_by = target_id
            existing.role = ('owner' if chat.created_by == target_id else
                             'subscriber' if chat.chat_type == 'channel' else 'member')
            existing.permissions = None
        action = 'invited'
    db.session.add(AuditLog(actor_id=actor_id, action=f'member_{action}',
                           entity_type='chat', entity_id=chat.id))
    return action
