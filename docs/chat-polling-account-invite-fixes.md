# Chat polling, profiles, copy, accounts and invitations

## Scope

This patch addresses the five reported issues without introducing WebSockets,
changing Flutter/package constraints, or requiring a database migration. The
existing HTTP API, 3-second chat polling interval, soft-deletion/audit records,
mandatory 2FA, media controls and view-once protections are retained.

Deploy the updated backend before the updated client. Existing clients can still
use the old status-response fields, but live deletion and private-invite joining
require the new client and backend together.

## 1. Deletion while the other participant stays in the chat

`after_id` retrieves new messages; deleting an existing message does not create a
new message. Checking only unread outgoing ticks also misses received and already
read messages.

The client now reconciles **all loaded message IDs**, quoted originals outside
the current page, and the selected reply-composer original through:

```text
POST /api/v1/messages/statuses
{"chat_id": "...", "message_ids": ["...", "..."]}

{"statuses": {...}, "viewed_at": {...}, "deleted_ids": ["..."]}
```

- Requests are split into batches of at most 100 IDs, not truncated to 100.
- Reconciliation continues in search and old reply/history windows. Polls do not
  overlap, stop making requests while the app is backgrounded, and retry on
  subsequent cycles after network failures.
- Deletions remove bubbles of every type, clear an unavailable selected reply,
  redact quoted content, and refresh the chat list. Draft text is not cleared.
- Screen-lifetime tombstones prevent late history/send/poll responses from
  resurrecting deleted bubbles or their quoted content.
- Status/consumption updates do not regress on a stale response. Soft-deleted
  cursors remain usable; a local send no longer advances the polling cursor past
  remote messages the client has not received yet.
- Deletion pauses media. An open deleted photo closes its own route, and a
  deleted full-screen video closes before its shared controller is disposed.
- The backend checks membership before exposing even a deleted ID, omits
  unrelated/missing IDs, and uses bounded queries instead of per-message receipt
  queries. One-sided hides are visible only to that user's sessions.
- Last-message snippets and unread counts use the same visibility rules as
  message history, including one-sided hides.

Expected foreground behavior: removal on the next successful reconciliation
cycle (normally around 3 seconds, plus network/batch latency), without reopening
the chat or sending another message. Older messages not loaded yet are filtered
when their history page is requested.

## 2. Header photo and presence

`GET /api/v1/chats/<id>/info` returns privacy-filtered `other_user` data for
private/support chats. Identity is no longer guessed from the first received
message, so completely empty conversations work too.

The header includes an authenticated avatar with a safe initial fallback, the
peer's name, online/last-seen status below it, and profile navigation. Group and
channel headers retain their own title/avatar/member counts and group actions;
saved messages are not treated as another user.

Presence belongs to the signed-in shell rather than the chat-list tab: ordinary
HTTP heartbeats run every 15 seconds while foregrounded, with an offline update
on pause/disposal. The server expires online status after 60 seconds without a
heartbeat, including when a process is killed without sending an offline update.
Privacy switches remain authoritative. UTC timestamps, including older naive UTC
values, are displayed in local time. Avatar requests never send the account's
bearer token to a different origin.

## 3. Copy

Long-press a message and choose **Copy text** / **کپی متن**. The clipboard receives
the exact message body or media caption, without author, timestamp or quoted
original. Empty/captionless media has no copy action. View-once content has
neither a copy nor a forward action. Existing reply/delete actions remain, with
English/Persian feedback for the new actions.

## 4. Add-account/login routing and session isolation

The old add-account path replaced the navigator root with a standalone login
route. Authentication updated `home`, but that replacement route remained above
it; returning to the first route therefore returned to login.

The app now owns auth routing centrally. Its navigator identity changes when the
signed-in user changes, removing the old settings/login/register/2FA/chat stack.
Successful login or registration opens the new user's **Chats** tab without an
app restart. Same-user profile, theme, locale and token refreshes retain routes.

- Session saving, active-account bookkeeping, switching and logout are
  centralized in `AuthNotifier`.
- Add-account keeps saved accounts but clears the active session and user ID.
  Removing the active saved account also signs out that session.
- Saved credentials are validated/refreshed before replacing a working account;
  failed switching leaves the current account intact.
- Session generations reject stale validation responses. Account-owned API
  clients cannot silently pick up another account's credentials.
- Chat-list providers/pollers reset with the authenticated session; disposed
  notifiers ignore late responses. Same-user token renewal publishes new clients
  without clearing the navigator. Presence cleanup uses the original account's
  client rather than a newly active global token.
- Account-management and auth submissions guard repeated taps and disposed
  screens. The existing three-saved-account limit and mandatory 2FA remain.

