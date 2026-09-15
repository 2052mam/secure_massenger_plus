"""Short lived unlock tokens for the PIN protected archive.

The 4 digit PIN itself is never sent again after verification: the client gets
a signed, short lived token instead, so a stolen request log cannot reveal it.
Changing or removing the PIN invalidates every token issued before the change.
"""
from datetime import timedelta

from flask import request
from flask_jwt_extended import create_access_token, decode_token

from app.services.timestamps import utc_iso

ARCHIVE_CLAIM = 'archive_unlock'
ARCHIVE_PIN_STAMP = 'archive_pin_at'
ARCHIVE_TOKEN_HEADER = 'X-Archive-Token'
ARCHIVE_TOKEN_TTL = timedelta(minutes=30)


def _stamp(user):
    return utc_iso(user.archive_pin_updated_at) if user.archive_pin_updated_at else ''


def create_archive_token(user):
    return create_access_token(
        identity=user.id,
        additional_claims={ARCHIVE_CLAIM: True, ARCHIVE_PIN_STAMP: _stamp(user)},
        expires_delta=ARCHIVE_TOKEN_TTL,
    )


def archive_unlocked(user, token=None):
    """True when the archive may be listed for this request."""
    if user is None:
        return False
    if not user.has_archive_pin:
        return True
    raw = token if token is not None else request.headers.get(ARCHIVE_TOKEN_HEADER, '')
    if not raw:
        return False
    try:
        claims = decode_token(raw)
    except Exception:
        return False
    return (claims.get('sub') == user.id
            and claims.get(ARCHIVE_CLAIM) is True
            and claims.get(ARCHIVE_PIN_STAMP) == _stamp(user))
