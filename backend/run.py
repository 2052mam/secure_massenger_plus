from app import create_app, db
from app.models import *
from app.models.user import User
from werkzeug.security import generate_password_hash
import os

app = create_app()

def seed_support_user():
    """ایجاد کاربر پشتیبانی در صورت نبود"""
    with app.app_context():
        support = User.query.filter_by(is_support=True, is_deleted=False).first()
        if not support:
            support = User(
                email='support@securemessenger.local',
                username='support',
                display_name='پشتیبانی',
                is_support=True,
                is_admin=False,
                is_2fa_enabled=True,
            )
            support.set_password('SupportPass123!')
            support.generate_totp_secret()
            db.session.add(support)
            db.session.commit()
            print('Support user created: support@securemessenger.local')

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
        seed_support_user()
    app.run(host='0.0.0.0', port=5000, debug=False)
