"""FCM wake-up ticks: data-only, never blocking, silent when unconfigured."""
from datetime import datetime, timedelta

import pytest
from flask_jwt_extended import create_access_token

import app.services.push_service as push
from app import db
from app.models.user import UserDevice, UserSession


class _HttpStub:
    def __init__(self, status=200, text='{"name":"x"}'):
        self.status_code = status
        self.text = text


def _device_headers(app, user_id, device_id):
    with app.app_context():
        token = create_access_token(
            identity=user_id, additional_claims={'device_id': device_id},
        )
    return {'Authorization': f'Bearer {token}'}


def _add_device(app, device_id, user_id, token='tok', platform='android'):
    with app.app_context():
        db.session.add(UserDevice(
            id=device_id, user_id=user_id,
            device_fingerprint=f'fp-{device_id}', device_name=device_id,
            push_token=token, push_platform=platform,
            notifications_enabled=True, is_deleted=False, is_active=True,
        ))
        db.session.commit()


@pytest.fixture()
def configured(monkeypatch):
    monkeypatch.setattr(push, 'push_configured', lambda: True)
    monkeypatch.setattr(push, '_access_token', lambda: 'test-access')
    monkeypatch.setattr(push, '_config', lambda: {'project_id': 'demo'})


def test_send_tick_noop_without_config_and_without_http(monkeypatch):
    monkeypatch.setattr(push, 'push_configured', lambda: False)

    def boom(*args, **kwargs):
        raise AssertionError('must not touch the network')

    monkeypatch.setattr(push, '_post_fcm', boom)
    assert push.send_tick(['tok'], {'kind': 'tick'}) == (0, [])
    assert push.send_tick([], {'kind': 'tick'}) == (0, [])


def test_send_tick_is_data_only_and_flags_stale_tokens(
        app, configured, monkeypatch):
    calls = []

    def fake_post(url, headers, payload):
        calls.append((url, headers, payload))
        token = payload['message']['token']
        if token == 'stale':
            return _HttpStub(404, '{"error":{"status":"NOT_FOUND"}}')
        return _HttpStub(200)

    monkeypatch.setattr(push, '_post_fcm', fake_post)
    delivered, stale = push.send_tick(
        ['good', 'stale', 'good', None, ''],
        {'kind': 'tick', 'chat_id': 'chat'},
        collapse_key='chat-chat',
    )
    assert delivered == 1
    assert stale == ['stale']
    # Deduped + empties dropped: exactly two HTTP calls.
    assert [c[2]['message']['token'] for c in calls] == ['good', 'stale']
    url, headers, payload = calls[0]
    assert 'demo' in url and url.endswith('/messages:send')
    assert headers['Authorization'] == 'Bearer test-access'
    message = payload['message']
    # Data-only: no notification payload may ever carry content to Google.
    assert 'notification' not in message
    assert message['data'] == {'kind': 'tick', 'chat_id': 'chat'}
    assert message['android']['priority'] == 'HIGH'
    assert message['android']['collapse_key'] == 'chat-chat'


def test_new_message_ticks_recipients_not_sender(
        app, client, auth, configured, monkeypatch):
    _add_device(app, 'dev-alice', 'alice', token='tok-alice')
    _add_device(app, 'dev-bob', 'bob', token='tok-bob')
    calls = []
    monkeypatch.setattr(
        push, '_send_async',
        lambda app_obj, tokens, data, collapse_key=None: calls.append(
            (tokens, data, collapse_key)),
    )
    res = client.post('/api/v1/messages/', headers=auth('alice'), json={
        'chat_id': 'chat', 'message_type': 'text', 'content': 'hi bob',
    })
    assert res.status_code == 201, res.json
    assert len(calls) == 1
    tokens, data, collapse_key = calls[0]
    assert tokens == ['tok-bob']
    assert data == {'kind': 'tick', 'chat_id': 'chat'}
    assert collapse_key == 'chat-chat'


