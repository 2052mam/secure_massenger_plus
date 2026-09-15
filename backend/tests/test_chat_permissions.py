"""Policy regressions exercise real endpoints, not just disabled UI controls."""
from datetime import datetime
import pytest
from sqlalchemy import inspect, text
from app import db
from app.models.chat import Chat, ChatMember
from app.models.message import Message, MessageStatus
from app.models.user import User, BlockList
from app.services.chat_permissions import ADMIN_DEFAULTS
from app.services.schema_upgrade import upgrade_schema


@pytest.fixture()
def group(app):
    with app.app_context():
        db.session.add(Chat(id='group', chat_type='group', title='Group', description='Keep this description', created_by='alice'))
        db.session.add_all([ChatMember(chat_id='group', user_id='alice', role='owner'),
                            ChatMember(chat_id='group', user_id='bob', role='member')])
        db.session.commit()
    return 'group'


def post(client, auth, path, body, user='alice'):
    return client.post('/api/v1/' + path, headers=auth(user), json=body)


def send(client, auth, kind='text', media=None, once=False, user='bob', chat='group'):
    return post(client, auth, 'messages/', {'chat_id': chat, 'message_type': kind,
                'content': 'Caption or text', 'media_id': media, 'is_view_once': once}, user)


def test_permissions_persist_without_overwriting_description(app, client, auth, group):
    assert post(client, auth, 'chats/group/set-permissions', {'send_photos': False}).status_code == 200
    info = client.get('/api/v1/chats/group/info', headers=auth('bob')).json
    assert info['permissions']['send_photos'] is False
    assert info['capabilities']['send_photos'] is False
    assert info['capabilities']['send_view_once_photos'] is False
    assert info['description'] == 'Keep this description'
    assert info['capabilities']['send_videos'] is True
    assert info['capabilities']['delete_messages'] is False


@pytest.mark.parametrize('patch', [{'send_photos': 'false'}, {'send_photos': 0},
                                    {'clear_history_for_all': True}, {'unknown': True}, []])
def test_invalid_permission_values_rejected(client, auth, group, patch):
    assert post(client, auth, 'chats/group/set-permissions', patch).status_code == 400


@pytest.mark.parametrize('kind,key,filename', [('text', 'send_messages', None),
    ('image', 'send_photos', 'photo.png'), ('image', 'send_view_once_photos', 'photo.png'),
    ('video', 'send_videos', 'clip.mp4'), ('voice', 'send_voice', 'voice.m4a'), ('file', 'send_files', 'file.pdf')])
def test_send_and_forward_obey_each_permission(app, client, auth, upload, group, kind, key, filename):
    media = upload('bob', filename=filename, data=None if kind == 'image' else b'test media')[0] if filename else None
    once = key == 'send_view_once_photos'
    assert post(client, auth, 'chats/group/set-permissions', {key: False}).status_code == 200
    assert send(client, auth, kind, media, once).status_code == 403
    # Every forward destination is checked as carefully as a new message.
    if not once:
        original = send(client, auth, kind, media, chat='chat').json['id']
        assert post(client, auth, f'messages/{original}/forward', {'target_chat_id': group}, 'bob').status_code == 403
    assert post(client, auth, 'chats/group/set-permissions', {key: True}).status_code == 200
    assert send(client, auth, kind, media, once).status_code == 201


def test_media_type_spoofing_cannot_bypass_photo_permission(client, auth, upload, group):
    media, _ = upload('bob')
    post(client, auth, 'chats/group/set-permissions', {'send_photos': False})
    for kind in ('file', 'voice', 'video', 'text', 'system', 'made-up'):
        assert send(client, auth, kind, media).status_code == 400


def test_master_send_switch_blocks_media_but_not_owner(client, auth, upload, group):
    post(client, auth, 'chats/group/set-permissions', {'members_can_send': False})
    media, _ = upload('bob')
    assert send(client, auth, 'image', media).status_code == 403
    assert send(client, auth, user='alice').status_code == 201


