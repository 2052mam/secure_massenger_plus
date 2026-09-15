import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_poller.dart';

/// Foreground-service entry point. Must stay a top-level function.
@pragma('vm:entry-point')
void foregroundTaskStartCallback() {
  FlutterForegroundTask.setTaskHandler(MessagePollTaskHandler());
}

/// The keep-alive task: polls the server every [ConnectionService.interval]
/// and raises local banners. Runs in the app's process as a foreground
/// service, so it survives swipe-away on Xiaomi/Huawei/Oppo/Vivo where
/// WorkManager jobs are force-stopped with the app.
class MessagePollTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Immediate check on (re)start, then the repeat timer takes over.
    await _tick();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_tick());
  }

  Future<void> _tick() async {
    try {
      final outcome = await NotificationPoller.pollAndNotify();
      if (outcome == PollOutcome.signedOut) {
        // Session died while we were away (logout/terminated on another
        // device): stop the service instead of polling pointlessly. The
        // next login starts it again.
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationPressed() {
    // Default behaviour (open the app) is handled by the plugin; tapping
    // a *message* banner deep-links into its chat (NotificationService).
  }
}

/// Telegram-style "background connection" (keep-alive service) WITHOUT any
/// push infrastructure: while running, new messages arrive within seconds
/// even with the app swiped away — the persistent notification is what buys
/// survival on aggressive OEMs (Xiaomi/Huawei/Oppo/Vivo), exactly like
/// Telegram's optional keep-alive and Signal's no-Play-Services mode.
///
/// Layers (all dedupe through the same seen-ids + cursor):
/// 1. App alive: 3s foreground unread-diff (instant).
/// 2. App swiped away: this keep-alive service (~20s).
/// 3. Service disabled by user: WorkManager every ~15 min (stock Android).
class ConnectionService {
  /// Poll cadence of the keep-alive service.
  static const interval = Duration(seconds: 20);

  static const _prefsKey = 'bg_connection_enabled';
  static const _serviceId = 727271;
  static const _channelId = 'secure_messenger_connection';
  static const _channelName = 'اتصال پس‌زمینه';

  static bool _initialized = false;

  /// Configures the service. Called once from main(), before runApp.
  static Future<void> init() async {
    if (_initialized || !Platform.isAndroid) return;
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: _channelId,
          channelName: _channelName,
          channelDescription:
              'اتصال دائمی برای دریافت پیام‌ها حتی وقتی برنامه بسته است',
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(
            interval.inMilliseconds,
          ),
          autoRunOnBoot: true,
          autoRunOnMyPackageReplaced: true,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
      _initialized = true;
    } catch (_) {}
  }

  /// Starts the keep-alive service when the user allows it (master
  /// notification switch AND background-connection switch, both on by
  /// default). Safe to call repeatedly; no-op while already running.
  static Future<void> startIfEnabled() async {
    if (!Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('notif_enabled') == false) return;
      if (prefs.getBool(_prefsKey) == false) return;
      if (await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.startService(
        // remoteMessaging = the Android messaging use-case: exempt from the
        // Android 15 dataSync 6h/day cap and allowed to start after boot.
        serviceTypes: [ForegroundServiceTypes.remoteMessaging],
        serviceId: _serviceId,
        notificationTitle: 'SecureMessenger',
        notificationText: 'متصل — پیام‌های جدید را دریافت می‌کنید',
        callback: foregroundTaskStartCallback,
      );
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  static Future<bool> get isRunning async {
    if (!Platform.isAndroid) return false;
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefsKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, enabled);
      if (enabled) {
        await startIfEnabled();
      } else {
        await stop();
      }
    } catch (_) {}
  }

  /// True when Android lets us use the network freely in Doze/sleep
  /// (user granted "ignore battery optimizations").
  static Future<bool> get isBatteryExempt async {
    if (!Platform.isAndroid) return true;
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system dialog that grants the battery exemption. Call only
  /// from a user tap with an on-screen explanation (system requirement).
  static Future<void> requestBatteryExemption() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (_) {}
  }
}
