"""Regressions for archive, chat folders, multi pin, albums and search history.

Every test drives the real HTTP API, never the helper functions directly.
"""
import pytest

from app import db
from app.models.chat import Chat, ChatMember
from app.models.message import PinnedMessage
from app.models.profile import SearchHistory, UserPhoto
from app.models.user import User


def post(client, auth, path, body=None, user='alice', headers=None):
    request_headers = dict(auth(user))
    request_headers.update(headers or {})
    return client.post('/api/v1/' + path, headers=request_headers, json=body or {})


def get(client, auth, path, user='alice', headers=None):
    request_headers = dict(auth(user))
    request_headers.update(headers or {})
    return client.get('/api/v1/' + path, headers=request_headers)


def chat_ids(response):
    return [chat['id'] for chat in response.json['chats']]


@pytest.fixture()
def group(app):
    with app.app_context():
        db.session.add(Chat(id='group', chat_type='group', title='Group', created_by='alice'))
        db.session.add_all([ChatMember(chat_id='group', user_id='alice', role='owner'),
                            ChatMember(chat_id='group', user_id='bob', role='member')])
        db.session.commit()
    return 'group'


# ----- Archive -------------------------------------------------------------

def test_archived_chat_leaves_the_main_list_and_keeps_its_unread_badge(client, auth, make_message):
    make_message(sender_id='bob', content='Hello')
    assert 'chat' in chat_ids(get(client, auth, 'chats/'))

    assert post(client, auth, 'chats/chat/archive', {'is_archived': True}).status_code == 200
    main = get(client, auth, 'chats/')
    assert 'chat' not in chat_ids(main)
    assert main.json['archived'] == {'total': 1, 'unread': 1, 'chats_with_unread': 1}

    archived = get(client, auth, 'chats/?archived=1')
    assert chat_ids(archived) == ['chat']
    assert archived.json['chats'][0]['is_archived'] is True

    assert post(client, auth, 'chats/chat/archive', {'is_archived': False}).status_code == 200
    assert 'chat' in chat_ids(get(client, auth, 'chats/'))
    assert get(client, auth, 'chats/?archived=1').json['chats'] == []


def test_archiving_is_per_user_and_rejects_non_boolean(client, auth):
    assert post(client, auth, 'chats/chat/archive', {'is_archived': 'true'}).status_code == 400
    assert post(client, auth, 'chats/chat/archive', {'is_archived': True}).status_code == 200
    # Bob's copy of the same conversation stays exactly where it was.
    assert 'chat' in chat_ids(get(client, auth, 'chats/', user='bob'))
    assert post(client, auth, 'chats/other/archive', {}, user='bob').status_code == 403


def test_archive_pin_locks_the_archive_until_a_token_is_presented(client, auth):
    post(client, auth, 'chats/chat/archive', {'is_archived': True})
    assert post(client, auth, 'users/me/archive-pin', {'pin': '12a4'}).status_code == 400
    assert post(client, auth, 'users/me/archive-pin', {'pin': '12345'}).status_code == 400

    created = post(client, auth, 'users/me/archive-pin', {'pin': '1234'})
    assert created.status_code == 200
    assert created.json['has_archive_pin'] is True
    assert get(client, auth, 'users/me').json['has_archive_pin'] is True

    locked = get(client, auth, 'chats/?archived=1')
    assert locked.status_code == 423
    assert locked.json['archive_locked'] is True
    # The main list still works and reports that the archive is locked.
    assert get(client, auth, 'chats/').json['archive_locked'] is True

    assert post(client, auth, 'users/me/archive-pin/verify', {'pin': '9999'}).status_code == 403
    token = post(client, auth, 'users/me/archive-pin/verify', {'pin': '1234'}).json['archive_token']
    unlocked = get(client, auth, 'chats/?archived=1', headers={'X-Archive-Token': token})
    assert unlocked.status_code == 200
    assert chat_ids(unlocked) == ['chat']

    # Changing the PIN invalidates tokens handed out before the change.
    assert post(client, auth, 'users/me/archive-pin', {'pin': '5678'}).status_code == 403
    assert post(client, auth, 'users/me/archive-pin',
                {'pin': '5678', 'current_pin': '1234'}).status_code == 200
    assert get(client, auth, 'chats/?archived=1',
               headers={'X-Archive-Token': token}).status_code == 423

    assert post(client, auth, 'users/me/archive-pin/remove', {'pin': '1234'}).status_code == 403
    assert post(client, auth, 'users/me/archive-pin/remove', {'pin': '5678'}).status_code == 200
    assert get(client, auth, 'chats/?archived=1').status_code == 200


