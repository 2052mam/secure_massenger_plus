# FCM instant push — setup guide

The app already delivers notifications without any Google service (keep-alive
service + WorkManager polling `GET /notifications/pending`). Firebase Cloud
Messaging adds one thing on top: an **instant external wake-up** for the cases
where Android would never wake our own code (restricted battery bucket,
hibernation, aggressive OEM force-stop). This is the same trick Telegram uses.

**Privacy design:** the server sends DATA-ONLY ticks (`{kind, chat_id}`) —
never message content. Google infra only ever sees "something changed". Every
tick funnels into the same `/pending` poll the app already runs, so previews
are rendered locally and duplicate/collapsed ticks are harmless.

**Without these steps, nothing breaks:** the build compiles and the app runs
in polling-only mode. The settings screen shows پوش as inactive.

## 1. Firebase project (one time, ~5 minutes)

1. Go to https://console.firebase.google.com → Add project (any name, e.g.
   `secure-messenger`). No Analytics needed.
2. Project Overview → Add app → Android:
   - Package name: **`com.securemessenger.app`** (must match exactly).
   - App nickname: anything. SHA-1: optional, skip it.
3. Download **`google-services.json`** and put it at:
   - `android/app/google-services.json`
   - Never commit this file (it is in `.gitignore`).
4. In the console: Project settings → Cloud Messaging → note the **Project ID**
   (e.g. `secure-messenger-12345`). You need it for the server below.

## 2. Server credentials (one time)

1. Firebase console → Project settings → Service accounts → Generate new
   private key → downloads a `*-firebase-adminsdk-*.json` file.
2. Copy that file to the server, OUTSIDE the repo, e.g.
   `/etc/secure-messenger/fcm-key.json`, `chmod 600` it.
3. In the server's backend `.env` add:
   ```env
   FCM_PROJECT_ID=secure-messenger-12345
   FCM_SERVICE_ACCOUNT_FILE=/etc/secure-messenger/fcm-key.json
   ```
   (Alternative: `FCM_SERVICE_ACCOUNT_JSON='{...}'` with the whole JSON
   inlined — useful on hosts without file access.)
4. Install the two new backend deps and restart:
   ```bash
   pip install -r backend/requirements.txt   # adds google-auth + requests
   # then restart gunicorn / the app service
   ```
5. No database migration is needed (`push_token` columns already exist).

## 3. Rebuild the app

```bash
flutter pub get
flutter run   # or flutter build apk
```

The Gradle plugin applies automatically once `google-services.json` exists
(`android/app/build.gradle` — no manual step).

## 4. Verify end to end (~1 minute)

1. Log in on the phone (login syncs the FCM token to the server).
2. Settings → اتصال پس‌زمینه → **اعلان فوری (پوش)** should show green/active.
3. Tap **تست** → a "تست اعلان" banner must arrive within seconds.
4. Kill the app (swipe away) → send a message from a second account → the
   phone must buzz even in deep sleep.
5. If the test button says the server is not configured: re-check step 2
   (env vars + backend restart). `POST /api/v1/notifications/test` returns
   `404 push_not_configured` until the credentials load.

## Notes for Iran / sanctioned networks

- FCM needs Play Services on the phone and a reachable `fcm.googleapis.com`.
  On phones/VPNs where that fails, the keep-alive + WorkManager polling keeps
  delivering — keep it enabled, it is the fallback, not a competitor.
- The backend reaches `fcm.googleapis.com` directly; if the server host
  filters Google, ticks fail silently (logged server-side) and polling
  continues. No user-visible error either way.
- Tokens rotate on every logout and are wiped server-side on logout, device
  termination and session end. Dead tokens (`UNREGISTERED`) are purged
  automatically after the first failed tick.

## Troubleshooting

| Symptom | Cause → fix |
|---|---|
| پوش row grey/inactive in settings | `google-services.json` missing or wrong package name → step 1 |
| Test button: "server not configured" | env vars missing / backend not restarted → step 2 |
| Test works, real messages don't buzz | sender's app didn't tick, or recipient token stale → re-login on the recipient phone, check server log for `FCM tick failed` |
| Build error about `google-services` plugin | plugin version pinned in `android/settings.gradle` (4.4.2); run with `--stacktrace` and check the package name |