def test_group_delete_own_and_admin_moderation_are_distinct(client, auth, group):
    bob = send(client, auth).json['id']
    alice = send(client, auth, user='alice').json['id']
    post(client, auth, 'chats/group/set-permissions', {'delete_own_messages': False})
    for mid in (bob, alice):
        assert post(client, auth, f'messages/{mid}/delete', {'for_all': True}, 'bob').status_code == 403
    assert post(client, auth, f'messages/{bob}/delete', {'for_all': False}, 'bob').status_code == 200
    assert post(client, auth, 'chats/group/promote', {'user_id': 'bob', 'permissions': {'delete_messages': False}}).status_code == 200
    assert post(client, auth, f'messages/{alice}/delete', {'for_all': True}, 'bob').status_code == 403
    post(client, auth, 'chats/group/promote', {'user_id': 'bob', 'permissions': {'delete_messages': True}})
    assert post(client, auth, f'messages/{alice}/delete', {'for_all': True}, 'bob').status_code == 200


@pytest.mark.parametrize('kind', ['group', 'channel'])
@pytest.mark.parametrize('user', ['alice', 'bob'])
def test_shared_history_clear_is_owner_only(app, client, auth, group, kind, user):
    """The owner has full control and may wipe both sides; admins never inherit it."""
    with app.app_context():
        db.session.get(Chat, group).chat_type = kind
        ChatMember.query.filter_by(chat_id=group, user_id='bob').one().role = 'admin'
        db.session.commit()
    owner = user == 'alice'
    assert post(client, auth, 'messages/chat/group/clear', {'for_all': True}, user).status_code == (200 if owner else 403)
    assert post(client, auth, 'messages/chat/group/clear', {'for_all': False}, user).status_code == 200
    assert client.get('/api/v1/chats/group/info', headers=auth(user)).json[
        'capabilities']['clear_history_for_all'] is owner
    if user == 'bob':
        assert post(client, auth, 'chats/group/delete', {'for_all': True}, user).status_code == 403


def test_only_owner_can_delete_whole_group(client, auth, group):
    assert post(client, auth, 'chats/group/delete', {'for_all': True}, 'bob').status_code == 403
    assert post(client, auth, 'chats/group/delete', {'for_all': True}).status_code == 200
    assert send(client, auth, user='alice').status_code == 403


def test_owner_and_role_escalation_protection(client, auth, group):
    for role in ('owner', 'superadmin', ''):
        assert post(client, auth, 'chats/group/promote', {'user_id': 'bob', 'role': role}).status_code == 400
    assert post(client, auth, 'chats/group/promote', {'user_id': 'alice', 'role': 'member'}).status_code == 403
    assert post(client, auth, 'chats/group/remove-member', {'user_id': 'alice'}).status_code == 403
    assert post(client, auth, 'chats/group/promote', {'user_id': 'bob'}, 'bob').status_code == 403


def test_admin_rights_enforced_for_management(client, auth, group):
    post(client, auth, 'chats/group/promote', {'user_id': 'bob', 'permissions': {
        'change_info': False, 'invite_users': False, 'restrict_members': False,
        'pin_messages': False, 'promote_members': False}})
    for path, body in [('update', {'title': 'Hacked'}), ('add-member', {'user_id': 'carol'}),
                       ('remove-member', {'user_id': 'alice'}), ('promote', {'user_id': 'alice'}),
                       ('set-permissions', {'send_messages': False})]:
        assert post(client, auth, 'chats/group/' + path, body, 'bob').status_code == 403
    assert client.get('/api/v1/chats/group/invite-link', headers=auth('bob')).status_code == 403
    mid = send(client, auth).json['id']
    assert post(client, auth, f'messages/{mid}/pin', {}, 'bob').status_code == 403


def test_admin_cannot_delegate_rights_they_do_not_hold(app, client, auth, group):
    with app.app_context():
        db.session.add(ChatMember(chat_id=group, user_id='carol'))
        db.session.commit()
    post(client, auth, 'chats/group/promote', {'user_id': 'bob', 'permissions': {'promote_members': True, 'delete_messages': False}})
    assert post(client, auth, 'chats/group/promote', {'user_id': 'carol'}, 'bob').status_code == 403
    assert post(client, auth, 'chats/group/promote', {'user_id': 'carol', 'permissions': {'delete_messages': False}}, 'bob').status_code == 200
    assert post(client, auth, 'chats/group/promote', {'user_id': 'carol', 'permissions': {'send_messages': False}}, 'bob').status_code == 403
    assert post(client, auth, 'chats/group/remove-member', {'user_id': 'carol'}, 'bob').status_code == 403