def test_archive_token_of_one_account_cannot_unlock_another(client, auth):
    post(client, auth, 'users/me/archive-pin', {'pin': '1111'})
    post(client, auth, 'users/me/archive-pin', {'pin': '2222'}, user='bob')
    token = post(client, auth, 'users/me/archive-pin/verify', {'pin': '1111'}).json['archive_token']
    assert get(client, auth, 'chats/?archived=1', user='bob',
               headers={'X-Archive-Token': token}).status_code == 423


# ----- Pinned chats --------------------------------------------------------

def test_pinned_chats_sort_first_with_the_newest_pin_on_top(client, auth):
    assert post(client, auth, 'chats/chat/pin').status_code == 200
    assert post(client, auth, 'chats/other/pin', {'is_pinned': True}).status_code == 200
    listed = get(client, auth, 'chats/').json['chats']
    assert [c['id'] for c in listed[:2]] == ['other', 'chat']
    assert listed[0]['pinned_at'] is not None

    assert post(client, auth, 'chats/other/pin', {'is_pinned': 'yes'}).status_code == 400
    assert post(client, auth, 'chats/other/unpin').json['is_pinned'] is False
    assert get(client, auth, 'chats/').json['chats'][0]['id'] == 'chat'

    # Archiving a pinned chat removes it from the pinned block of the main list.
    post(client, auth, 'chats/chat/archive', {'is_archived': True})
    post(client, auth, 'chats/chat/archive', {'is_archived': False})
    assert get(client, auth, 'chats/').json['chats'][0]['is_pinned'] is False


# ----- Chat folders --------------------------------------------------------

def test_folders_are_created_updated_and_soft_deleted(client, auth, group):
    created = post(client, auth, 'chats/folders', {
        'name': 'Work', 'include_groups': True, 'chat_ids': ['chat'],
    })
    assert created.status_code == 201
    folder = created.json['folder']
    assert folder['include_groups'] is True
    assert folder['include_private'] is False
    assert folder['chat_ids'] == ['chat']

    listed = get(client, auth, 'chats/folders').json['folders']
    assert [f['name'] for f in listed] == ['Work']

    updated = post(client, auth, f"chats/folders/{folder['id']}", {
        'name': 'Team', 'include_channels': True, 'chat_ids': ['group'],
    })
    assert updated.json['folder']['name'] == 'Team'
    assert updated.json['folder']['chat_ids'] == ['group']
    assert updated.json['folder']['include_groups'] is False

    assert post(client, auth, f"chats/folders/{folder['id']}/delete").status_code == 200
    assert get(client, auth, 'chats/folders').json['folders'] == []
    assert post(client, auth, f"chats/folders/{folder['id']}", {'name': 'Gone'}).status_code == 404


def test_folder_payloads_are_validated_and_scoped_to_my_own_chats(client, auth):
    assert post(client, auth, 'chats/folders', {'name': '  '}).status_code == 400
    assert post(client, auth, 'chats/folders', {'name': 'x' * 61}).status_code == 400
    assert post(client, auth, 'chats/folders',
                {'name': 'Bad', 'include_groups': 'yes'}).status_code == 400
    assert post(client, auth, 'chats/folders',
                {'name': 'Bad', 'chat_ids': [1]}).status_code == 400

    # A foreign chat id is silently ignored instead of leaking its existence.
    folder = post(client, auth, 'chats/folders', {
        'name': 'Mixed', 'chat_ids': ['chat', 'other']}, user='bob').json['folder']
    assert folder['chat_ids'] == ['chat']
    assert get(client, auth, 'chats/folders').json['folders'] == []


