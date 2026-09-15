# Groups, channels, join privacy, profile photos and timestamps

Implemented 2026-09-08. **Deploy the database upgrade and backend before the Flutter client.**

## Architecture retained

The application is a bilingual English/Persian Flutter/Riverpod client with a
Flask/JWT/SQLAlchemy backend intended for MySQL/cPanel. Conversations and media
synchronize through HTTP polling, not WebSockets. Existing multi-account session
isolation, mandatory 2FA, media playback, reply navigation, signed invitations,
soft deletion and audit records are retained. No Flutter/package version changes
are part of this patch.

The main defects were: permissions stored unreliably inside `description` and
never enforced; publishing unrestricted by channel membership; no usable member
addition UI after creation; no remove-photo action; and timezone-less UTC values
parsed as local time in chat-list/message models.

## 1. Add members after creation and respect join privacy

Open a group/channel and tap its header (or its information item in the menu).
Choose **Add members** / **Add subscribers**.

- The initial list contains peers from existing active private conversations.
  An authorized inviter can add them directly only when their privacy allows it.
- Search accepts usernames (including `@username`), display names and exact user
  IDs. Search selections **send an invitation link**, even if the result is also
  a chat-list contact. Search alone never silently subscribes someone.
- **Settings → below Ghost Mode → Allow people to join** controls whether other
  people can add *you* directly. It applies to both groups and channels and
  defaults to enabled for existing/new accounts. Disabled means invite-only,
  not “prevent me from voluntarily joining a link.”
- The server independently checks active private-chat membership, blocks,
  recipient privacy and the inviter's permissions. UI-supplied source/role is not
  sufficient authorization. Privacy is also checked during group creation with
  `member_ids`.
- Invitations are ordinary signed-link messages in a private conversation, with
  recipient delivery status and chat-list activity. Repeated identical invitations
  are deduplicated while the previous invitation is still visible to the recipient.
- Existing members return `already_member`. Voluntary rejoins reuse soft-deleted
  rows without restoring former admin rights. Only an administrator with removal
  rights can restore a removed member. An explicit invite can lift the removal
  ban without overriding join privacy; the recipient still confirms joining.
- Creation deduplicates member IDs (maximum 100) and rolls back on invalid targets.

API: `PUT /users/me {"allow_group_adds": false}`;
`POST /chats/<id>/add-member {"user_id": "...", "source": "chat_list" | "search"}`.
The result includes `action: added | invited | already_member`.
The privacy preference is returned only in the user's own profile, not public
profile/search payloads.

## 2. Group defaults and individual administrator rights

**Group information → Permissions** edits member defaults. The owner can also
select a member's menu → **Add administrator** / **Edit administrator rights**.

`Chat.permissions` and `ChatMember.permissions` are separate JSON columns.
`GET /chats/<id>/info` returns saved group `permissions` and the caller's effective
`capabilities`. Policy lives in `backend/app/services/chat_permissions.py` and is
checked by the mutation endpoints, including forwarding destinations.

| Right | Ordinary group members | Individual administrators |
| --- | --- | --- |
| Send messages (master switch) | Configurable | Configurable |
| Photos | Configurable | Configurable |
| View-once photos | Configurable | Configurable in groups |
| Videos, voice messages, files | Individually configurable | Individually configurable |
| Add/invite people | Configurable | Configurable |
| Delete own messages for everyone | Configurable | Covered by delete-message rights |
| Delete other people's messages | Never granted by group defaults | Configurable |
| Pin messages | Configurable; off by default | Configurable |
| Change information | No | Configurable |
| Remove members / manage group defaults | No | Configurable |
| Add administrators | No | Explicitly delegated; off by default |
| Clear shared history for everyone | **Never** | **Never**, including owner |

Default group send/add/delete-own rights are enabled. Existing administrators
with no stored permission object retain administrative defaults; promotion now
stores an explicit snapshot of the selected rights. Group defaults govern ordinary
members, not owners/admins. Owners retain control. Disabling the master send
switch disables all media; disabling photos also disables view-once photos.

Admins cannot change/remove the owner, modify their own role, edit/remove other
admins, or grant rights they do not possess. Only the owner edits existing admin
rights. Demotion normalizes the role to `member` or `subscriber`, clearing stored
admin rights. Invalid roles, unknown permissions, JSON arrays and non-boolean
permission/destructive flags are rejected.

The client hides/disables unavailable composer/actions, refreshes effective rights
through existing polling, and cancels active recording if voice permission is
revoked. The server remains authoritative if a stale or modified client sends a
request. Uploaded media types must match message types, so sending an image as
`text`, `file` or a forged `system` message does not bypass the photo rule.

