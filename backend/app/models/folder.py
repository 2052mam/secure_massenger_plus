"""Telegram-style chat folders.

A folder mixes rule based inclusion (all private chats / groups / channels) with
explicitly pinned chats, exactly like Telegram's folder editor. Everything is
soft deleted so an accidental removal never destroys history.
"""
from app import db
from datetime import datetime
import uuid


class ChatFolder(db.Model):
    __tablename__ = 'chat_folders'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)

    name = db.Column(db.String(60), nullable=False)
    position = db.Column(db.Integer, nullable=False, default=0)

    # Rule based inclusion
    include_private = db.Column(db.Boolean, nullable=False, default=False)
    include_groups = db.Column(db.Boolean, nullable=False, default=False)
    include_channels = db.Column(db.Boolean, nullable=False, default=False)
    include_archived = db.Column(db.Boolean, nullable=False, default=False)

    is_deleted = db.Column(db.Boolean, nullable=False, default=False, index=True)
    deleted_at = db.Column(db.DateTime, nullable=True)

    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    items = db.relationship('ChatFolderItem', backref='folder', lazy='dynamic')

    def to_dict(self, chat_ids=None):
        return {
            'id': self.id,
            'name': self.name,
            'position': self.position,
            'include_private': bool(self.include_private),
            'include_groups': bool(self.include_groups),
            'include_channels': bool(self.include_channels),
            'include_archived': bool(self.include_archived),
            'chat_ids': list(chat_ids if chat_ids is not None else
                             [item.chat_id for item in self.items.filter_by(is_deleted=False)]),
        }


class ChatFolderItem(db.Model):
    __tablename__ = 'chat_folder_items'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    folder_id = db.Column(db.String(36), db.ForeignKey('chat_folders.id'), nullable=False, index=True)
    chat_id = db.Column(db.String(36), db.ForeignKey('chats.id'), nullable=False, index=True)

    is_deleted = db.Column(db.Boolean, nullable=False, default=False)
    deleted_at = db.Column(db.DateTime, nullable=True)

    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    __table_args__ = (
        db.UniqueConstraint('folder_id', 'chat_id', name='uq_folder_chat'),
    )