# ----- Pinned messages -----------------------------------------------------

def test_multiple_messages_stay_pinned_and_can_be_unpinned(client, auth, make_message):
    first = make_message('first', content='First')
    second = make_message('second', content='Second')

    assert post(client, auth, f'messages/{first}/pin').status_code == 200
    assert post(client, auth, f'messages/{second}/pin').json['pinned_count'] == 2
    # Pinning twice is idempotent, never a duplicate row.
    assert post(client, auth, f'messages/{second}/pin').json['pinned_count'] == 2

    pinned = get(client, auth, 'messages/chat/chat/pinned').json
    assert [m['id'] for m in pinned['messages']] == [second, first]
    assert pinned['can_pin'] is True
    assert get(client, auth, 'messages/chat').json['messages'][0]['is_pinned'] is True

    # Both sides of the chat see the same pins, and polling reconciles them.
    assert [m['id'] for m in get(client, auth, 'messages/chat/chat/pinned',
                                 user='bob').json['messages']] == [second, first]
    synced = post(client, auth, 'messages/statuses',
                  {'chat_id': 'chat', 'message_ids': [first, second]})
    assert synced.json['pinned_ids'] == sorted([first, second])

    assert post(client, auth, f'messages/{first}/unpin').json['pinned_count'] == 1
    assert [m['id'] for m in get(client, auth, 'messages/chat/chat/pinned').json['messages']] == [second]
    assert post(client, auth, 'messages/chat/chat/unpin-all').json['pinned_count'] == 0
    assert get(client, auth, 'messages/chat/chat/pinned').json['messages'] == []


def test_pinning_needs_permission_and_deleted_messages_leave_the_bar(app, client, auth, group):
    mid = post(client, auth, 'messages/', {'chat_id': 'group', 'content': 'Hi'}).json['id']
    assert post(client, auth, f'messages/{mid}/pin', user='bob').status_code == 403
    assert post(client, auth, f'messages/{mid}/unpin', user='bob').status_code == 403
    assert get(client, auth, 'messages/chat/group/pinned', user='bob').json['can_pin'] is False

    assert post(client, auth, f'messages/{mid}/pin').status_code == 200
    assert post(client, auth, f'messages/{mid}/delete', {'for_all': True}).status_code == 200
    assert get(client, auth, 'messages/chat/group/pinned').json['messages'] == []
    with app.app_context():
        assert PinnedMessage.query.filter_by(message_id=mid, is_deleted=False).count() == 0

    # An outsider can neither read nor change the pinned bar.
    assert get(client, auth, 'messages/chat/group/pinned', user='carol').status_code == 403
    assert post(client, auth, 'messages/chat/group/unpin-all', user='carol').status_code == 403


def test_owner_clear_history_for_all_also_clears_pins(app, client, auth, group):
    mid = post(client, auth, 'messages/', {'chat_id': 'group', 'content': 'Hi'}).json['id']
    post(client, auth, f'messages/{mid}/pin')
    assert post(client, auth, 'messages/chat/group/clear', {'for_all': True}).status_code == 200
    assert get(client, auth, 'messages/chat/group/pinned').json['messages'] == []
    assert get(client, auth, 'messages/group', user='bob').json['messages'] == []


# ----- Profile photo album -------------------------------------------------

def test_profile_album_supports_many_photos_with_a_main_one(app, client, auth):
    first = post(client, auth, 'users/me/photos', {'photo_url': '/api/v1/media/one'})
    assert first.status_code == 201
    second = post(client, auth, 'users/me/photos', {'photo_url': '/api/v1/media/two'})
    assert [p['photo_url'] for p in second.json['photos']] == ['/api/v1/media/two', '/api/v1/media/one']
    assert get(client, auth, 'users/me').json['avatar_url'] == '/api/v1/media/two'

    older = next(p for p in second.json['photos'] if p['photo_url'] == '/api/v1/media/one')
    promoted = post(client, auth, f"users/me/photos/{older['id']}/main")
    assert promoted.json['avatar_url'] == '/api/v1/media/one'
    assert sum(1 for p in promoted.json['photos'] if p['is_main']) == 1

    removed = post(client, auth, f"users/me/photos/{older['id']}/delete")
    assert removed.json['avatar_url'] == '/api/v1/media/two'
    assert len(removed.json['photos']) == 1
    with app.app_context():
        assert UserPhoto.query.filter_by(id=older['id']).one().is_deleted is True

    last = removed.json['photos'][0]
    assert post(client, auth, f"users/me/photos/{last['id']}/delete").json['avatar_url'] is None
    assert get(client, auth, 'users/me').json['avatar_url'] is None
    assert post(client, auth, 'users/me/photos', {'photo_url': ''}).status_code == 400