**History distinction:** deleting one message for everyone is not clearing an
entire shared history. Local “clear for me” remains a per-user hide operation.
Only the owner has a separate, confirmed **Delete group/channel for everyone**
action. Individual incoming messages in private chats can be deleted for both
participants, following Telegram-style private-chat behavior.

Endpoints retained: `/set-permissions`, `/promote`, `/remove-member`, `/update`,
`/invite-link`, message `/delete`, `/forward`, `/pin`, history `/clear` and chat
`/delete`. Legacy `members_can_send` and `members_can_add_members` permission keys
are accepted as aliases. Descriptions are never overwritten to store rights.

## 3. Channels are broadcast feeds, not groups

- Separate group/channel management entry points, names, descriptions and actions
  replace the old mixed “group/channel” sheets. Shared rendering utilities avoid
  duplicate networking and permission code; channel behavior is not a group
  permission toggle.
- A dedicated channel-creation screen explains broadcasting and offers explicit
  private/public selection. Private is the UI default; public channels require
  a valid unique username.
- Subscribers (including old channel rows with `role=member`) are read-only.
  Only owners/admins with **Publish channel posts** and the relevant media right
  can send or forward into the channel.
- Subscribers cannot retrieve the subscriber list. Admins can manage subscribers
  and delegated rights; there is no misleading group-default-permissions screen
  for channels.
- Channel posts and reply-author previews use channel identity, not the personal
  publisher profile. The real sender remains stored server-side for audit and
  moderation. Legacy posts use channel identity too; no message-row rewrite.
- Subscriber composer is replaced by a broadcast explanation and a persisted,
  per-membership mute/unmute preference (`POST /chats/<id>/mute`). This is a saved
  setting; this patch does not introduce a push-notification service.
- Signed invite/public joining remains supported, including the legacy join
  endpoints and soft-deleted membership reuse.

**Reference/scope:** this is Telegram-style behavior for the requested membership,
permissions and broadcasting flows, not a claim of full Telegram feature parity.
Comments/discussion groups, view counters, scheduled/edited posts, ownership
transfer, per-invite revocation/expiry and approval queues are not added. The
project's existing “timed photo” UI is **view once**, not a configurable timer;
this patch controls that existing feature rather than adding timed/per-recipient
expiry. View-once photos are unavailable for new channel posts. Its existing
single-claim group behavior is unchanged. The requested configurable group
view-once/delete-own rights and prohibition on clearing shared history are product
choices, not claims about Telegram's exact permission matrix.

## 4. Remove profile photo without deleting the account

**Edit Profile → Remove profile photo → Confirm** sends `avatar_url: null` through
the existing authenticated profile endpoint, refreshes the session and renders
initials. Cancel leaves the photo unchanged. Loading/error states prevent false
success and repeated submission.

The own-profile payload returns the owner's actual photo even when hidden from
others, so hidden photos can also be removed. Public profiles still apply privacy
filtering. Profile upload/edit/removal uses account-owned API clients. The shared
avatar widget avoids sending bearer credentials to external avatar origins.

This removes the active profile reference; it does not hard-delete uploaded files
or audit history. Media may have other references, and the project uses soft
retention rather than destructive file deletion.

## 5. UTC timestamps and chat-list time

All chat/message/user API datetime output now has an explicit UTC `Z` suffix.
Database datetimes remain naive UTC, avoiding a destructive timestamp migration.
A shared Dart parser handles both older naive UTC strings and explicit offsets,
then converts to local time once. Account serialization writes last-seen timestamps
in UTC, avoiding timezone loss when saving/restoring accounts.

The chat list uses a compact clock for today's messages and a date for earlier
messages instead of an ambiguous relative “four hours ago.” Message bubbles,
view-once synchronization and profile presence use the same instant parsing.
Exact last-seen display and 60-second heartbeat expiry are preserved; future-dated
heartbeats do not leave someone incorrectly online. Pinned conversations sort
before unpinned conversations, then by latest visible message time.

## Required deployment (existing installations)

1. Back up the database and uploads; stop all backend workers during the upgrade.
2. Install this backend version with the existing requirements/environment.
3. Run from the repository root, with the production `DATABASE_URL` configured:

   ```bash
   # Use your existing backend virtual environment's python.
   # Running from backend also lets its existing .env load as before.
   cd backend
   python -m flask --app run:app upgrade-chat-schema
   ```

4. Start the updated backend workers; check `/health` and an authenticated
   `/users/me` and `/chats/<id>/info` request. Deploy the new Flutter build next.

The upgrade adds only `users.allow_group_adds` (boolean, default true),
`chats.permissions` and `chat_members.permissions` (nullable JSON). It is
idempotent, uses SQL supported by SQLite/MySQL, and does not drop tables or rewrite
accounts, memberships, messages or descriptions. **`db.create_all()` alone does
not upgrade existing tables.** Fresh databases created from the new models already
have the fields. No automatic production DDL runs at request/startup time.

