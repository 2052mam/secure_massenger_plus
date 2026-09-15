from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from pathlib import Path

import pytest

from app import db
from app.models.audit import AuditLog
from app.models.chat import ChatMember
from app.models.media import MediaFile
from app.models.message import Message, MessageHide


def send(client, auth, **values):
    return client.post('/api/v1/messages/', headers=auth('alice'), json={
        'chat_id': 'chat', 'message_type': 'text', 'content': 'My reply', **values,
    })


def test_send_history_search_and_poll_have_the_same_reply(client, auth, make_message):
    make_message()
    response = send(client, auth, reply_to_id='original')
    assert response.status_code == 201
    sent = response.json
    assert sent['reply_to_id'] == 'original'
    assert sent['sender']['display_name'] == 'Alice'
    assert sent['reply_to'] == {
        'id': 'original', 'sender_id': 'alice', 'sender_name': 'Alice',
        'message_type': 'text', 'content': 'Original message',
        'is_view_once': False, 'is_spoiler': False, 'is_unavailable': False, 'media_url': None,
    }
    for endpoint in ('/chat', '/search/chat?q=reply', '/poll'):
        result = client.get('/api/v1/messages' + endpoint, headers=auth('bob'))
        assert result.status_code == 200
        reply = next(m for m in result.json['messages'] if m['id'] == sent['id'])
        assert reply['reply_to'] == sent['reply_to']
        assert reply['reply_to_id'] == 'original'


def test_media_send_response_is_complete(client, auth, upload, make_message):
    make_message()
    mid, _ = upload()
    response = send(client, auth, message_type='image', media_id=mid,
                    content='', reply_to_id='original')
    assert response.status_code == 201
    assert response.json['media_id'] == mid
    assert response.json['media_url'] == f'/api/v1/media/{mid}'
    assert response.json['reply_to']['content'] == 'Original message'
    assert response.json['viewed_at'] is None
    assert response.json['is_view_once'] is False


def test_reply_to_old_message_is_independent_of_page(client, auth, make_message):
    make_message(created_at=datetime(2020, 1, 1))
    for i in range(60):
        make_message(f'new-{i:03}', created_at=datetime(2026, 1, 1) + timedelta(seconds=i))
    result = send(client, auth, reply_to_id='original')
    assert result.status_code == 201
    page = client.get('/api/v1/messages/chat', headers=auth('bob')).json['messages']
    assert 'original' not in [m['id'] for m in page]
    assert page[-1]['reply_to']['content'] == 'Original message'
    jump = client.get('/api/v1/messages/chat?from_id=original', headers=auth('bob'))
    assert jump.status_code == 200
    assert jump.json['messages'][0]['id'] == 'original'
    assert jump.json['has_more'] is True


@pytest.mark.parametrize('mode', ['hidden', 'deleted', 'cross-chat'])
def test_replies_never_expose_deleted_hidden_or_cross_chat_content(
        app, client, auth, make_message, mode):
    make_message()
    make_message('reply', reply_to_id='original', content='reply body')
    with app.app_context():
        original = db.session.get(Message, 'original')
        if mode == 'hidden':
            db.session.add(MessageHide(message_id='original', user_id='bob'))
        elif mode == 'deleted':
            original.is_deleted = True
            original.is_deleted_for_all = True
        else:
            original.chat_id = 'other'
        db.session.commit()
    for endpoint in ('/chat', '/search/chat?q=reply', '/poll'):
        result = client.get('/api/v1/messages' + endpoint, headers=auth('bob')).json
        reply = next(m for m in result['messages'] if m['id'] == 'reply')
        assert reply['reply_to'] == {'id': 'original', 'is_unavailable': True}
    # The privacy fix must keep records, not hard-delete them.
    with app.app_context():
        assert db.session.get(Message, 'original') is not None


def test_invalid_reply_references_are_rejected(app, client, auth, make_message):
    make_message('foreign', chat_id='other', content='secret')
    assert send(client, auth, reply_to_id='foreign').status_code == 400
    assert send(client, auth, reply_to_id='missing').status_code == 400
    make_message('hidden')
    with app.app_context():
        db.session.add(MessageHide(message_id='hidden', user_id='alice'))
        db.session.commit()
    assert send(client, auth, reply_to_id='hidden').status_code == 400
    assert client.get('/api/v1/messages/chat?from_id=foreign', headers=auth()).status_code == 404