## 5. Invitations shared inside messages

Text and captions recognize local invitation links without taking over reply or
media gestures. A nonmember sees a group/channel preview, confirms **Join**, and
then navigates into the canonical joined chat. Existing members open it directly.
Invalid/unavailable invites show an error without changing the current chat.
Repeated taps are guarded, joining is idempotent, and the chat list is refreshed.
The generated-link dialog also has a **Copy link** action.

New links are generated for owners/admins of groups/channels:

- Public username: `securemessenger://public/<username>`
- Private or username-less chat: `securemessenger://join/<signed-token>`

The server resolves them locally through `POST /api/v1/chats/invite-preview` and
`POST /api/v1/chats/join`, both accepting `{"invite_link": "..."}`. It never fetches
an arbitrary URL and never grants invite access to private one-to-one, support,
or saved-message chats. Preview alone does not grant message-history access.

Voluntary leavers reuse their soft-deleted membership row without recovering
former admin privileges. Removed members cannot use invitations to bypass their
removal; an administrator can explicitly re-add them. The existing public-search
join path also reuses soft-deleted rows instead of violating the unique-member
constraint.

### Compatibility and boundaries

- Previously shared canonical UUID `securemessenger://join/<uuid>` links remain
  usable for groups/channels. Legacy `t.me/<username>` and HTTP(S) variants resolve
  **local public chats**, not Telegram accounts. Newly generated links avoid that
  ambiguity.
- Legacy UUIDs are bearer capabilities, not revocable per-invite secrets. Knowing
  such a group ID remains sufficient to form a legacy link. Supporting those
  previously shared links is an intentional compatibility tradeoff.
- New signed tokens use the backend's stable `SECRET_KEY` with a dedicated salt.
  Keep a strong production key consistent across workers. Rotating it invalidates
  signed tokens, but does not revoke legacy UUID links. Per-invite expiry,
  revocation, approval queues and OS-level deep-link registration are not added.
- This change covers links tapped **inside this app's conversations**.

## Validation

Validation in this sandbox on **2026-09-07**:

- `PYTHONPATH=backend .venv/bin/python -m pytest -q backend/tests`:
  **82 passed**, including the original 20 media/API tests. Tests use isolated
  temporary SQLite databases/uploads, never the configured MySQL database.
- Dart sources were formatted with the WASM build of `dart_style`
  (`@wasm-fmt/dart_fmt`), and all `lib/` and `test/` Dart files passed a syntax
  parse. This is **not** a substitute for Dart analysis or Flutter execution.
- Added Flutter regressions for real auth-route transitions (login/registration
  plus 2FA and direct-token fallback), session isolation/token renewal, presence
  lifecycle, actual chat-screen polling/search/history, stale responses, batching,
  profile headers/privacy/RTL, clipboard actions, invite parsing/join navigation,
  and full-screen-video deletion.
- **Flutter analysis/tests and an Android build were not run here.** Flutter/Dart
  are not installed, and attempted SDK/pub download hosts failed TLS connections.
  No APK or device-test pass is claimed. Concurrent-join backend coverage was run
  on SQLite; deployment-database locking and native media behavior still need
  device/integration validation.

Commands for an SDK-enabled environment using this repository's existing SDK
constraints:

```bash
python -m venv .venv
.venv/bin/python -m pip install -r backend/requirements.txt pytest
PYTHONPATH=backend .venv/bin/python -m pytest -q backend/tests

flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --debug
```

### Two-device acceptance checklist

1. Keep A and B in the same conversation. Read messages of each type; delete for
   everyone on A. B should lose each bubble within a successful poll cycle while
   staying in the chat. Repeat while searching, viewing an old quote, composing a
   reply, and playing/viewing the deleted media. Try more than 100 loaded messages,
   loss/recovery of network, and one-sided deletion on another session of A.
2. Open a brand-new, empty private chat. Verify name/photo/profile navigation,
   presence changes, photo/last-seen privacy, foreground/background behavior and
   killed-app expiry. Check English/Persian and narrow screens.
3. Copy received and outgoing multiline/Unicode text and captions. Verify exact
   clipboard content and absence of copy/forward on view-once content.
4. From Settings -> Accounts -> Add account, complete login+2FA and separately
   registration+2FA. Verify Chats appears without restarting; Back must not reveal
   an old login/account route. Switch A/B, remove the active account, and test a
   stale saved token and a failed switch without cross-account chat data.
5. Create a private group, copy/share its invite in a private conversation, and
   tap it as a nonmember. Confirm preview -> Join -> group history. Repeat as an
   existing member, voluntary leaver and removed member; try legacy, public,
   malformed and tampered links and repeated taps.
