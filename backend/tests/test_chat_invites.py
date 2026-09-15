from uuid import uuid4

import pytest

from app import db
from app.models.audit import AuditLog
from app.models.chat import Chat, ChatMember


@pytest.fixture()
def group(app):
    chat_id = str(uuid4())
    with app.app_context():
        db.session.add(Chat(id=chat_id, chat_type='group', title='Private group',
                            created_by='alice', description='A group invitation'))
        db.session.add(ChatMember(chat_id=chat_id, user_id='alice', role='owner'))
        db.session.commit()
    return chat_id


def invite(client, auth, group):
    result = client.get(f'/api/v1/chats/{group}/invite-link', headers=auth())
    assert result.status_code == 200
    return result.json['invite_link']


def post_link(client, auth, link, action='join', user='bob'):
    return client.post(f'/api/v1/chats/{action}', headers=auth(user), json={'invite_link': link})


def test_private_invite_previews_then_joins_and_opens_history(app, client, auth, group):
    link = invite(client, auth, group)
    assert link.startswith('securemessenger://join/')
    assert link != f'securemessenger://join/{group}'  # New invites are signed.
    preview = post_link(client, auth, link, 'invite-preview')
    assert preview.status_code == 200
    assert preview.json == {
        'id': group, 'chat_type': 'group', 'title': 'Private group',
        'description': 'A group invitation', 'avatar_url': None,
        'members_count': 1, 'is_member': False,
    }
    assert client.get(f'/api/v1/messages/{group}', headers=auth('bob')).status_code == 403
    assert client.post(f'/api/v1/chats/{group}/add-member', headers=auth('bob'), json={'user_id': 'bob'}).status_code == 403
    joined = post_link(client, auth, link)
    assert joined.status_code == 200
    assert joined.json['id'] == group
    assert joined.json['is_member'] is True
    assert joined.json['members_count'] == 2
    assert client.get(f'/api/v1/messages/{group}', headers=auth('bob')).status_code == 200
    assert any(c['id'] == group for c in client.get('/api/v1/chats/', headers=auth('bob')).json['chats'])
    with app.app_context():
        assert AuditLog.query.filter_by(action='join_chat_by_invite', actor_id='bob', entity_id=group).count() == 1


def test_existing_member_and_repeated_taps_are_idempotent(app, client, auth, group):
    link = invite(client, auth, group)
    for _ in range(3):
        assert post_link(client, auth, link).status_code == 200
    assert post_link(client, auth, link, 'invite-preview').json['is_member'] is True
    with app.app_context():
        assert ChatMember.query.filter_by(chat_id=group, user_id='bob').count() == 1
        assert AuditLog.query.filter_by(action='join_chat_by_invite', actor_id='bob').count() == 1


def test_leaver_reuses_membership_without_restoring_admin_privileges(app, client, auth, group):
    link = invite(client, auth, group)
    post_link(client, auth, link)
    with app.app_context():
        member = ChatMember.query.filter_by(chat_id=group, user_id='bob').first()
        old_id = member.id
        member.role = 'admin'
        db.session.commit()
    assert client.post(f'/api/v1/chats/{group}/leave', headers=auth('bob'), json={}).status_code == 200
    assert post_link(client, auth, link).status_code == 200
    with app.app_context():
        member = ChatMember.query.filter_by(chat_id=group, user_id='bob').one()
        assert member.id == old_id
        assert member.is_deleted is False
        assert member.deleted_at is None
        assert member.deleted_by is None
        assert member.role == 'member'


def test_removed_user_cannot_bypass_removal_with_invite(client, auth, group):
    link = invite(client, auth, group)
    post_link(client, auth, link)
    assert client.post(f'/api/v1/chats/{group}/remove-member', headers=auth(), json={'user_id': 'bob'}).status_code == 200
    assert post_link(client, auth, link, 'invite-preview').status_code == 403
    assert post_link(client, auth, link).status_code == 403


def test_previously_shared_uuid_links_still_work(client, auth, group):
    link = f'securemessenger://join/{group}'
    assert post_link(client, auth, link, 'invite-preview').status_code == 200
    assert post_link(client, auth, link).status_code == 200


@pytest.mark.parametrize('kind', ['private', 'support', 'saved'])
def test_invites_never_grant_access_to_one_to_one_or_saved_chats(app, client, auth, group, kind):
    link = invite(client, auth, group)
    with app.app_context():
        db.session.get(Chat, group).chat_type = kind
        db.session.commit()
    assert client.get(f'/api/v1/chats/{group}/invite-link', headers=auth()).status_code == 400
    for value in (link, f'securemessenger://join/{group}'):
        assert post_link(client, auth, value).status_code == 404


