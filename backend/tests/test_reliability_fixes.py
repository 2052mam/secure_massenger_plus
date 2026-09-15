"""Regression tests for the five reported items (Telegram parity)."""
from datetime import datetime, timedelta

from app import db
from app.models.chat import Chat, ChatMember
from app.models.message import Message, MessageStatus
from app.models.user import UserDevice, UserSession


def _send(client, auth, **kwargs):
    payload = {'chat_id': 'chat', 'message_type': 'text', 'content': 'hi'}
    payload.update(kwargs)
    return client.post('/api/v1/messages/', headers=auth('alice'), json=payload)


def test_scheduled_dispatch_is_idempotent_after_early_read_receipt(
        app, client, auth):
    """Item 1: early read receipts must not break the timed dispatch."""
    future = (datetime.utcnow() + timedelta(hours=1)).isoformat()
    res = _send(client, auth, content='timed', scheduled_at=future)
    assert res.status_code == 201
    msg_id = res.json['id']
    assert res.json['is_scheduled'] is True

    # Simulate the old mark_chat_read creating a status row early.
    with app.app_context():
        db.session.add(MessageStatus(
            message_id=msg_id, user_id='bob', status='read',
            read_at=datetime.utcnow(), delivered_at=datetime.utcnow(),
        ))
        msg = db.session.get(Message, msg_id)
        msg.scheduled_at = datetime.utcnow() - timedelta(seconds=1)
        db.session.commit()

    # The chat must still load (previously: 500 HTML with <!DOCTYPE).
    history = client.get('/api/v1/messages/chat', headers=auth('bob'))
    assert history.status_code == 200
    assert any(m['id'] == msg_id for m in history.json['messages'])
    # A second poll (concurrent dispatch) must also succeed.
    again = client.get('/api/v1/messages/chat', headers=auth('alice'))
    assert again.status_code == 200
    with app.app_context():
        rows = MessageStatus.query.filter_by(message_id=msg_id).all()
        # One row per user, never duplicates.
        assert sorted(r.user_id for r in rows) == ['alice', 'bob']
        assert db.session.get(Message, msg_id).is_scheduled is False


def test_mark_chat_read_ignores_scheduled(app, client, auth):
    future = (datetime.utcnow() + timedelta(hours=1)).isoformat()
    res = _send(client, auth, content='future', scheduled_at=future)
    assert res.json['is_scheduled'] is True
    assert client.post(
        '/api/v1/messages/chat/chat/read', headers=auth('bob'), json={},
    ).status_code == 200
    with app.app_context():
        assert MessageStatus.query.filter_by(
            message_id=res.json['id'], user_id='bob').first() is None


def test_api_errors_are_json_not_html(client, auth):
    res = client.get('/api/v1/messages/nope', headers=auth('alice'))
    assert res.status_code == 403
    assert res.is_json
    assert 'doctype' not in res.get_data(as_text=True).lower()
    res = client.get('/api/v1/messages/poll?limit=banana', headers=auth('alice'))
    assert res.status_code == 400
    assert res.is_json


def test_timed_photo_lifecycle(app, client, auth, upload):
    """Item 2: timed photo behaves like view-once + countdown."""
    media_id, _ = upload('alice')
    res = _send(
        client, auth, message_type='image', media_id=media_id, content='',
        is_view_once=True, view_duration=10,
    )
    assert res.status_code == 201, res.json
    assert res.json['is_view_once'] is True
    assert res.json['view_duration'] == 10
    mid = res.json['id']

    # Rejects bad durations and non-photo timed messages.
    media2, _ = upload('alice')
    bad = _send(
        client, auth, message_type='image', media_id=media2,
        is_view_once=True, view_duration=999,
    )
    assert bad.status_code == 400
    bad2 = _send(
        client, auth, message_type='text', content='x',
        is_view_once=True, view_duration=10,
    )
    assert bad2.status_code == 400

    # Timed photos cannot be forwarded, like view-once.
    fwd = client.post(f'/api/v1/messages/{mid}/forward', headers=auth('bob'),
                      json={'target_chat_id': 'other'})
    assert fwd.status_code == 403

    # Download works before consuming, generic media URL stays blocked.
    assert client.get(
        f'/api/v1/messages/{mid}/view-once/media',
        headers=auth('bob'),
    ).status_code == 200
    assert client.get(
        f'/api/v1/media/{media_id}', headers=auth('bob')).status_code == 403

    # Consume: server returns the countdown deadline.
    consume = client.post(
        f'/api/v1/messages/{mid}/view-once', headers=auth('bob'), json={})
    assert consume.status_code == 200
    assert consume.json['view_duration'] == 10
    assert 'view_expires_at' in consume.json
    # Second open is gone.
    assert client.get(
        f'/api/v1/messages/{mid}/view-once/media',
        headers=auth('bob'),
    ).status_code == 410


