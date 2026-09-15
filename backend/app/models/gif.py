from app import db
from datetime import datetime
import uuid

class SavedGif(db.Model):
    __tablename__ = 'saved_gifs'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)
    # Either media_id referencing uploaded gif, or external URL
    media_id = db.Column(db.String(36), db.ForeignKey('media_files.id'), nullable=True)
    gif_url = db.Column(db.String(500), nullable=True)  # external or media url
    external_id = db.Column(db.String(100), nullable=True)  # giphy id etc
    title = db.Column(db.String(200), nullable=True)
    preview_url = db.Column(db.String(500), nullable=True)

    is_deleted = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    __table_args__ = (
        db.UniqueConstraint('user_id', 'gif_url', name='uq_user_gif_url'),
        db.UniqueConstraint('user_id', 'media_id', name='uq_user_media_gif'),
    )

    def to_dict(self):
        return {
            'id': self.id,
            'user_id': self.user_id,
            'media_id': self.media_id,
            'gif_url': self.gif_url,
            'external_id': self.external_id,
            'title': self.title,
            'preview_url': self.preview_url,
            'created_at': self.created_at.isoformat() + 'Z' if self.created_at else None,
        }
