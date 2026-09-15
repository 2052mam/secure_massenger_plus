import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'api_service.dart';
import 'notification_poller.dart';
import 'notification_service.dart';

/// FCM background entry point. Must stay a top-level function. Runs in a
/// background isolate when a tick arrives while the app is backgrounded or
/// killed — including when Android would never wake our own code (restricted
/// bucket / hibernation), because the wake-up comes from Play Services.
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  await PushService.handleTick(message.data);
}

/// Firebase Cloud Messaging layer: instant external wake-up TICKS.
///
/// Architecture (privacy-first, Telegram-style reliability):
/// * The server sends DATA-ONLY ticks (`{kind, chat_id}`) — never message
///   content — so Google infra only ever sees "something changed".
/// * Every tick funnels into [NotificationPoller.pollAndNotify], the same
///   routine the keep-alive service and WorkManager use: `/pending` is the
///   single source of truth, so collapsed/duplicate ticks are harmless and
///   per-chat notification ids make every race invisible.
/// * Display, tap-to-open, suppression and dedupe all stay in
///   [NotificationService], shared with the polling paths.
///
/// Fully optional at runtime: without `google-services.json` (or without
/// Play Services on the device) every method below degrades to a silent
/// no-op and the app runs on local polling exactly as before.
class PushService {
  static bool _supported = false;
  static bool _listenersAttached = false;

  /// True once Firebase initialized successfully on this device.
  static bool get isSupported => _supported;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // No google-services.json / no Play Services: polling-only mode.
      _supported = false;
      return;
    }
    _supported = true;
    try {
      FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
    } catch (_) {}
    if (_listenersAttached) return;
    _listenersAttached = true;
    try {
      FirebaseMessaging.onMessage.listen(
        (message) => unawaited(handleTick(message.data)),
      );
    } catch (_) {}
    try {
      FirebaseMessaging.onMessageOpenedApp.listen(_openFromData);
    } catch (_) {}
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _openFromData(initial);
    } catch (_) {}
    try {
      FirebaseMessaging.instance.onTokenRefresh.listen(
        (_) => unawaited(syncToken()),
      );
    } catch (_) {}
  }

  /// Handles one FCM tick (foreground stream or background isolate).
  /// Takes the raw [RemoteMessage.data] map (`Map<String, dynamic>`).
  static Future<void> handleTick(Map<String, dynamic> data) async {
    if ('${data['kind']}' == 'test') {
      await NotificationService().showTest();
      return;
    }
    await NotificationPoller.pollAndNotify();
  }

  /// Defensive deep-link for taps on FCM-rendered notifications. Our server
  /// sends data-only ticks (the OS renders nothing), so normally taps arrive
  /// through NotificationService banners instead.
  static void _openFromData(RemoteMessage message) {
    final chatId = message.data['chat_id'] ?? '';
    if (chatId.isEmpty) return;
    NotificationService.openFromPayload(
      '$chatId|${message.data['chat_title'] ?? 'چت'}|${message.data['chat_type'] ?? 'private'}',
    );
  }

  static Future<String?> currentToken() async {
    if (!_supported) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  /// Sends the current FCM token to the backend (called on every login and
  /// on token rotation). No-op in polling-only mode.
  static Future<void> syncToken() async {
    final token = await currentToken();
    if (token == null || token.isEmpty) return;
    try {
      await ApiService().post('/notifications/register', {
        'push_token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'notifications_enabled': await NotificationService().isEnabled(),
      });
    } catch (_) {}
  }

  /// Stops pushes to this device: clears the server-side token (while still
  /// authenticated) and rotates the local FCM token.
  static Future<void> unregisterToken() async {
    try {
      await ApiService().post('/notifications/register', {'push_token': null});
    } catch (_) {}
    if (!_supported) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
