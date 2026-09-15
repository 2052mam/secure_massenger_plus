from app import db
from datetime import datetime
import uuid

class Message(db.Model):
    __tablename__ = 'messages'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    chat_id = db.Column(db.String(36), db.ForeignKey('chats.id'), nullable=False, index=True)
    sender_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)
    
    # text | image | video | voice | file | system
    message_type = db.Column(db.String(20), default='text', nullable=False)
    
    content = db.Column(db.Text, nullable=True)  # text content or caption
    media_id = db.Column(db.String(36), db.ForeignKey('media_files.id'), nullable=True)
    
    # Reply & Forward
    reply_to_id = db.Column(db.String(36), db.ForeignKey('messages.id'), nullable=True)
    forwarded_from_id = db.Column(db.String(36), db.ForeignKey('messages.id'), nullable=True)
    forwarded_from_chat_id = db.Column(db.String(36), nullable=True)
    
    # View Once
    is_view_once = db.Column(db.Boolean, default=False)
    viewed_at = db.Column(db.DateTime, nullable=True)

    # Spoiler Mode
    is_spoiler = db.Column(db.Boolean, default=False, nullable=False)

    # Scheduled Message
    is_scheduled = db.Column(db.Boolean, default=False, nullable=False, index=True)
    scheduled_at = db.Column(db.DateTime, nullable=True, index=True)

    # --- Encrypted message mode (password-protected, spoiler-like) ---
    # content stores ciphertext (client-side encrypted); server never sees plaintext.
    is_encrypted = db.Column(db.Boolean, default=False, nullable=False, server_default=db.false())
    encryption_hint = db.Column(db.String(200), nullable=True)

    # --- Secure (secret) chat mode: separate black-theme page, no forward/download ---
    is_secure = db.Column(db.Boolean, default=False, nullable=False, server_default=db.false(), index=True)

    # --- Location messages (static + live via polling) ---
    latitude = db.Column(db.Float, nullable=True)
    longitude = db.Column(db.Float, nullable=True)
    location_title = db.Column(db.String(200), nullable=True)
    live_until = db.Column(db.DateTime, nullable=True)

    # --- Music / audio messages (internal player like Telegram) ---
    audio_title = db.Column(db.String(200), nullable=True)
    audio_artist = db.Column(db.String(200), nullable=True)
    audio_duration = db.Column(db.Float, nullable=True)

    # --- Video editor: muted videos play silently on every client ---
    is_muted = db.Column(db.Boolean, default=False, nullable=False, server_default=db.false())
    
    # Soft Delete
    is_deleted = db.Column(db.Boolean, default=False, index=True)
    deleted_at = db.Column(db.DateTime, nullable=True)
    deleted_by = db.Column(db.String(36), nullable=True)
    is_deleted_for_all = db.Column(db.Boolean, default=False)
    
    # Edit
    is_edited = db.Column(db.Boolean, default=False)
    edited_at = db.Column(db.DateTime, nullable=True)
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow, index=True)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    statuses = db.relationship('MessageStatus', backref='message', lazy='dynamic')
    reactions = db.relationship('MessageReaction', backref='message', lazy='dynamic')


class MessageStatus(db.Model):
    __tablename__ = 'message_statuses'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    message_id = db.Column(db.String(36), db.ForeignKey('messages.id'), nullable=False, index=True)
    user_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)
    
    # sent | delivered | read
    status = db.Column(db.String(20), default='sent', nullable=False)
    
    delivered_at = db.Column(db.DateTime, nullable=True)
    read_at = db.Column(db.DateTime, nullable=True)
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    __table_args__ = (
        db.UniqueConstraint('message_id', 'user_id', name='uq_message_status'),
    )


class MessageReaction(db.Model):
    __tablename__ = 'message_reactions'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    message_id = db.Column(db.String(36), db.ForeignKey('messages.id'), nullable=False, index=True)
    user_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False)
    emoji = db.Column(db.String(20), nullable=False)
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    is_deleted = db.Column(db.Boolean, default=False)
    deleted_at = db.Column(db.DateTime, nullable=True)

    __table_args__ = (
        db.UniqueConstraint('message_id', 'user_id', 'emoji', name='uq_reaction'),
    )


class PinnedMessage(db.Model):
    __tablename__ = 'pinned_messages'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    chat_id = db.Column(db.String(36), db.ForeignKey('chats.id'), nullable=False, index=True)
    message_id = db.Column(db.String(36), db.ForeignKey('messages.id'), nullable=False)
    pinned_by = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False)
    
    pinned_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    is_deleted = db.Column(db.Boolean, default=False)
    deleted_at = db.Column(db.DateTime, nullable=True)


class MessageHide(db.Model):
    """حذف یک‌طرفه پیام برای یک کاربر خاص"""
    __tablename__ = 'message_hides'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    message_id = db.Column(db.String(36), db.ForeignKey('messages.id'), nullable=False, index=True)
    user_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    __table_args__ = (
        db.UniqueConstraint('message_id', 'user_id', name='uq_message_hide'),
    )
