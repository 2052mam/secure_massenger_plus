"""Idempotent, additive upgrade for pre-migration installations (SQLite/MySQL).

Run with workers stopped and a database backup. Never drops or rewrites rows.
"""
from sqlalchemy import inspect, text
from app import db


def upgrade_schema():
    additions = {
        'users': {
            # Phone-primary authentication (E.164); existing accounts keep a
            # NULL value and may use the legacy email/password route.
            'mobile_number': 'VARCHAR(16) NULL',
            'mobile_verified_at': 'DATETIME NULL',
            'allow_group_adds': 'BOOLEAN NOT NULL DEFAULT 1',
            'archive_pin_hash': 'VARCHAR(255) NULL',
            'archive_pin_updated_at': 'DATETIME NULL',
            'is_limited': 'BOOLEAN NOT NULL DEFAULT 0',
            'limited_until': 'DATETIME NULL',
            'limited_reason': 'TEXT NULL',
            'limited_by': 'VARCHAR(36) NULL',
            'allow_forwarding': 'BOOLEAN NOT NULL DEFAULT 1',
            'terms_version': 'INTEGER NOT NULL DEFAULT 0',
            'terms_accepted_at': 'DATETIME NULL',
        },
        'chats': {
            'permissions': 'JSON NULL',
            'slow_mode_delay': 'INTEGER NOT NULL DEFAULT 0',
            'hide_members': 'BOOLEAN NOT NULL DEFAULT 0',
            'is_suspended': 'BOOLEAN NOT NULL DEFAULT 0',
            'suspension_reason': 'TEXT NULL',
            'suspended_at': 'DATETIME NULL',
            'suspended_by': 'VARCHAR(36) NULL',
            'is_closed': 'BOOLEAN NOT NULL DEFAULT 0',
            'closed_reason': 'TEXT NULL',
            'closed_at': 'DATETIME NULL',
            'allow_forwarding': 'BOOLEAN NOT NULL DEFAULT 1',
            'is_sponsored': 'BOOLEAN NOT NULL DEFAULT 0',
            'sponsored_at': 'DATETIME NULL',
            'sponsored_by': 'VARCHAR(36) NULL',
        },
        'chat_members': {
            'permissions': 'JSON NULL',
            'is_archived': 'BOOLEAN NOT NULL DEFAULT 0',
            'archived_at': 'DATETIME NULL',
            'pinned_at': 'DATETIME NULL',
        },
        'messages': {
            'is_spoiler': 'BOOLEAN NOT NULL DEFAULT 0',
            'is_scheduled': 'BOOLEAN NOT NULL DEFAULT 0',
            'scheduled_at': 'DATETIME NULL',
            'is_encrypted': 'BOOLEAN NOT NULL DEFAULT 0',
            'encryption_hint': 'VARCHAR(200) NULL',
            'is_secure': 'BOOLEAN NOT NULL DEFAULT 0',
            'latitude': 'FLOAT NULL',
            'longitude': 'FLOAT NULL',
            'location_title': 'VARCHAR(200) NULL',
            'live_until': 'DATETIME NULL',
            'audio_title': 'VARCHAR(200) NULL',
            'audio_artist': 'VARCHAR(200) NULL',
            'audio_duration': 'FLOAT NULL',
        },
        'media_files': {
            'title': 'VARCHAR(200) NULL',
            'artist': 'VARCHAR(200) NULL',
        },
    }
    with db.engine.begin() as connection:
        for table, columns in additions.items():
            inspector = inspect(connection)
            if not inspector.has_table(table):
                continue
            existing = {column['name'] for column in inspector.get_columns(table)}
            for column, definition in columns.items():
                if column not in existing:
                    connection.execute(text(f'ALTER TABLE {table} ADD COLUMN {column} {definition}'))

    # ``ALTER TABLE`` does not add the model's unique index on existing
    # databases. Create it explicitly after the nullable column is present;
    # NULL values remain valid for pre-phone-auth accounts.
    with db.engine.begin() as connection:
        inspector = inspect(connection)
        if inspector.has_table('users'):
            index_names = {item['name'] for item in inspector.get_indexes('users')}
            unique_names = {item['name'] for item in inspector.get_unique_constraints('users')}
            if 'ux_users_mobile_number' not in index_names | unique_names:
                connection.execute(text(
                    'CREATE UNIQUE INDEX ux_users_mobile_number ON users (mobile_number)'
                ))

    # New, self contained tables (folders, profile albums, search history, reports, stickers, gifs).
    # create_all only creates what is missing and never rewrites existing rows.
    from app.models.folder import ChatFolder, ChatFolderItem  # noqa: F401
    from app.models.profile import SearchHistory, UserPhoto  # noqa: F401
    from app.models.report import Report  # noqa: F401
    from app.models.sticker import StickerPack, Sticker  # noqa: F401
    from app.models.gif import SavedGif  # noqa: F401
    from app.models.message import MessageReaction  # ensure exists
    from app.models.story import Story, StoryView  # noqa: F401
    from app.models.user import PhoneVerification  # noqa: F401

    db.metadata.create_all(bind=db.engine)
    # Also ensure specific tables exist individually for older SQLAlchemy metadata
    db.metadata.create_all(bind=db.engine, tables=[
        ChatFolder.__table__, ChatFolderItem.__table__,
        UserPhoto.__table__, SearchHistory.__table__,
        Report.__table__, StickerPack.__table__, Sticker.__table__, SavedGif.__table__,
        MessageReaction.__table__,
        Story.__table__, StoryView.__table__, PhoneVerification.__table__,
    ])