def test_busy_polling_and_hidden_rows_do_not_skip_messages(app, client, auth, make_message):
    start = datetime(2026, 1, 1)
    for i in range(120):
        make_message(f'm-{i:03}', created_at=start + timedelta(seconds=i))
    page = client.get('/api/v1/messages/chat?after_id=m-000&limit=10', headers=auth()).json
    assert [m['id'] for m in page['messages']] == [f'm-{i:03}' for i in range(1, 11)]
    assert page['has_more'] is True
    with app.app_context():
        for i in range(50, 120):
            db.session.add(MessageHide(message_id=f'm-{i:03}', user_id='bob'))
        db.session.commit()
    page = client.get('/api/v1/messages/chat?limit=30', headers=auth('bob')).json
    assert len(page['messages']) == 30
    assert page['messages'][-1]['id'] == 'm-049'
    assert client.get('/api/v1/messages/chat?limit=invalid', headers=auth()).status_code == 400


def make_once(client, auth, upload):
    media_id, data = upload()
    response = send(client, auth, message_type='image', content='',
                    media_id=media_id, is_view_once=True)
    assert response.status_code == 201
    assert response.json['media_url'] is None
    return response.json['id'], media_id, data


def test_view_once_download_then_consume_then_cannot_reopen(app, client, auth, upload):
    message_id, media_id, data = make_once(client, auth, upload)
    url = f'/api/v1/messages/{message_id}/view-once'
    with client.get(url + '/media', headers=auth('bob')) as response:
        assert response.status_code == 200
        assert response.data == data  # Actual photo bytes, not a 'viewed' label.
        assert 'no-store' in response.headers['Cache-Control']
    with app.app_context():
        assert db.session.get(Message, message_id).viewed_at is None
    result = client.post(url, headers=auth('bob'), json={})
    assert result.status_code == 200
    assert result.json['viewed_at']
    assert client.post(url, headers=auth('bob'), json={}).status_code == 410
    assert client.get(url + '/media', headers=auth('bob')).status_code == 410
    for name in ('alice', 'bob', 'carol'):
        assert client.get(f'/api/v1/media/{media_id}', headers=auth(name)).status_code == 403
    with app.app_context():
        assert AuditLog.query.filter_by(action='view_once_opened', entity_id=message_id).count() == 1
    status = client.post('/api/v1/messages/statuses', headers=auth(),
                         json={'message_ids': [message_id]}).json
    assert status['viewed_at'][message_id] == result.json['viewed_at']


def test_view_once_sender_stranger_and_left_member_cannot_consume(app, client, auth, upload):
    mid, _, _ = make_once(client, auth, upload)
    url = f'/api/v1/messages/{mid}/view-once'
    for name in ('alice', 'carol'):
        assert client.get(url + '/media', headers=auth(name)).status_code == 403
        assert client.post(url, headers=auth(name), json={}).status_code == 403
    assert client.get(url + '/media').status_code == 401
    with app.app_context():
        ChatMember.query.filter_by(chat_id='chat', user_id='bob').first().is_deleted = True
        db.session.commit()
    assert client.post(url, headers=auth('bob'), json={}).status_code == 403
    with app.app_context():
        assert db.session.get(Message, mid).viewed_at is None


def test_view_once_missing_file_does_not_consume(app, client, auth, upload):
    mid, media_id, _ = make_once(client, auth, upload)
    with app.app_context():
        Path(db.session.get(MediaFile, media_id).file_path).unlink()
    assert client.get(f'/api/v1/messages/{mid}/view-once/media', headers=auth('bob')).status_code == 404
    with app.app_context():
        assert db.session.get(Message, mid).viewed_at is None


def test_ephemeral_media_cannot_leak_through_replies_forward_or_resend(client, auth, upload):
    mid, media_id, _ = make_once(client, auth, upload)
    reply = send(client, auth, reply_to_id=mid).json['reply_to']
    assert reply['is_view_once'] is True
    assert reply['media_url'] is None
    assert reply['content'] is None
    assert client.post(f'/api/v1/messages/{mid}/forward', headers=auth(),
                       json={'target_chat_id': 'other'}).status_code == 403
    assert send(client, auth, media_id=media_id, message_type='image').status_code == 400
    assert client.post(f'/api/v1/messages/{mid}/delete', headers=auth(), json={'for_all': True}).status_code == 200
    assert client.get(f'/api/v1/media/{media_id}', headers=auth()).status_code == 403


