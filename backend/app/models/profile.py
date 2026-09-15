"""Multiple profile photos and recent search history (Telegram parity).

Both tables follow the project rule: nothing is ever hard deleted, every row
keeps an audit friendly timestamp.
"""
from app.services.timestamps import utc_iso
from app import db
from datetime import datetime
import uuid


class UserPhoto(db.Model):
    """A user's profile photo album. Only users have albums, never chats."""

    __tablename__ = 'user_photos'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)

    photo_url = db.Column(db.String(500), nullable=False)
    media_id = db.Column(db.String(36), nullable=True)
    is_main = db.Column(db.Boolean, nullable=False, default=False)
    position = db.Column(db.Integer, nullable=False, default=0)

    is_deleted = db.Column(db.Boolean, nullable=False, default=False, index=True)
    deleted_at = db.Column(db.DateTime, nullable=True)

    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'photo_url': self.photo_url,
            'media_id': self.media_id,
            'is_main': bool(self.is_main),
            'position': self.position,
            'created_at': utc_iso(self.created_at),
        }


class SearchHistory(db.Model):
    """Recent searches shown before the user types anything in the search tab."""

    __tablename__ = 'search_history'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)

    # NOTE: the attribute is `term`, never `query`: `Model.query` is
    # Flask-SQLAlchemy's session query property and must not be shadowed.
    term = db.Column('search_term', db.String(120), nullable=True)
    target_user_id = db.Column(db.String(36), nullable=True, index=True)
    target_chat_id = db.Column(db.String(36), nullable=True, index=True)

    is_deleted = db.Column(db.Boolean, nullable=False, default=False, index=True)
    deleted_at = db.Column(db.DateTime, nullable=True)

    created_at = db.Column(db.DateTime, default=datetime.utcnow, index=True)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
