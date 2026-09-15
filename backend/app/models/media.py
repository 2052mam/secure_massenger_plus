from app import db
from datetime import datetime
import uuid

class MediaFile(db.Model):
    __tablename__ = 'media_files'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    uploader_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False)
    
    original_name = db.Column(db.String(255), nullable=False)
    stored_name = db.Column(db.String(255), nullable=False, unique=True)
    mime_type = db.Column(db.String(100), nullable=False)
    file_size = db.Column(db.BigInteger, nullable=False)
    file_path = db.Column(db.String(500), nullable=False)
    
    # image | video | audio | document
    media_type = db.Column(db.String(20), nullable=False)
    
    width = db.Column(db.Integer, nullable=True)
    height = db.Column(db.Integer, nullable=True)
    duration = db.Column(db.Float, nullable=True)  # seconds for audio/video
    thumbnail_path = db.Column(db.String(500), nullable=True)
    # Music metadata (Telegram-like internal player)
    title = db.Column(db.String(200), nullable=True)
    artist = db.Column(db.String(200), nullable=True)
    
    # Soft Delete
    is_deleted = db.Column(db.Boolean, default=False)
    deleted_at = db.Column(db.DateTime, nullable=True)
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
