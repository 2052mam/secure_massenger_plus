from app import db
from datetime import datetime
import uuid

class Chat(db.Model):
    __tablename__ = 'chats'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    
    # private | group | channel | support
    chat_type = db.Column(db.String(20), nullable=False, index=True)
    
    title = db.Column(db.String(200), nullable=True)  # for group/channel
    username = db.Column(db.String(50), unique=True, nullable=True, index=True)  # public channel/group
    description = db.Column(db.Text, nullable=True)
    avatar_url = db.Column(db.String(500), nullable=True)
    
    permissions = db.Column(db.JSON, nullable=True)
    slow_mode_delay = db.Column(db.Integer, default=0, nullable=False)
    # Telegram-like: admin can hide members list from non-admins
    hide_members = db.Column(db.Boolean, default=False, nullable=False)

    # Telegram-like: block forwarding from this chat (group/channel).
    allow_forwarding = db.Column(db.Boolean, default=True, nullable=False, server_default=db.true())

    # Sponsored channels (set by the general app admin, visible to everyone).
    is_sponsored = db.Column(db.Boolean, default=False, nullable=False, server_default=db.false(), index=True)
    sponsored_at = db.Column(db.DateTime, nullable=True)
    sponsored_by = db.Column(db.String(36), nullable=True)

    # Suspension / closure after reports (Telegram-like)
    is_suspended = db.Column(db.Boolean, default=False, nullable=False)
    suspension_reason = db.Column(db.Text, nullable=True)
    suspended_at = db.Column(db.DateTime, nullable=True)
    suspended_by = db.Column(db.String(36), nullable=True)
    is_closed = db.Column(db.Boolean, default=False, nullable=False)
    closed_reason = db.Column(db.Text, nullable=True)
    closed_at = db.Column(db.DateTime, nullable=True)

    created_by = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False)
    is_public = db.Column(db.Boolean, default=False)
    
    # Soft Delete
    is_deleted = db.Column(db.Boolean, default=False, index=True)
    deleted_at = db.Column(db.DateTime, nullable=True)
    deleted_by = db.Column(db.String(36), nullable=True)
    is_deleted_for_all = db.Column(db.Boolean, default=False)
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    members = db.relationship('ChatMember', backref='chat', lazy='dynamic')
    messages = db.relationship('Message', backref='chat', lazy='dynamic')


class ChatMember(db.Model):
    __tablename__ = 'chat_members'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    chat_id = db.Column(db.String(36), db.ForeignKey('chats.id'), nullable=False, index=True)
    user_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)
    
    # owner | admin | member | subscriber
    role = db.Column(db.String(20), default='member')
    
    permissions = db.Column(db.JSON, nullable=True)

    # Notification & settings
    is_muted = db.Column(db.Boolean, default=False)
    is_pinned = db.Column(db.Boolean, default=False)
    # Newest pin first, exactly like Telegram's pinned block.
    pinned_at = db.Column(db.DateTime, nullable=True)
    # Archived chats leave the main list and live behind the optional PIN.
    is_archived = db.Column(db.Boolean, nullable=False, default=False,
                            server_default=db.false())
    archived_at = db.Column(db.DateTime, nullable=True)
    custom_background = db.Column(db.String(500), nullable=True)
    
    joined_at = db.Column(db.DateTime, default=datetime.utcnow)
    last_read_message_id = db.Column(db.String(36), nullable=True)
    
    # Soft Delete (leave / remove)
    is_deleted = db.Column(db.Boolean, default=False)
    deleted_at = db.Column(db.DateTime, nullable=True)
    deleted_by = db.Column(db.String(36), nullable=True)

    __table_args__ = (
        db.UniqueConstraint('chat_id', 'user_id', name='uq_chat_member'),
    )


class ChatBackground(db.Model):
    __tablename__ = 'chat_backgrounds'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    chat_id = db.Column(db.String(36), db.ForeignKey('chats.id'), nullable=False)
    user_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False)
    
    background_type = db.Column(db.String(20), default='color')  # color | image | gradient
    value = db.Column(db.String(500), nullable=False)
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
