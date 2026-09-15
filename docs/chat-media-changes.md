# Chat and media improvements

## Project review and scope

Reviewed the Flutter entry points, Riverpod providers, models, API/storage/device/
recording services, every screen, Android configuration, Flask APIs/admin pages,
SQLAlchemy models, dependencies, README and existing test. The application is a
Persian/English Android messenger using authenticated HTTP polling against Flask
and MySQL, with private/group/channel/support/saved chats, mandatory TOTP login,
multi-account support and soft-delete/audit records.

The changes are isolated to chat message presentation, media playback, the message
payload/access endpoints and their tests. Authentication, account switching,
chat membership/management, themes, the three-second polling transport, production
SDK constraints and dependency lockfile are retained. **No database migration or
hard deletion is required.**

## 1. Reply context

- One shared backend serializer supplies complete messages on send, history,
  search and polling, including a bounded, non-recursive `reply_to` preview.
- Sent text, photo and voice replies immediately show the original author and
  text/caption or a meaningful media label. Normal photo quotes have thumbnails;
  view-once quotes never include a thumbnail or caption.
- The selected quote now sits directly above the composer. Swipe-to-reply and
  long-press reply remain available.
- Tapping a quote highlights the original. When it is outside the loaded/lazy
  window, `GET /messages/<chat_id>?from_id=<message_id>` loads a window starting
  at the original, with an explicit **Back to latest messages** action. Earlier
  history can also be loaded without inventing pixel offsets to an unbuilt item.
- Hidden/deleted/missing originals show **Message unavailable**. Cross-chat reply
  references are rejected rather than leaking content. Related records are batched
  to avoid one extra query per quote.
- Pagination filters hidden messages *before* applying its limit and incremental
  polling takes the first unseen page, preventing skipped messages in busy chats.

## 2. View-once photos (the existing “timed photo” option)

The previous tap handler only marked the message viewed; it never opened media.
The new route performs:

1. Acquire Android `FLAG_SECURE` for this route.
2. Fetch authenticated photo bytes into memory from
   `GET /messages/<id>/view-once/media` (`Cache-Control: private, no-store`).
3. Validate/decode a real image frame. Download/decoding failures offer Retry and
   do not mark the message as viewed.
4. Claim the opening using the existing `POST /messages/<id>/view-once` endpoint.
   Its conditional database UPDATE allows only one claim to succeed.
5. Reveal the photo full-screen. Closing or backgrounding covers the photo,
   disposes the decoded image and releases screen protection. The already-decoded
   frame is reused for display; it never enters a shared/disk image cache or needs
   a second decode after the successful claim.

The sender cannot consume their own photo. Non-members, departed members, hidden
messages and already-opened photos are rejected. The generic `/media/<id>` route
never serves an upload used in a view-once message, including soft-deleted ones.
Forwarding/reusing a view-once upload as normal media is blocked. Polling also
updates the sender's **Photo viewed** state after ordinary read receipts have
already arrived.

**Semantics retained:** this is view-once, not a newly invented seconds-based timer.
It stays visible while its viewing screen is open and cannot be reopened after
closing. The existing single `messages.viewed_at` field means one successful
opening **per message**, not per group member. In a group, the first recipient to
open consumes it. Per-recipient expiration or selectable countdown durations would
need an explicitly designed schema migration and are not silently added here.

The load-then-claim protocol is a client/server UX guarantee, not DRM or end-to-end
encryption. A modified authorized client or an external camera can retain content;
Android screenshot protection does not change that limitation. A network/process
failure after a successful server claim can still consume an opening that the
client could not display. The application avoids claiming before download/decode,
but it cannot make display and an HTTP transaction atomic.

## 3. Voice playback

- Dedicated player using the existing `just_audio` dependency.
- Scrubbable seek bar, buffered progress, elapsed/total time, ±10-second buttons,
  and selectable **1× / 1.5× / 2×** speed.
- Position updates do not fight an in-progress drag. Seeks are clamped and paused
  clips stay paused. Playback at EOF is explicitly paused and Replay seeks to zero.
- Loading/buffering/error/retry states, request authentication and cleanup are
  explicit. A per-chat coordinator prevents voice and video playing over each other.
