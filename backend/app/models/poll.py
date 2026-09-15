from app import db
from datetime import datetime
import uuid

class PollVote(db.Model):
    __tablename__ = 'poll_votes'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    message_id = db.Column(db.String(36), db.ForeignKey('messages.id'), nullable=False, index=True)
    user_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)
    option_index = db.Column(db.Integer, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    __table_args__ = (
        db.UniqueConstraint('message_id', 'user_id', 'option_index', name='uq_poll_vote_option'),
        db.Index('idx_poll_vote_user', 'message_id', 'user_id'),
    )
