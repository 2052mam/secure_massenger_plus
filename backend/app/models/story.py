"""Telegram-like Stories: 24h expiring posts, polled (no WebSocket)."""
from app.services.timestamps import utc_iso
from app import db
from datetime import datetime, timedelta
import uuid


class Story(db.Model):
    __tablename__ = 'stories'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)

    # text | image | video
    story_type = db.Column(db.String(20), default='text', nullable=False)
    content = db.Column(db.Text, nullable=True)  # text or caption
    media_id = db.Column(db.String(36), db.ForeignKey('media_files.id'), nullable=True)

    # Who can see: everyone | contacts (for now everyone; contacts = share a chat)
    privacy = db.Column(db.String(20), default='everyone', nullable=False)

    views_count = db.Column(db.Integer, default=0, nullable=False)

    expires_at = db.Column(db.DateTime, nullable=False, index=True, default=lambda: datetime.utcnow() + timedelta(hours=24))

    is_deleted = db.Column(db.Boolean, default=False, index=True)
    deleted_at = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, index=True)

    def to_dict(self, viewer_has_seen=False):
        return {
            'id': self.id,
            'user_id': self.user_id,
            'story_type': self.story_type,
            'content': self.content,
            'media_id': self.media_id,
            'media_url': f'/api/v1/media/{self.media_id}' if self.media_id else None,
            'privacy': self.privacy,
            'views_count': self.views_count or 0,
            'viewer_has_seen': bool(viewer_has_seen),
            'expires_at': utc_iso(self.expires_at),
            'created_at': utc_iso(self.created_at),
        }


class StoryView(db.Model):
    __tablename__ = 'story_views'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    story_id = db.Column(db.String(36), db.ForeignKey('stories.id'), nullable=False, index=True)
    viewer_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)
    viewed_at = db.Column(db.DateTime, default=datetime.utcnow)

    __table_args__ = (
        db.UniqueConstraint('story_id', 'viewer_id', name='uq_story_view'),
    )
