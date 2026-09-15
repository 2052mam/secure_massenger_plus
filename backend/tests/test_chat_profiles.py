from datetime import datetime, timedelta

from app import db
from app.models.chat import Chat, ChatMember
from app.models.user import User


def test_empty_private_chat_info_identifies_peer_and_avatar(app, client, auth):
    with app.app_context():
        bob = db.session.get(User, 'bob')
        bob.avatar_url = '/api/v1/media/avatar-bob'
        bob.is_online = True
        bob.last_seen = datetime.utcnow()
        db.session.commit()
    result = client.get('/api/v1/chats/chat/info', headers=auth())
    assert result.status_code == 200
    assert result.json['other_user']['id'] == 'bob'
    assert result.json['other_user']['avatar_url'] == '/api/v1/media/avatar-bob'
    assert result.json['other_user']['is_online'] is True
    assert 'email' not in result.json['other_user']
    # The other side always sees its own peer, not the creator or last sender.
    assert client.get('/api/v1/chats/chat/info', headers=auth('bob')).json['other_user']['id'] == 'alice'
    assert client.get('/api/v1/chats/chat/info', headers=auth('carol')).status_code == 403


def test_profile_privacy_is_respected_by_header_and_polling(app, client, auth):
    with app.app_context():
        bob = db.session.get(User, 'bob')
        bob.avatar_url = '/private-photo'
        bob.bio = 'private bio'
        bob.is_online = True
        bob.last_seen = datetime.utcnow()
        bob.show_profile_photo = False
        bob.show_last_seen = False
        bob.show_bio = False
        db.session.commit()
    info = client.get('/api/v1/chats/chat/info', headers=auth()).json['other_user']
    profile = client.get('/api/v1/users/bob', headers=auth()).json
    listed = next(c for c in client.get('/api/v1/chats/', headers=auth()).json['chats'] if c['id'] == 'chat')['other_user']
    for payload in (info, profile, listed):
        assert payload['avatar_url'] is None
        assert payload['last_seen'] is None
        assert payload['is_online'] is False
        assert payload['bio'] is None


def test_heartbeat_expires_and_resumes_without_reopening_chat(app, client, auth):
    with app.app_context():
        bob = db.session.get(User, 'bob')
        bob.is_online = True
        bob.last_seen = datetime.utcnow() - timedelta(seconds=61)
        db.session.commit()
    def peer():
        return client.get('/api/v1/chats/chat/info', headers=auth()).json['other_user']
    assert peer()['is_online'] is False
    assert peer()['last_seen'].endswith('Z')
    assert client.post('/api/v1/users/online-status', headers=auth('bob'), json={'is_online': True}).status_code == 200
    assert peer()['is_online'] is True
    client.post('/api/v1/users/online-status', headers=auth('bob'), json={'is_online': False})
    assert peer()['is_online'] is False


def test_group_header_has_member_count_not_an_arbitrary_sender(app, client, auth):
    with app.app_context():
        db.session.add(Chat(id='group', chat_type='group', created_by='alice', title='Our group'))
        db.session.add(ChatMember(chat_id='group', user_id='alice', role='owner'))
        db.session.commit()
    info = client.get('/api/v1/chats/group/info', headers=auth()).json
    assert info['other_user'] is None
    assert info['members_count'] == 1
    assert info['title'] == 'Our group'
