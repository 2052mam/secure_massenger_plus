"""Deletion reconciliation is HTTP polling, independent of new messages."""
from datetime import datetime, timedelta

import pytest
from sqlalchemy import event

from app import db
from app.models.audit import AuditLog
from app.models.chat import Chat, ChatMember
from app.models.message import Message, MessageHide, MessageStatus


def sync(client, auth, ids, user='bob', **extra):
    return client.post('/api/v1/messages/statuses', headers=auth(user), json={
        'chat_id': 'chat', 'message_ids': ids, **extra,
    })


@pytest.mark.parametrize('kind', ['text', 'image', 'video', 'voice', 'audio', 'file', 'system'])
def test_delete_for_all_arrives_on_next_poll_even_after_read(
        app, client, auth, make_message, kind):
    mid = make_message(message_type=kind)
    client.post('/api/v1/messages/chat/chat/read', headers=auth('bob'), json={})
    assert sync(client, auth, [mid]).json['deleted_ids'] == []
    result = client.post(f'/api/v1/messages/{mid}/delete', headers=auth(), json={'for_all': True})
    assert result.status_code == 200
    # after_id sees no new messages; the reconciliation poll still removes it.
    assert client.get(f'/api/v1/messages/chat?after_id={mid}', headers=auth('bob')).json['messages'] == []
    for user in ('alice', 'bob'):
        result = sync(client, auth, [mid], user=user)
        assert result.status_code == 200
        assert result.json == {'deleted_ids': [mid], 'statuses': {}, 'viewed_at': {},
                               'pinned_ids': []}
        # Missing a poll cannot lose the deletion event.
        assert sync(client, auth, [mid], user=user).json == result.json
    with app.app_context():
        assert db.session.get(Message, mid).is_deleted_for_all is True
        assert AuditLog.query.filter_by(entity_id=mid, action='delete_message_for_all').count() == 1


def test_delete_for_me_is_shared_only_with_my_other_sessions(app, client, auth, make_message):
    mid = make_message()
    assert client.post(f'/api/v1/messages/{mid}/delete', headers=auth('bob'), json={}).status_code == 200
    assert sync(client, auth, [mid]).json['deleted_ids'] == [mid]
    assert sync(client, auth, [mid], user='alice').json['deleted_ids'] == []
    with app.app_context():
        assert db.session.get(Message, mid).is_deleted is False
        assert MessageHide.query.filter_by(message_id=mid, user_id='bob').count() == 1
    # Neither the last-message snippet nor the unread badge may resurrect it.
    chat = next(c for c in client.get('/api/v1/chats/', headers=auth('bob')).json['chats'] if c['id'] == 'chat')
    assert chat['last_message'] is None
    assert chat['unread_count'] == 0
    chat = next(c for c in client.get('/api/v1/chats/', headers=auth()).json['chats'] if c['id'] == 'chat')
    assert chat['last_message']['id'] == mid


@pytest.mark.parametrize('for_all', [False, True])
def test_clear_history_and_old_quoted_originals_are_reconciled(
        client, auth, make_message, for_all):
    ids = [make_message(f'm-{i:03}', created_at=datetime(2020, 1, 1) + timedelta(seconds=i)) for i in range(125)]
    make_message('reply', reply_to_id=ids[0])
    assert client.post('/api/v1/messages/chat/chat/clear', headers=auth(), json={'for_all': for_all}).status_code == 200
    for user in ('alice', 'bob'):
        expected = set(ids) if for_all or user == 'alice' else set()
        deleted = set()
        for offset in range(0, len(ids), 100):
            deleted.update(sync(client, auth, ids[offset:offset + 100], user=user).json['deleted_ids'])
        assert deleted == expected
    # A new message after a clear must still be found using a deleted cursor.
    newest = make_message('after-clear', content='New message', created_at=datetime(2027, 1, 1))
    result = client.get('/api/v1/messages/chat?after_id=reply', headers=auth()).json
    assert [m['id'] for m in result['messages']] == [newest]


def test_sync_keeps_view_once_and_read_receipts_but_not_deleted_media(app, client, auth, make_message):
    mid = make_message(is_view_once=True, message_type='image')
    with app.app_context():
        db.session.add(MessageStatus(message_id=mid, user_id='bob', status='read'))
        db.session.get(Message, mid).viewed_at = datetime(2026, 9, 7, 12)
        db.session.commit()
    result = sync(client, auth, [mid], user='alice').json
    assert result['statuses'] == {mid: 'read'}
    assert result['viewed_at'] == {mid: '2026-09-07T12:00:00Z'}
    assert sync(client, auth, [mid]).json['statuses'] == {}
    client.post(f'/api/v1/messages/{mid}/delete', headers=auth(), json={'for_all': True})
    assert sync(client, auth, [mid]).json == {'deleted_ids': [mid], 'statuses': {},
                                              'viewed_at': {}, 'pinned_ids': []}


@pytest.mark.parametrize('ids', [None, 'original', {}, [None], [12], [['id']], [''], ['x' * 37], ['id'] * 101])
def test_sync_validates_id_batches(client, auth, ids):
    assert sync(client, auth, ids).status_code == 400


def test_sync_never_leaks_unrelated_or_left_chat_ids(app, client, auth, make_message):
    mid = make_message(is_deleted=True, is_view_once=True)
    foreign = make_message('foreign', chat_id='other', is_deleted=True, is_view_once=True)
    assert sync(client, auth, [mid, foreign, 'missing']).json['deleted_ids'] == [mid]
    assert sync(client, auth, [mid], user='carol').status_code == 403
    # The legacy, unscoped endpoint must enforce membership too.
    result = client.post('/api/v1/messages/statuses', headers=auth('carol'), json={'message_ids': [mid]}).json
    assert result == {'deleted_ids': [], 'statuses': {}, 'viewed_at': {}, 'pinned_ids': []}
    with app.app_context():
        ChatMember.query.filter_by(chat_id='chat', user_id='bob').first().is_deleted = True
        db.session.commit()
    assert sync(client, auth, [mid]).status_code == 403


def test_sync_rejects_deleted_chat(app, client, auth, make_message):
    mid = make_message()
    with app.app_context():
        db.session.get(Chat, 'chat').is_deleted_for_all = True
        db.session.commit()
    assert sync(client, auth, [mid]).status_code == 403


def test_sync_queries_are_batched(app, client, auth, make_message):
    ids = [make_message(f'm-{i:03}') for i in range(100)]
    headers = auth()
    statements = []
    with app.app_context():
        engine = db.engine
        def capture(_conn, _cursor, statement, _parameters, _context, _many):
            statements.append(statement)
        event.listen(engine, 'before_cursor_execute', capture)
        try:
            result = client.post('/api/v1/messages/statuses', headers=headers,
                                 json={'chat_id': 'chat', 'message_ids': ids})
        finally:
            event.remove(engine, 'before_cursor_execute', capture)
    assert result.status_code == 200
    assert len(result.json['statuses']) == 100
    assert len(statements) <= 5  # Not one membership/status query per message.


@pytest.mark.parametrize('body', [[], False, 42, 'ids'])
def test_non_object_poll_bodies_are_rejected(client, auth, body):
    response = client.post('/api/v1/messages/statuses', json=body, headers=auth())
    assert response.status_code == 400