- New AAC recordings use `.m4a` and `audio/mp4` instead of being identified as a
  video `.mp4`. Existing voice messages still play through the same audio engine.

## 4. Video playback

- Replaces the fixed 240×160 Chewie surface with dedicated controls around the
  existing `video_player` engine; no media dependency upgrade is required.
- Source aspect ratio is preserved (including portrait clips), with sufficient
  room for touch controls on narrow screens.
- Play/pause/replay, scrubbing, buffered progress, elapsed/total time, ±10 seconds,
  double-tap left/right seeking, speed choices from **0.5× to 2×**, mute and full screen.
- Controls auto-hide during playback, remain visible while paused/seeking, and
  expose retry/error states instead of a non-interactive broken-image icon.
- Full screen reuses the same controller, preserving position/speed/volume. It
  permits landscape and restores the app's portrait policy/system UI on exit.
- Native media endpoints explicitly retain authenticated HTTP byte-range support.

## 5. Full-screen photo zoom

- Regular photos now open in a black, full-screen route rather than an inset dialog.
- Pinch zoom (up to 6×), panning, animated focal-point double-tap zoom/reset, tap to
  toggle chrome, a close button and captions use the entire screen as their viewport.
- New photo uploads allow up to 4096px at quality 95 instead of 1600px/85, preserving
  more detail for zoom. Previously compressed photos cannot regain lost detail.

## Deployment

Deploy the backend and rebuild/install the Flutter client together. No SQL schema,
Gradle, package-version or server-address change is needed. View-once viewing uses
the new message-scoped media endpoint; old client builds do not implement that flow.
Keep uploads outside the public web root so a web server cannot bypass API checks.
HTTPS remains required for production credentials/media.

## Verification

Backend regression tests use a temporary SQLite database/uploads directory and
never touch a developer's MySQL instance:

```sh
python -m pip install -r backend/requirements.txt pytest
PYTHONPATH=backend python -m pytest -q backend/tests
```

Flutter regression tests use in-memory images, fake audio/video engines and mocked
platform channels (no live account or media server needed):

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```

The obsolete `MyApp` counter test is replaced with an actual logged-out app smoke
test. `docs/ci/chat-media-tests.yml` is a ready-to-install GitHub Actions template
for both suites using the project's Flutter 3.47.0 SDK line. Copy it to
`.github/workflows/chat-media-tests.yml` using a connection with **workflows**
permission to enable it. The current GitHub App can push code but rejected workflow
creation, so the template is deliberately not installed automatically.
Non-fatal style warnings in unrelated legacy code are not
turned into a repository-wide cleanup in this patch.

Local verification completed: **20 backend tests**, Python compilation, and Dart
syntax parsing. Changed Dart files were formatted using a WASM build of dart_style.
The sandbox has no Flutter/Android SDK and its network cannot download Flutter or
pub.dev packages. **Flutter analysis/tests have not been executed** in this
environment; the CI template documents how to run them on an SDK-enabled runner.
An Android device/emulator smoke test is still required for native codecs, audio
focus, screenshot/recents behavior and physical pinch/rotation gestures.

### Two-device acceptance checklist

- [ ] Send replies to text, images and voice; verify both participants see the same
      quote immediately and after reopening/searching. Tap an old quote and return
      to latest. Delete/hide an original and refresh: no private preview remains.
- [ ] Send a fresh view-once photo. Receiver sees the actual image; sender cannot
      consume it. Close/background and try again. Test an offline first opening,
      a failed load, rapid repeated taps and two clients trying to claim together.
- [ ] Play a long voice note; scrub while playing/paused, skip past each end, select
      1.5×/2× and replay after completion. Start another voice/video and verify only
      one plays. Try both a new `.m4a` and an existing `.mp4` voice note.
- [ ] Test portrait/landscape videos, short and long clips, double-tap seek, scrubbing,
      speed, mute, buffering, full screen, rotation and Back. Position/speed should
      survive the full-screen transition and audio should pause on backgrounding.
- [ ] Zoom and pan a high-resolution portrait and landscape photo all the way to
      screen edges; double-tap at different focal points, reset and close. Repeat
      in Persian RTL, English, dark mode and on a narrow phone.
