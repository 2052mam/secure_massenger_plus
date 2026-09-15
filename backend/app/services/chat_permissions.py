"""Authoritative policies. Group defaults and delegated admin rights are separate.

Never trust a client role or hide security decisions only in Flutter widgets.
Owners retain control; no shared-history-clear permission can be delegated.
"""
from app.models.chat import ChatMember

SEND_KEYS = ('send_messages', 'send_photos', 'send_view_once_photos',
             'send_videos', 'send_voice', 'send_files')
GROUP_DEFAULTS = dict.fromkeys((*SEND_KEYS, 'invite_users', 'delete_own_messages'), True)
GROUP_DEFAULTS['pin_messages'] = False
ADMIN_DEFAULTS = dict.fromkeys((*SEND_KEYS, 'invite_users', 'delete_messages',
                              'pin_messages', 'change_info', 'restrict_members'), True)
ADMIN_DEFAULTS['post_messages'] = True
ADMIN_DEFAULTS['promote_members'] = False


def group_permissions(chat):
    return {**GROUP_DEFAULTS, **(chat.permissions or {})}


def admin_permissions(member):
    return {**ADMIN_DEFAULTS, **(member.permissions or {})}


def membership(chat, user_id):
    return ChatMember.query.filter_by(chat_id=chat.id, user_id=user_id,
                                      is_deleted=False).first()


def capabilities(chat, member):
    keys = set(GROUP_DEFAULTS) | set(ADMIN_DEFAULTS)
    result = dict.fromkeys(keys, False)
    if not member or chat.is_deleted or chat.is_deleted_for_all:
        return {**result, 'manage_permissions': False, 'clear_history_for_all': False}
    if chat.chat_type not in ('group', 'channel') or member.role == 'owner':
        result = dict.fromkeys(keys, True)
    elif member.role == 'admin':
        result.update(admin_permissions(member))
        result['delete_own_messages'] = result['delete_messages']
    elif chat.chat_type == 'group':
        result.update(group_permissions(chat))
    # A channel is a broadcast feed, not a group with different wording.
    if chat.chat_type == 'channel':
        for key in SEND_KEYS:
            result[key] = result[key] and result['post_messages']
        result['send_view_once_photos'] = False
    if not result['send_messages']:
        for key in SEND_KEYS:
            result[key] = False
    result['send_view_once_photos'] &= result['send_photos']
    result['manage_permissions'] = member.role == 'owner' or (
        chat.chat_type == 'group' and member.role == 'admin' and result['restrict_members'])
    # The owner has full control over their own group/channel and may wipe the
    # shared history on both sides. Delegated admins never inherit this right.
    result['clear_history_for_all'] = (chat.chat_type not in ('group', 'channel')
                                       or member.role == 'owner')
    return result


def can(chat, user_id, key):
    return capabilities(chat, membership(chat, user_id)).get(key, False)


def can_send(chat, user_id, message_type, view_once=False):
    mapping = {
        'text': 'send_messages',
        'image': 'send_photos',
        'video': 'send_videos',
        'voice': 'send_voice',
        'audio': 'send_voice',   # music/songs follow voice right (Telegram)
        'music': 'send_voice',
        'file': 'send_files',
        'sticker': 'send_messages',  # Telegram: stickers follow send_messages
        'gif': 'send_messages',      # GIFs follow send_messages/photos
        'video_note': 'send_videos',
        'round_video': 'send_videos',
        'location': 'send_messages',  # locations follow text right
        'live_location': 'send_messages',
    }
    key = mapping.get(message_type)
    # gif can be sent if either send_photos or send_messages is allowed (lenient like Telegram)
    rights = capabilities(chat, membership(chat, user_id))
    if message_type == 'gif':
        return bool(rights.get('send_messages') or rights.get('send_photos') or rights.get('send_files'))
    if message_type == 'sticker':
        return bool(rights.get('send_messages'))
    return bool(key and rights[key] and (not view_once or rights['send_view_once_photos']))


def can_delete(chat, user_id, message):
    member = membership(chat, user_id)
    if not member:
        return False
    if chat.chat_type in ('private', 'saved'):
        return True
    if chat.chat_type == 'support':
        return message.sender_id == user_id or member.role in ('owner', 'admin')
    rights = capabilities(chat, member)
    if chat.chat_type == 'channel':
        return rights['delete_messages']
    return rights['delete_messages'] or (
        message.sender_id == user_id and rights['delete_own_messages'])


def validate_permissions(value, defaults):
    if not isinstance(value, dict) or not value or any(
        key not in defaults or type(flag) is not bool for key, flag in value.items()
    ):
        raise ValueError('Invalid permissions: use known keys and boolean values')
    return value