Do not run old and new backend workers simultaneously during deployment. A backend
rollback can leave these additive columns in place, but the new client's group
composer expects capabilities from the new backend. Roll back client/backend
together if necessary. Keep the production `SECRET_KEY` stable for signed invites.

## Validation

Local results on 2026-09-08:

- **126 backend tests passed** using isolated temporary SQLite databases/uploads,
  including all original regressions. No configured production database was used.
- Added tests for creation and post-creation privacy, blocked/search-only invites,
  idempotent invitation delivery, each send/forward restriction, media type
  spoofing, owner/admin escalation protection, deletion boundaries, channel
  identity/read-only behavior, subscriber privacy, schema upgrades, profile
  removal, UTC payloads and pinned ordering.
- **80 Dart files syntax-parsed successfully**, with changed sources formatted
  using the WASM build of `dart_style` (`@wasm-fmt/dart_fmt`).
- Added Flutter tests for group/channel management, saving permissions, contact vs
  search invitations, failed-operation retries, channel creation, live composer
  restriction polling, profile removal/privacy, Persian RTL and UTC/offset parsing.
- **Flutter analyze/tests and Android builds were not run:** Flutter/Dart are not
  installed here, and the Google SDK download host failed TLS connections. Syntax
  parsing is not type analysis or a device test; no APK/device pass is claimed.
- MySQL migration/locking behavior needs staging verification on your deployment
  database. Native recording/playback and two-device behavior need device testing.

Reproduce backend validation:

```bash
python -m venv .venv
.venv/bin/python -m pip install -r backend/requirements.txt pytest
PYTHONPATH=backend .venv/bin/python -m pytest -q backend/tests
```

With the repository's required Flutter/Dart SDK available:

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
TZ=Asia/Tehran flutter test test/models/api_datetime_test.dart
TZ=America/New_York flutter test test/models/api_datetime_test.dart
flutter build apk --debug
```

Optional backend and Flutter CI templates are in `docs/ci/`. The current GitHub
App connection lacks workflow-management permission, so this patch does not install
an active workflow. A repository administrator can enable the templates separately.

### Two-device acceptance checklist

1. Create a group as A. From its header add chat-list peer B. Repeat with B's join
   switch off: B must receive a link without becoming a member until confirming.
   Search for B's ID/username and verify invite-only behavior even for a contact.
2. Toggle each group media right on A. On B, verify composer changes after polling
   and rejection of both direct sends and forwards. Revoke voice while recording.
3. Promote B with limited rights. Test removal, invite links, metadata, deleting
   own/other messages and attempts to grant stronger privileges. Shared-history
   clear must remain denied; local clear must affect only B.
4. Create public and private channels. B as subscriber must see a broadcast feed,
   channel author identity and no sending/member-list controls. Grant/revoke B's
   publish/media/delete rights and verify independent effects. Test mute/rejoin.
5. Remove A's profile photo, including while photo privacy is disabled. A and B
   should see initials after refresh, while the account and its messages remain.
6. Send messages with devices in different timezones. Compare list time, bubble
   time and exact last seen; test midnight and older messages in English/Persian.
7. Recheck 2FA, switching accounts, private/support/saved chats, signed invitations,
   reply navigation and native view-once/photo/video/voice playback.

## Follow-up: preserve permission changes on Back

The permission editor previously persisted only through its explicit **Save**
button; toolbar/system Back discarded the local toggle values. The editor now
saves pending changes before allowing Back navigation, for both group defaults
and individual administrator rights. It waits for the server response, blocks
duplicate submissions while saving, and keeps the editor and selected values
open with an error if saving fails. The existing Save button still works.
Unchanged/reverted settings leave without a write; merely opening and backing out
of the administrator promotion editor does not promote the member.

This is a **Flutter-client-only fix**. Rebuild/deploy the client; no additional
backend change or schema upgrade is required beyond the original release above.
It handles navigation away from the editor, not forced app/process termination.

Validation: all **126 backend tests still pass**, and all **80 Dart files parse**.
Eight additional widget regression cases cover toolbar/system Back and reopening,
a pending save with repeated exits, failure/retry, unchanged/reverted values,
explicit default-rights promotion, and group/channel administrator persistence.
The test API now stores permission changes rather than always returning defaults.
Flutter widget tests remain unexecuted in this workspace because the SDK is not
installed.

Manual check: disable **Send messages**, use Back **without tapping Save**, reopen
Permissions and confirm it remains disabled. Check that a normal member cannot
send messages. Repeat offline: Back should retain the editor and changes with an
error; reconnect and retry Save or Back, then reopen to verify persistence.