def test_concurrent_view_once_claims_have_exactly_one_winner(app, client, auth, upload):
    mid, _, _ = make_once(client, auth, upload)
    headers = auth('bob')
    url = f'/api/v1/messages/{mid}/view-once'
    # Two devices can prepare the image, but only one may reveal it.
    for _ in range(2):
        with client.get(url + '/media', headers=headers) as response:
            assert response.status_code == 200
    def claim(_):
        with app.test_client() as device:
            return device.post(url, headers=headers, json={}).status_code
    with ThreadPoolExecutor(max_workers=2) as pool:
        assert sorted(pool.map(claim, range(2))) == [200, 410]


def test_normal_media_supports_authenticated_range_requests(client, auth, upload):
    data = bytes(range(256)) * 4
    mid, _ = upload(filename='voice.m4a', data=data)
    for byte_range, expected in [('bytes=100-199', data[100:200]), ('bytes=800-', data[800:])]:
        with client.get(f'/api/v1/media/{mid}', headers={**auth(), 'Range': byte_range}) as response:
            assert response.status_code == 206
            assert response.data == expected
            assert response.headers['Accept-Ranges'] == 'bytes'
            assert response.headers['Content-Range'].endswith('/1024')
    assert client.get(f'/api/v1/media/{mid}').status_code == 401


def test_normal_forward_still_works_but_source_membership_is_required(client, auth, make_message):
    mid = make_message()
    assert client.post(f'/api/v1/messages/{mid}/forward', headers=auth(),
                       json={'target_chat_id': 'other'}).status_code == 201
    assert client.post(f'/api/v1/messages/{mid}/forward', headers=auth('carol'),
                       json={'target_chat_id': 'other'}).status_code == 403


def test_view_once_validates_media_ownership_and_type(client, auth, upload):
    assert send(client, auth, is_view_once=True).status_code == 400
    foreign_id, _ = upload(name='bob')
    assert send(client, auth, media_id=foreign_id, message_type='image', is_view_once=True).status_code == 403
    audio_id, _ = upload(filename='audio.m4a', data=b'audio')
    assert send(client, auth, media_id=audio_id, message_type='image', is_view_once=True).status_code == 400


def test_read_receipts_do_not_consume_view_once(client, auth, upload):
    mid, _, _ = make_once(client, auth, upload)
    assert client.post('/api/v1/messages/chat/chat/read', headers=auth('bob'), json={}).status_code == 200
    result = client.post('/api/v1/messages/statuses', headers=auth(), json={'message_ids': [mid]}).json
    assert result['statuses'][mid] == 'read'
    assert result['viewed_at'][mid] is None
    with client.get(f'/api/v1/messages/{mid}/view-once/media', headers=auth('bob')) as response:
        assert response.status_code == 200
    assert client.post(f'/api/v1/messages/{mid}/view-once', headers=auth('bob'), json={}).status_code == 200
    result = client.post('/api/v1/messages/statuses', headers=auth(), json={'message_ids': [mid]}).json
    assert result['statuses'][mid] == 'read'
    assert result['viewed_at'][mid] is not None


@pytest.mark.parametrize('cursor', ['before_id', 'after_id'])
def test_cross_chat_cursors_are_rejected(client, auth, make_message, cursor):
    make_message('other-message', chat_id='other')
    result = client.get(f'/api/v1/messages/chat?{cursor}=other-message', headers=auth())
    assert result.status_code == 404


def test_equal_timestamp_pagination_is_stable(client, auth, make_message):
    for i in range(10):
        make_message(f'm-{i:03}', created_at=datetime(2026, 9, 7))
    result = client.get('/api/v1/messages/chat?limit=3', headers=auth()).json
    assert [m['id'] for m in result['messages']] == ['m-007', 'm-008', 'm-009']
    result = client.get('/api/v1/messages/chat?before_id=m-007&limit=3', headers=auth()).json
    assert [m['id'] for m in result['messages']] == ['m-004', 'm-005', 'm-006']
    result = client.get('/api/v1/messages/chat?after_id=m-004&limit=3', headers=auth()).json
    assert [m['id'] for m in result['messages']] == ['m-005', 'm-006', 'm-007']
