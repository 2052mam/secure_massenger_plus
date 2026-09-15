"""Isolated API tests; never connect to the developer's MySQL database."""
import io
from datetime import datetime, timedelta

import pytest
from flask_jwt_extended import create_access_token
from PIL import Image

from app import create_app, db
from app.models.chat import Chat, ChatMember
from app.models.message import Message
from app.models.user import User


@pytest.fixture()
def app(tmp_path, monkeypatch):
    monkeypatch.setenv('DATABASE_URL', f'sqlite:///{tmp_path / "test.sqlite"}')
    monkeypatch.setenv('UPLOAD_FOLDER', str(tmp_path / 'uploads'))
    monkeypatch.setenv('SECRET_KEY', 'isolated-test-secret-at-least-32-characters')
    monkeypatch.setenv('JWT_SECRET_KEY', 'isolated-test-jwt-secret-at-least-32-characters')
    app = create_app()
    app.config.update(TESTING=True)
    with app.app_context():
        db.create_all()
        for name in ('alice', 'bob', 'carol'):
            db.session.add(User(
                id=name, email=f'{name}@example.test', username=name,
                display_name=name.title(), password_hash='unused-test-hash',
                totp_secret='JBSWY3DPEHPK3PXP',
            ))
        db.session.flush()
        db.session.add_all([
            Chat(id='chat', chat_type='private', created_by='alice'),
            Chat(id='other', chat_type='private', created_by='carol'),
        ])
        db.session.flush()
        for chat_id, users in [('chat', ('alice', 'bob')), ('other', ('carol', 'alice'))]:
            for name in users:
                db.session.add(ChatMember(chat_id=chat_id, user_id=name))
        db.session.commit()
    yield app
    with app.app_context():
        db.session.remove()
        db.drop_all()
        db.engine.dispose()


@pytest.fixture()
def client(app):
    return app.test_client()


@pytest.fixture()
def auth(app):
    def headers(name='alice'):
        with app.app_context():
            return {'Authorization': f'Bearer {create_access_token(identity=name)}'}
    return headers


@pytest.fixture()
def make_message(app):
    def make(message_id='original', **kwargs):
        with app.app_context():
            values = dict(id=message_id, chat_id='chat', sender_id='alice',
                          content='Original message', message_type='text',
                          created_at=datetime(2026, 9, 7) + timedelta(seconds=1))
            values.update(kwargs)
            msg = Message(**values)
            db.session.add(msg)
            db.session.commit()
            return msg.id
    return make


@pytest.fixture()
def upload(client, auth):
    def send(name='alice', filename='photo.png', data=None):
        if data is None:
            stream = io.BytesIO()
            Image.new('RGB', (16, 12), 'blue').save(stream, format='PNG')
            data = stream.getvalue()
        response = client.post('/api/v1/media/upload', headers=auth(name),
                               data={'file': (io.BytesIO(data), filename)})
        assert response.status_code == 201
        return response.json['id'], data
    return send