def test_regular_member_invite_switch(client, auth, group):
    post(client, auth, 'chats/group/set-permissions', {'invite_users': False})
    assert post(client, auth, 'chats/group/add-member', {'user_id': 'carol'}, 'bob').status_code == 403
    assert client.get('/api/v1/chats/group/invite-link', headers=auth('bob')).status_code == 403
    post(client, auth, 'chats/group/set-permissions', {'invite_users': True})
    assert post(client, auth, 'chats/group/add-member', {'user_id': 'carol'}, 'bob').json['action'] == 'invited'


def test_channel_is_broadcast_and_subscriber_list_private(app, client, auth, group, upload):
    with app.app_context():
        db.session.get(Chat, group).chat_type = 'channel'
        db.session.commit()
    assert send(client, auth).status_code == 403  # legacy role=member also read-only
    mid = send(client, auth, user='alice').json['id']
    payload = client.get('/api/v1/messages/group', headers=auth('bob')).json['messages'][0]
    assert payload['sender_id'] == group
    assert payload['sender']['display_name'] == 'Group'
    assert 'alice' not in str(payload['sender'])
    assert client.get('/api/v1/chats/group/members', headers=auth('bob')).status_code == 403
    assert post(client, auth, f'messages/{mid}/forward', {'target_chat_id': group}, 'bob').status_code == 403
    assert post(client, auth, f'messages/{mid}/delete', {'for_all': True}, 'bob').status_code == 403
    assert post(client, auth, 'chats/group/set-permissions', {'send_messages': True}).status_code == 400
    media, _ = upload('alice')
    assert send(client, auth, 'image', media, once=True, user='alice').status_code == 403
    assert send(client, auth, 'image', media, user='alice').status_code == 201
    post(client, auth, 'chats/group/promote', {'user_id': 'bob', 'permissions': {'post_messages': False}})
    assert send(client, auth).status_code == 403
    post(client, auth, 'chats/group/promote', {'user_id': 'bob', 'permissions': {'post_messages': True}})
    assert send(client, auth).status_code == 201
    post(client, auth, 'chats/group/promote', {'user_id': 'bob', 'role': 'member'})
    with app.app_context():
        assert ChatMember.query.filter_by(chat_id=group, user_id='bob').one().role == 'subscriber'
    assert send(client, auth).status_code == 403


@pytest.mark.parametrize('allow,source,expected', [(True, 'chat_list', 'added'),
    (False, 'chat_list', 'invited'), (True, 'search', 'invited'), (False, 'search', 'invited')])
def test_direct_add_respects_privacy_and_search(app, client, auth, group, allow, source, expected):
    client.put('/api/v1/users/me', headers=auth('carol'), json={'allow_group_adds': allow})
    response = post(client, auth, 'chats/group/add-member', {'user_id': 'carol', 'source': source})
    assert response.status_code == 201
    assert response.json['action'] == expected
    with app.app_context():
        member = ChatMember.query.filter_by(chat_id=group, user_id='carol', is_deleted=False).first()
        assert (member is not None) == (expected == 'added')
        if expected == 'invited':
            msg = Message.query.filter(Message.content.like('securemessenger://%')).one()
            link = msg.content
            assert MessageStatus.query.filter_by(message_id=msg.id, user_id='carol').one()
    if expected == 'invited':
        post(client, auth, 'chats/group/add-member', {'user_id': 'carol', 'source': source})
        with app.app_context():
            assert Message.query.filter(Message.content.like('securemessenger://%')).count() == 1
        assert post(client, auth, 'chats/join', {'invite_link': link}, 'carol').status_code == 200


def test_stranger_receives_invite_not_direct_add(app, client, auth, group):
    # Bob has no private conversation with Carol.
    assert post(client, auth, 'chats/group/add-member', {'user_id': 'carol'}, 'bob').json['action'] == 'invited'
    with app.app_context():
        assert ChatMember.query.filter_by(chat_id=group, user_id='carol').first() is None


def test_blocking_prevents_both_adds_and_invites(app, client, auth, group):
    with app.app_context():
        db.session.add(BlockList(blocker_id='carol', blocked_id='alice'))
        db.session.commit()
    for source in ('chat_list', 'search'):
        assert post(client, auth, 'chats/group/add-member', {'user_id': 'carol', 'source': source}).status_code == 403
    with app.app_context():
        assert Message.query.count() == 0