def test_scheduled_message_ticks_on_dispatch_not_on_queue(
        app, client, auth, configured, monkeypatch):
    _add_device(app, 'dev-bob', 'bob', token='tok-bob')
    calls = []
    monkeypatch.setattr(
        push, '_send_async',
        lambda app_obj, tokens, data, collapse_key=None: calls.append(
            (tokens, data, collapse_key)),
    )
    future = (datetime.utcnow() + timedelta(hours=1)).isoformat()
    res = client.post('/api/v1/messages/', headers=auth('alice'), json={
        'chat_id': 'chat', 'message_type': 'text', 'content': 'later',
        'scheduled_at': future,
    })
    assert res.status_code == 201
    assert res.json['is_scheduled'] is True
    assert calls == []
    with app.app_context():
        from app.models.message import Message
        msg = db.session.get(Message, res.json['id'])
        msg.scheduled_at = datetime.utcnow() - timedelta(seconds=1)
        db.session.commit()
    # A poll dispatches the due message and fires the tick.
    history = client.get('/api/v1/messages/chat', headers=auth('bob'))
    assert history.status_code == 200
    assert len(calls) == 1
    assert calls[0][0] == ['tok-bob']
    assert calls[0][1] == {'kind': 'tick', 'chat_id': 'chat'}


def test_register_stores_and_clears_push_token(app, client):
    _add_device(app, 'dev-bob', 'bob', token=None, platform=None)
    headers = _device_headers(app, 'bob', 'dev-bob')
    res = client.post('/api/v1/notifications/register', headers=headers, json={
        'push_token': 'tok-new', 'platform': 'ios',
    })
    assert res.status_code == 200, res.json
    with app.app_context():
        device = db.session.get(UserDevice, 'dev-bob')
        assert device.push_token == 'tok-new'
        assert device.push_platform == 'ios'
    # Omitting the key leaves the token alone...
    res = client.post('/api/v1/notifications/register', headers=headers, json={
        'notifications_enabled': False,
    })
    assert res.status_code == 200
    with app.app_context():
        assert db.session.get(UserDevice, 'dev-bob').push_token == 'tok-new'
    # ...while an explicit empty token clears it (logout path).
    res = client.post('/api/v1/notifications/register', headers=headers, json={
        'push_token': '',
    })
    assert res.status_code == 200
    with app.app_context():
        device = db.session.get(UserDevice, 'dev-bob')
        assert device.push_token is None
        assert device.push_platform is None


def test_test_endpoint_404_without_config(client, auth):
    res = client.post('/api/v1/notifications/test', headers=auth('bob'))
    assert res.status_code == 404
    assert res.json['error'] == 'push_not_configured'


def test_test_endpoint_delivers_to_own_devices(
        app, client, configured, monkeypatch):
    _add_device(app, 'dev-bob', 'bob', token='tok-bob')
    seen = []
    monkeypatch.setattr(
        push, '_post_fcm',
        lambda url, headers, payload: (
            seen.append(payload['message']), _HttpStub(200))[1],
    )
    bob = _device_headers(app, 'bob', 'dev-bob')
    res = client.post('/api/v1/notifications/test', headers=bob)
    assert res.status_code == 200, res.json
    assert res.json == {'ok': True, 'delivered': 1}
    assert seen[0]['token'] == 'tok-bob'
    assert seen[0]['data'] == {'kind': 'test'}


def test_logout_and_terminate_clear_push_token(app, client):
    _add_device(app, 'dev-bob', 'bob', token='tok-bob')
    _add_device(app, 'dev-bob-2', 'bob', token='tok-bob-2')
    with app.app_context():
        db.session.add(UserSession(
            user_id='bob', device_id='dev-bob-2', refresh_token='rt-x',
            expires_at=datetime.utcnow() + timedelta(days=1),
        ))
        db.session.commit()
    # Terminating the second device from the first clears ITS token only.
    bob = _device_headers(app, 'bob', 'dev-bob')
    kill = client.post(
        '/api/v1/devices/dev-bob-2/terminate', headers=bob, json={})
    assert kill.status_code == 200, kill.json
    with app.app_context():
        assert db.session.get(UserDevice, 'dev-bob-2').push_token is None
        assert db.session.get(UserDevice, 'dev-bob').push_token == 'tok-bob'
    # Logging out the first device clears its token too.
    assert client.post('/api/v1/auth/logout', headers=bob).status_code == 200
    with app.app_context():
        assert db.session.get(UserDevice, 'dev-bob').push_token is None