def test_album_is_visible_to_others_only_when_privacy_allows_it(app, client, auth):
    post(client, auth, 'users/me/photos', {'photo_url': '/api/v1/media/one'}, user='bob')
    assert len(get(client, auth, 'users/bob/photos').json['photos']) == 1
    client.put('/api/v1/users/me', headers=auth('bob'), json={'show_profile_photo': False})
    assert get(client, auth, 'users/bob/photos').json['photos'] == []
    # The owner always sees their own album.
    assert len(get(client, auth, 'users/bob/photos', user='bob').json['photos']) == 1

    # A legacy avatar without album rows is still returned once.
    with app.app_context():
        db.session.get(User, 'carol').avatar_url = '/api/v1/media/legacy'
        db.session.commit()
    assert get(client, auth, 'users/carol/photos').json['photos'][0]['photo_url'] == '/api/v1/media/legacy'


# ----- Bio -----------------------------------------------------------------

def test_bio_is_saved_even_when_the_username_is_unchanged(client, auth):
    saved = client.put('/api/v1/users/me', headers=auth(), json={
        'display_name': 'Alice', 'username': 'alice', 'bio': '  Hello world  '})
    assert saved.status_code == 200
    assert saved.json['bio'] == 'Hello world'
    assert get(client, auth, 'users/me').json['bio'] == 'Hello world'
    assert get(client, auth, 'users/alice', user='bob').json['bio'] == 'Hello world'

    cleared = client.put('/api/v1/users/me', headers=auth(), json={'bio': ''})
    assert cleared.json['bio'] is None
    assert client.put('/api/v1/users/me', headers=auth(),
                      json={'display_name': '   '}).status_code == 400
    assert client.put('/api/v1/users/me', headers=auth(),
                      json={'bio': 12}).status_code == 400


# ----- Search history ------------------------------------------------------

def test_search_history_records_and_deduplicates_recent_lookups(app, client, auth):
    assert post(client, auth, 'users/search-history', {}).status_code == 400
    assert post(client, auth, 'users/search-history', {'query': 'bob', 'user_id': 'bob'}).status_code == 201
    assert post(client, auth, 'users/search-history', {'query': 'bob', 'user_id': 'bob'}).status_code == 201
    assert post(client, auth, 'users/search-history', {'query': 'news'}).status_code == 201

    items = get(client, auth, 'users/search-history').json['items']
    assert len(items) == 2
    assert items[0]['query'] == 'news'
    person = next(item for item in items if item['user'])
    assert person['user']['username'] == 'bob'

    assert post(client, auth, f"users/search-history/{person['id']}/delete").status_code == 200
    assert [i['query'] for i in get(client, auth, 'users/search-history').json['items']] == ['news']
    assert post(client, auth, 'users/search-history/clear').status_code == 200
    assert get(client, auth, 'users/search-history').json['items'] == []
    # Nothing is hard deleted; the audit trail keeps every row.
    with app.app_context():
        assert SearchHistory.query.filter_by(user_id='alice').count() == 2
    # History is private to its owner.
    assert get(client, auth, 'users/search-history', user='bob').json['items'] == []


def test_search_history_is_capped_at_twenty_entries(client, auth):
    for index in range(25):
        post(client, auth, 'users/search-history', {'query': f'term-{index:02}'})
    items = get(client, auth, 'users/search-history').json['items']
    assert len(items) == 20
    assert items[0]['query'] == 'term-24'
