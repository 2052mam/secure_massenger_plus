import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'notification_poller.dart';

/// WorkManager entry point. Must stay a top-level function and must not be
/// renamed without updating [BackgroundPollService.init].
@pragma('vm:entry-point')
void notificationCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == BackgroundPollService.taskName) {
      await BackgroundPollService.runOnce();
    }
    return Future.value(true);
  });
}

/// Killed-app notification fallback without FCM: a periodic WorkManager task
/// polls `GET /notifications/pending` and raises local banners.
///
/// This is the BACKUP path. The primary killed-app path is the foreground
/// keep-alive service ([ConnectionService]): on Xiaomi/Huawei/Oppo/Vivo,
/// swiping the app away force-stops it and cancels WorkManager jobs, while
/// a foreground service keeps running. WorkManager still helps when the user
/// disables the keep-alive service but leaves notifications on.
class BackgroundPollService {
  static const taskName = 'secure_messenger_poll';
  static const _taskId = 'secure_messenger_poll_periodic';

  static Future<void> init() async {
    try {
      await Workmanager().initialize(
        notificationCallbackDispatcher,
        isInDebugMode: kDebugMode,
      );
    } catch (_) {
      // Plugin missing on this platform (e.g. desktop): foreground
      // notifications keep working; background polling is skipped.
    }
  }

  /// (Re)registers the periodic poll. Called once after every login.
  static Future<void> start() async {
    try {
      await Workmanager().registerPeriodicTask(
        _taskId,
        taskName,
        frequency: const Duration(minutes: 15),
      );
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await Workmanager().cancelByUniqueName(_taskId);
    } catch (_) {}
  }

  /// One poll cycle, sharing logic + dedupe with the keep-alive service.
  static Future<void> runOnce() async {
    final outcome = await NotificationPoller.pollAndNotify();
    if (outcome == PollOutcome.signedOut) {
      // Session is dead: stop polling until the next login re-registers.
      await stop();
    }
  }
}
