"""In-app invitations; no external URL fetching and no new database tables."""

import re
from urllib.parse import urlsplit
from uuid import UUID

from flask import current_app
from itsdangerous import BadData, URLSafeSerializer

from app.models.chat import Chat


class InvalidInvite(ValueError):
    pass


def _signer():
    return URLSafeSerializer(current_app.config['SECRET_KEY'],
                             salt='secure-messenger-invite-v1')


def create_invite_link(chat):
    if chat.is_public and chat.username:
        # These are SecureMessenger usernames, NOT Telegram accounts.
        return f'securemessenger://public/{chat.username}'
    token = _signer().dumps({'chat_id': chat.id})
    return f'securemessenger://join/{token}'


def resolve_invite(link):
    if not isinstance(link, str) or not link or len(link) > 2048:
        raise InvalidInvite()
    link = link.strip()
    if any(char.isspace() for char in link) or '?' in link or '#' in link:
        raise InvalidInvite()
    if link.startswith('t.me/'):
        link = 'https://' + link
    try:
        uri = urlsplit(link)
        if uri.query or uri.fragment or uri.username or uri.password or uri.port:
            raise InvalidInvite()
        parts = uri.path.split('/')
        if len(parts) != 2 or not parts[1]:
            raise InvalidInvite()
        value = parts[1]
        if uri.scheme == 'securemessenger' and uri.netloc == 'join':
            if not re.fullmatch(r'[a-zA-Z0-9_.-]{1,1024}', value):
                raise InvalidInvite()
            try:
                payload = _signer().loads(value)
                if not isinstance(payload, dict) or not isinstance(payload.get('chat_id'), str):
                    raise InvalidInvite()
                chat_id = payload['chat_id']
            except BadData:
                # Backwards compatibility: earlier app versions shared a raw
                # UUID as a bearer invitation. Only canonical UUIDs and ONLY
                # groups/channels are accepted, never private/support/saved.
                try:
                    if str(UUID(value)) != value.lower():
                        raise InvalidInvite()
                    chat_id = value.lower()
                except (ValueError, AttributeError) as error:
                    raise InvalidInvite() from error
            query = Chat.query.filter_by(id=chat_id)
        elif ((uri.scheme == 'securemessenger' and uri.netloc == 'public') or
              (uri.scheme in ('http', 'https') and uri.netloc == 't.me')):
            if not re.fullmatch(r'[a-zA-Z0-9_]{3,30}', value):
                raise InvalidInvite()
            # Legacy t.me links resolve only public chats in this application.
            query = Chat.query.filter_by(username=value.lower(), is_public=True)
        else:
            raise InvalidInvite()
    except (ValueError, TypeError) as error:
        raise InvalidInvite() from error

    chat = query.filter(
        Chat.chat_type.in_(('group', 'channel')),
        Chat.is_deleted.is_(False),
        Chat.is_deleted_for_all.is_(False),
    ).first()
    if chat is None:
        raise InvalidInvite()
    return chat
