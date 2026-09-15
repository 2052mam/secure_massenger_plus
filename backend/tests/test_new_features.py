from datetime import datetime, timedelta
import time
from app import db
from app.models.chat import Chat, ChatMember
from app.models.message import Message


def test_spoiler_mode(client, auth):
    res = client.post('/api/v1/messages/', headers=auth('alice'), json={
        'chat_id': 'chat', 'message_type': 'text', 'content': 'Secret spoiler', 'is_spoiler': True,
    })
    assert res.status_code == 201
    assert res.json['is_spoiler'] is True

    # Poll history
    get_res = client.get('/api/v1/messages/chat', headers=auth('bob'))
    assert get_res.status_code == 200
    msg = [m for m in get_res.json['messages'] if m['id'] == res.json['id']][0]
    assert msg['is_spoiler'] is True


def test_file_message_and_download(client, auth, upload):
    mid, _ = upload(filename='document.pdf', data=b'%PDF-1.4 test content')
    res = client.post('/api/v1/messages/', headers=auth('alice'), json={
        'chat_id': 'chat', 'message_type': 'file', 'content': 'document.pdf', 'media_id': mid
    })
    assert res.status_code == 201
    assert res.json['message_type'] == 'file'
    assert res.json['media_id'] == mid

    # Test download parameter
    dl_res = client.get(f'/api/v1/media/{mid}?download=1', headers=auth('bob'))
    assert dl_res.status_code == 200
    assert 'attachment' in dl_res.headers.get('Content-Disposition', '')


def test_slow_mode_in_group(app, client, auth):
    # Set slow_mode_delay = 5 seconds on group 'chat'
    with app.app_context():
        chat = db.session.get(Chat, 'chat')
        chat.chat_type = 'group'
        chat.slow_mode_delay = 5
        db.session.commit()

    # Bob is regular member (role='member')
    with app.app_context():
        member = ChatMember.query.filter_by(chat_id='chat', user_id='bob').first()
        if member:
            member.role = 'member'
            db.session.commit()

    # Bob sends first message: OK
    res1 = client.post('/api/v1/messages/', headers=auth('bob'), json={
        'chat_id': 'chat', 'message_type': 'text', 'content': 'First msg'
    })
    assert res1.status_code == 201

    # Bob sends second message immediately: 429 Too Many Requests
    res2 = client.post('/api/v1/messages/', headers=auth('bob'), json={
        'chat_id': 'chat', 'message_type': 'text', 'content': 'Second msg'
    })
    assert res2.status_code == 429
    assert 'remaining_seconds' in res2.json

    # Alice (owner/admin) sends message immediately: OK (owners/admins bypass slow mode)
    res_alice = client.post('/api/v1/messages/', headers=auth('alice'), json={
        'chat_id': 'chat', 'message_type': 'text', 'content': 'Admin msg'
    })
    assert res_alice.status_code == 201


def test_scheduled_message_lifecycle(app, client, auth):
    future_time = (datetime.utcnow() + timedelta(hours=2)).isoformat()
    res = client.post('/api/v1/messages/', headers=auth('alice'), json={
        'chat_id': 'chat', 'message_type': 'text', 'content': 'Scheduled for future',
        'scheduled_at': future_time,
    })
    assert res.status_code == 201
    msg_id = res.json['id']
    assert res.json['is_scheduled'] is True

    # Scheduled message must NOT appear in normal history for Bob or Alice
    hist = client.get('/api/v1/messages/chat', headers=auth('bob')).json['messages']
    assert not any(m['id'] == msg_id for m in hist)

    # But MUST appear in scheduled list for Alice
    sched_res = client.get('/api/v1/messages/chat/chat/scheduled', headers=auth('alice'))
    assert sched_res.status_code == 200
    sched_list = sched_res.json['messages']
    assert any(m['id'] == msg_id for m in sched_list)

    # Test send now
    send_now_res = client.post(f'/api/v1/messages/{msg_id}/scheduled/send-now', headers=auth('alice'), json={})
    assert send_now_res.status_code == 200
    assert send_now_res.json['is_scheduled'] is False

    # Now it MUST appear in normal history
    hist2 = client.get('/api/v1/messages/chat', headers=auth('bob')).json['messages']
    assert any(m['id'] == msg_id for m in hist2)


def test_cancel_scheduled_message(client, auth):
    future_time = (datetime.utcnow() + timedelta(hours=5)).isoformat()
    res = client.post('/api/v1/messages/', headers=auth('alice'), json={
        'chat_id': 'chat', 'message_type': 'text', 'content': 'To be canceled',
        'scheduled_at': future_time,
    })
    assert res.status_code == 201
    msg_id = res.json['id']

    # Cancel
    cancel_res = client.delete(f'/api/v1/messages/{msg_id}/scheduled', headers=auth('alice'))
    assert cancel_res.status_code == 200

    # Scheduled list is now empty
    sched_res = client.get('/api/v1/messages/chat/chat/scheduled', headers=auth('alice'))
    assert not any(m['id'] == msg_id for m in sched_res.json['messages'])


def test_shared_media_endpoint(client, auth, upload):
    mid_img, _ = upload(filename='photo.jpg', data=b'fake photo data')
    client.post('/api/v1/messages/', headers=auth('alice'), json={
        'chat_id': 'chat', 'message_type': 'image', 'content': 'Photo caption', 'media_id': mid_img
    })

    mid_file, _ = upload(filename='report.pdf', data=b'fake pdf data')
    client.post('/api/v1/messages/', headers=auth('alice'), json={
        'chat_id': 'chat', 'message_type': 'file', 'content': 'report.pdf', 'media_id': mid_file
    })

    sm_res = client.get('/api/v1/chats/chat/shared-media', headers=auth('bob'))
    assert sm_res.status_code == 200
    assert len(sm_res.json['media']) >= 1
    assert len(sm_res.json['files']) >= 1