def test_creation_uses_privacy_rules_and_deduplicates(app, client, auth):
    client.put('/api/v1/users/me', headers=auth('bob'), json={'allow_group_adds': False})
    result = post(client, auth, 'chats/group', {'title': 'New group', 'member_ids': ['bob', 'bob', 'carol', 'alice']})
    assert result.status_code == 201
    assert result.json['members'] == {'bob': 'invited', 'carol': 'added'}
    with app.app_context():
        assert ChatMember.query.filter_by(chat_id=result.json['chat_id']).count() == 2


def test_creation_invalid_member_rolls_back(app, client, auth):
    result = post(client, auth, 'chats/group', {'title': 'New group', 'member_ids': ['carol', 'missing']})
    assert result.status_code == 404
    with app.app_context():
        assert Chat.query.filter_by(chat_type='group').count() == 0


def test_privacy_private_serialization_and_photo_removal(app, client, auth):
    for invalid in ('false', 0, None):
        assert client.put('/api/v1/users/me', headers=auth(), json={'allow_group_adds': invalid}).status_code == 400
    with app.app_context():
        alice = db.session.get(User, 'alice')
        alice.avatar_url = '/api/v1/media/profile'
        alice.show_profile_photo = False
        db.session.commit()
    # Owner can remove the photo even when hidden from others.
    assert client.get('/api/v1/users/me', headers=auth()).json['avatar_url'] is not None
    for _ in range(2):
        result = client.put('/api/v1/users/me', headers=auth(), json={'avatar_url': None, 'allow_group_adds': False})
        assert result.json['avatar_url'] is None
        assert result.json['allow_group_adds'] is False
    peer = client.get('/api/v1/users/alice', headers=auth('bob')).json
    assert peer['avatar_url'] is None
    assert 'allow_group_adds' not in peer
    with app.app_context():
        assert db.session.get(User, 'alice').is_deleted is False


def test_all_chat_message_times_are_explicit_utc(client, auth, make_message):
    make_message(created_at=datetime(2026, 9, 8, 10, 15))
    listed = next(c for c in client.get('/api/v1/chats/', headers=auth()).json['chats'] if c['id'] == 'chat')
    msg = client.get('/api/v1/messages/chat', headers=auth()).json['messages'][0]
    assert listed['last_message']['created_at'] == msg['created_at'] == '2026-09-08T10:15:00Z'
    assert listed['updated_at'].endswith('Z')


def test_mute_is_per_member(client, auth, group):
    assert post(client, auth, 'chats/group/mute', {'is_muted': True}, 'bob').status_code == 200
    assert client.get('/api/v1/chats/group/info', headers=auth('bob')).json['is_muted'] is True
    assert client.get('/api/v1/chats/group/info', headers=auth()).json['is_muted'] is False
    assert post(client, auth, 'chats/group/mute', {'is_muted': 'false'}, 'bob').status_code == 400


def test_additive_schema_upgrade_preserves_old_rows_and_is_repeatable(app):
    with app.app_context():
        db.session.remove()
        # Simulate an installation before these columns/tables existed.
        with db.engine.begin() as conn:
            user_indexes = {item['name'] for item in inspect(conn).get_indexes('users')}
            for name in ('ix_users_mobile_number', 'ux_users_mobile_number'):
                if name in user_indexes:
                    conn.execute(text(f'DROP INDEX {name}'))
            conn.execute(text('ALTER TABLE users DROP COLUMN mobile_number'))
            conn.execute(text('ALTER TABLE users DROP COLUMN mobile_verified_at'))
            conn.execute(text('ALTER TABLE users DROP COLUMN allow_group_adds'))
            conn.execute(text('ALTER TABLE users DROP COLUMN archive_pin_hash'))
            conn.execute(text('ALTER TABLE chats DROP COLUMN permissions'))
            conn.execute(text('ALTER TABLE chat_members DROP COLUMN permissions'))
            conn.execute(text('ALTER TABLE chat_members DROP COLUMN is_archived'))
            conn.execute(text('ALTER TABLE chat_members DROP COLUMN pinned_at'))
            conn.execute(text('DROP TABLE chat_folder_items'))
            conn.execute(text('DROP TABLE chat_folders'))
            conn.execute(text('DROP TABLE user_photos'))
            conn.execute(text('DROP TABLE search_history'))
        upgrade_schema()
        result = app.test_cli_runner().invoke(args=['upgrade-chat-schema'])
        assert result.exit_code == 0, result.output
        assert 'up to date' in result.output
        assert db.session.get(User, 'alice').allow_group_adds is True
        assert db.session.get(User, 'alice').has_archive_pin is False
        assert Chat.query.count() == 2
        assert ChatMember.query.count() == 4
        assert ChatMember.query.filter_by(is_archived=False).count() == 4
        assert 'permissions' in {c['name'] for c in inspect(db.engine).get_columns('chats')}
        user_columns = {c['name'] for c in inspect(db.engine).get_columns('users')}
        assert {'mobile_number', 'mobile_verified_at'} <= user_columns
        assert inspect(db.engine).has_table('phone_verifications')
        for table in ('chat_folders', 'chat_folder_items', 'user_photos', 'search_history'):
            assert inspect(db.engine).has_table(table)