def test_device_termination_revokes_tokens(app, client, auth):
    """Item 4: terminating a device must disconnect it for real."""
    from flask_jwt_extended import create_access_token
    with app.app_context():
        device = UserDevice(
            id='dev-bob', user_id='bob',
            device_fingerprint='fp-bob-1', device_name='Bob phone',
        )
        db.session.add(device)
        db.session.commit()
        token = create_access_token(
            identity='bob', additional_claims={'device_id': 'dev-bob'})
        db.session.add(UserSession(
            user_id='bob', device_id='dev-bob', refresh_token='rt-bob-1',
            expires_at=datetime.utcnow() + timedelta(days=1),
        ))
        db.session.commit()
    bob = {'Authorization': f'Bearer {token}'}
    assert client.get('/api/v1/devices/', headers=bob).status_code == 200
    # Bob terminates... no: Alice cannot touch Bob's device.
    assert client.post(
        '/api/v1/devices/dev-bob/terminate', headers=auth('alice'),
        json={}).status_code == 404
    # Bob terminates his own second device from the first one.
    with app.app_context():
        other = UserDevice(
            id='dev-bob-2', user_id='bob',
            device_fingerprint='fp-bob-2', device_name='Bob tablet',
        )
        db.session.add(other)
        db.session.commit()
        token2 = create_access_token(
            identity='bob', additional_claims={'device_id': 'dev-bob-2'})
        db.session.add(UserSession(
            user_id='bob', device_id='dev-bob-2', refresh_token='rt-bob-2',
            expires_at=datetime.utcnow() + timedelta(days=1),
        ))
        db.session.commit()
    bob2 = {'Authorization': f'Bearer {token2}'}
    kill = client.post(
        '/api/v1/devices/dev-bob/terminate', headers=bob2, json={})
    assert kill.status_code == 200, kill.json
    # The terminated device is rejected immediately with a JSON 401.
    gone = client.get('/api/v1/devices/', headers=bob)
    assert gone.status_code == 401
    assert gone.is_json
    assert gone.json.get('code') == 'device_terminated'
    with app.app_context():
        assert UserSession.query.filter_by(
            device_id='dev-bob', is_active=True).count() == 0


def test_delete_chat_for_all_wipes_history_for_everyone(client, auth):
    """Item 5: two-way delete removes the chat AND its history for both."""
    _send(client, auth, content='one')
    _send(client, auth, content='two')
    res = client.post(
        '/api/v1/chats/chat/delete', headers=auth('alice'),
        json={'for_all': True},
    )
    assert res.status_code == 200
    # Both sides lose the chat and its messages.
    assert client.get('/api/v1/messages/chat', headers=auth('alice')).status_code == 403
    assert client.get('/api/v1/messages/chat', headers=auth('bob')).status_code == 403
    chats = client.get('/api/v1/chats/', headers=auth('bob'))
    assert all(c['id'] != 'chat' for c in chats.json['chats'])


def test_notifications_pending_feed(client, auth):
    """Item 3: background polling feed returns only new foreign messages."""
    first = client.get('/api/v1/notifications/pending', headers=auth('bob'))
    assert first.status_code == 200
    assert first.json['messages'] == []
    baseline = first.json['server_time']
    _send(client, auth, content='hello bob')
    pending = client.get(
        '/api/v1/notifications/pending',
        headers=auth('bob'), query_string={'since': baseline},
    )
    assert pending.status_code == 200
    assert len(pending.json['messages']) == 1
    item = pending.json['messages'][0]
    assert item['preview'] == 'hello bob'
    assert item['chat_id'] == 'chat'
    # The sender sees nothing new.
    mine = client.get(
        '/api/v1/notifications/pending',
        headers=auth('alice'), query_string={'since': baseline},
    )
    assert mine.json['messages'] == []
    # Register preference.
    reg = client.post(
        '/api/v1/notifications/register', headers=auth('bob'),
        json={'notifications_enabled': True},
    )
    assert reg.status_code in (200, 404)