@pytest.mark.parametrize('prefix', ['securemessenger://public/', 't.me/', 'https://t.me/', 'http://t.me/'])
def test_public_and_legacy_username_links_resolve_local_chats(app, client, auth, group, prefix):
    with app.app_context():
        chat = db.session.get(Chat, group)
        chat.is_public = True
        chat.username = 'our_group'
        chat.chat_type = 'channel'
        db.session.commit()
    assert invite(client, auth, group) == 'securemessenger://public/our_group'
    assert post_link(client, auth, prefix + 'our_group').status_code == 200
    with app.app_context():
        assert ChatMember.query.filter_by(chat_id=group, user_id='bob').one().role == 'subscriber'
        db.session.get(Chat, group).is_public = False
        db.session.commit()
    assert post_link(client, auth, prefix + 'our_group', user='carol').status_code == 404


def test_tampered_deleted_and_unauthorized_invites_fail(app, client, auth, group):
    link = invite(client, auth, group)
    assert post_link(client, auth, link + 'tampered').status_code == 404
    assert client.get(f'/api/v1/chats/{group}/invite-link', headers=auth('bob')).status_code == 403
    assert client.post('/api/v1/chats/join', json={'invite_link': link}).status_code == 401
    with app.app_context():
        db.session.get(Chat, group).is_deleted = True
        db.session.commit()
    assert post_link(client, auth, link, 'invite-preview').status_code == 404
    assert post_link(client, auth, link).status_code == 404


@pytest.mark.parametrize('link', [None, 12, {}, '', 'not a link', 'securemessenger://join/missing',
                                  'https://evil.test/our_group', 'https://t.me.evil.test/our_group',
                                  'https://bob@t.me/our_group', 'https://t.me:443/our_group',
                                  't.me/our_group/extra', 't.me/our_group?next=bad',
                                  'securemessenger://public/our_group#fragment'])
def test_malformed_or_external_invites_are_not_followed(client, auth, link):
    assert post_link(client, auth, link).status_code == 404


@pytest.mark.parametrize('chat_type', ['group', 'channel'])
def test_public_rejoin_via_search_reuses_membership_without_admin_privileges(
        app, client, auth, group, chat_type):
    with app.app_context():
        chat = db.session.get(Chat, group)
        chat.chat_type = chat_type
        chat.is_public = True
        chat.username = 'search_public'
        db.session.add(ChatMember(chat_id=group, user_id='bob', role='admin'))
        db.session.commit()
    assert client.post(f'/api/v1/chats/{group}/leave', headers=auth('bob'), json={}).status_code == 200
    response = client.post(f'/api/v1/chats/{group}/add-member', headers=auth('bob'), json={'user_id': 'bob'})
    assert response.status_code == 201
    with app.app_context():
        members = ChatMember.query.filter_by(chat_id=group, user_id='bob').all()
        assert len(members) == 1
        assert not members[0].is_deleted
        assert members[0].role == ('subscriber' if chat_type == 'channel' else 'member')


def test_removed_public_member_needs_an_explicit_admin_readd(app, client, auth, group):
    with app.app_context():
        chat = db.session.get(Chat, group)
        chat.is_public = True
        chat.username = 'removed_public'
        db.session.commit()
    link = f'securemessenger://join/{group}'
    assert post_link(client, auth, link).status_code == 200
    assert client.post(f'/api/v1/chats/{group}/remove-member', headers=auth(), json={'user_id': 'bob'}).status_code == 200
    assert client.post(f'/api/v1/chats/{group}/add-member', headers=auth('bob'), json={'user_id': 'bob'}).status_code == 403
    assert client.post(f'/api/v1/chats/{group}/add-member', headers=auth(), json={'user_id': 'bob'}).status_code == 201
    assert post_link(client, auth, link).status_code == 200


def test_invites_reject_empty_query_and_fragment_delimiters(client, auth, group):
    for suffix in ('?', '#'):
        assert post_link(client, auth, f'securemessenger://join/{group}{suffix}').status_code == 404


def test_two_devices_joining_at_once_get_one_active_membership(app, client, auth, group):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier

    link = invite(client, auth, group)
    headers = auth('bob')
    ready = Barrier(2)

    def accept():
        with app.test_client() as thread_client:
            ready.wait(timeout=5)
            return thread_client.post('/api/v1/chats/join', json={'invite_link': link}, headers=headers).status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        assert list(pool.map(lambda _: accept(), range(2))) == [200, 200]
    with app.app_context():
        assert ChatMember.query.filter_by(chat_id=group, user_id='bob', is_deleted=False).count() == 1