def test_public_channel_requires_username_and_private_creation_works(client, auth):
    assert post(client, auth, 'chats/channel', {'title': 'News', 'is_public': True}).status_code == 400
    private = post(client, auth, 'chats/channel', {'title': 'Private news', 'is_public': False})
    assert private.status_code == 201
    info = client.get(f"/api/v1/chats/{private.json['chat_id']}/info", headers=auth()).json
    assert info['is_public'] is False
    assert info['capabilities']['post_messages'] is True
    assert info['capabilities']['send_view_once_photos'] is False
    public = post(client, auth, 'chats/channel', {'title': 'News', 'is_public': True, 'username': 'news_public'})
    assert public.status_code == 201
    assert post(client, auth, 'chats/channel', {'title': 'Duplicate', 'username': 'news_public'}).status_code == 409


def test_private_received_message_can_be_deleted_for_both(client, auth, make_message):
    mid = make_message(sender_id='bob')
    assert post(client, auth, f'messages/{mid}/delete', {'for_all': True}).status_code == 200


def test_boolean_strings_cannot_trigger_destructive_actions(client, auth, group):
    for path in ('chats/group/delete', 'messages/chat/group/clear'):
        assert post(client, auth, path, {'for_all': 'false'}).status_code == 400
    assert post(client, auth, 'chats/group/promote', ['bob']).status_code == 400


def test_pins_follow_group_permission(client, auth, group):
    mid = send(client, auth).json['id']
    assert post(client, auth, f'messages/{mid}/pin', {}, 'bob').status_code == 403
    post(client, auth, 'chats/group/set-permissions', {'pin_messages': True})
    assert post(client, auth, f'messages/{mid}/pin', {}, 'bob').status_code == 200


def test_private_chat_cannot_be_used_as_a_group_management_target(client, auth):
    assert post(client, auth, 'chats/chat/add-member', {'user_id': 'carol'}).status_code == 400
    assert post(client, auth, 'chats/chat/promote', {'user_id': 'bob'}).status_code == 404
    assert post(client, auth, 'chats/chat/set-permissions', {'send_photos': False}).status_code == 400


def test_legacy_public_join_does_not_restore_admin_rights(app, client, auth, group):
    with app.app_context():
        chat = db.session.get(Chat, group)
        chat.chat_type = 'channel'
        chat.is_public = True
        member = ChatMember.query.filter_by(chat_id=group, user_id='bob').one()
        member.role = 'admin'
        member.permissions = dict(ADMIN_DEFAULTS)
        db.session.commit()
    post(client, auth, 'chats/group/leave', {}, 'bob')
    result = post(client, auth, 'chats/join/group', {}, 'bob')
    assert result.status_code == 201
    assert result.json['chat_id'] == group
    assert send(client, auth).status_code == 403
    with app.app_context():
        assert ChatMember.query.filter_by(chat_id=group, user_id='bob').one().permissions is None


def test_pinned_chats_sort_before_more_recent_unpinned_chats(client, auth, make_message):
    make_message(chat_id='chat', created_at=datetime(2026, 9, 7))
    make_message('newer', chat_id='other', created_at=datetime(2026, 9, 8))
    post(client, auth, 'chats/chat/pin', {})
    listed = client.get('/api/v1/chats/', headers=auth()).json['chats']
    assert [c['id'] for c in listed] == ['chat', 'other']
