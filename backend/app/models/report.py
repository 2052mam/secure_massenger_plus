from app import db
from datetime import datetime
import uuid
from app.services.timestamps import utc_iso

class Report(db.Model):
    __tablename__ = 'reports'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    reporter_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)
    # target can be user, chat (group/channel), or message
    target_type = db.Column(db.String(20), nullable=False)  # user | group | channel | message
    target_user_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=True, index=True)
    target_chat_id = db.Column(db.String(36), db.ForeignKey('chats.id'), nullable=True, index=True)
    target_message_id = db.Column(db.String(36), db.ForeignKey('messages.id'), nullable=True, index=True)

    # Telegram-like reasons
    reason = db.Column(db.String(50), nullable=False)  # spam, violence, child_abuse, pornography, fake_account, copyright, illegal_drugs, personal_data, other
    description = db.Column(db.Text, nullable=True)

    status = db.Column(db.String(20), nullable=False, default='pending')  # pending | reviewed | action_taken | dismissed
    admin_note = db.Column(db.Text, nullable=True)
    resolved_by = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=True)
    resolved_at = db.Column(db.DateTime, nullable=True)

    created_at = db.Column(db.DateTime, default=datetime.utcnow, index=True)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    reporter = db.relationship('User', foreign_keys=[reporter_id], backref='reports_made')
    target_user = db.relationship('User', foreign_keys=[target_user_id])
    target_chat = db.relationship('Chat', foreign_keys=[target_chat_id])
    target_message = db.relationship('Message', foreign_keys=[target_message_id])

    def to_dict(self, include_reporter=False):
        data = {
            'id': self.id,
            'reporter_id': self.reporter_id,
            'target_type': self.target_type,
            'target_user_id': self.target_user_id,
            'target_chat_id': self.target_chat_id,
            'target_message_id': self.target_message_id,
            'reason': self.reason,
            'description': self.description,
            'status': self.status,
            'admin_note': self.admin_note,
            'resolved_by': self.resolved_by,
            'created_at': utc_iso(self.created_at),
            'updated_at': utc_iso(self.updated_at),
            'resolved_at': utc_iso(self.resolved_at) if self.resolved_at else None,
        }
        if include_reporter and self.reporter:
            data['reporter'] = self.reporter.to_dict()
        if self.target_user:
            data['target_user'] = self.target_user.to_dict()
        if self.target_chat:
            data['target_chat'] = {'id': self.target_chat.id, 'title': self.target_chat.title, 'chat_type': self.target_chat.chat_type, 'username': self.target_chat.username}
        if self.target_message:
            data['target_message'] = {'id': self.target_message.id, 'content': self.target_message.content, 'message_type': self.target_message.message_type}
        return data
