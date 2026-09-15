import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/constants/api_constants.dart';
import 'notification_service.dart';

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

/// Killed-app notifications without FCM (Item 3): a periodic WorkManager
/// task polls `GET /notifications/pending` and raises the same local
/// notifications the foreground poller shows.
///
/// Honest limits (no push service can do better without FCM/APNs):
/// * Android runs this at most every 15 minutes, deferred further by Doze.
/// * OEM battery savers may delay it until the user exempts the app.
/// * While the app is alive (even backgrounded), the 3-second foreground
///   poller notifies instantly — this task is only the killed-app fallback.
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

  /// One poll cycle. Safe to call from the UI isolate too (used by tests
  /// and by a manual "check now" if ever added).
  static Future<void> runOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('notif_enabled') == false) return;
      var token = prefs.getString('access_token');
      final refreshToken = prefs.getString('refresh_token');
      if (token == null || token.isEmpty) return;

      final notifications = NotificationService();
      await notifications.init();

      Future<http.Response> fetch(String accessToken) {
        final since = prefs.getString('notif_cursor');
        final uri = Uri.parse(
          '${ApiConstants.baseUrl}/notifications/pending',
        ).replace(queryParameters: {
          if (since != null && since.isNotEmpty) 'since': since,
          'limit': '50',
        });
        return http
            .get(
              uri,
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer $accessToken',
              },
            )
            .timeout(const Duration(seconds: 25));
      }

      var res = await fetch(token);
      if (res.statusCode == 401 &&
          refreshToken != null &&
          refreshToken.isNotEmpty) {
        // Access token expired while the app was dead: refresh it inline.
        try {
          final refreshed = await http
              .post(
                Uri.parse('${ApiConstants.baseUrl}/auth/refresh'),
                headers: {
                  'Accept': 'application/json',
                  'Authorization': 'Bearer $refreshToken',
                },
              )
              .timeout(const Duration(seconds: 25));
          if (refreshed.statusCode >= 200 && refreshed.statusCode < 300) {
            final body =
                jsonDecode(refreshed.body) as Map<String, dynamic>;
            final next = body['access_token'] as String?;
            if (next != null && next.isNotEmpty) {
              token = next;
              await prefs.setString('access_token', next);
              res = await fetch(next);
            }
          } else {
            return; // Signed out / device terminated elsewhere: stay silent.
          }
        } catch (_) {
          return;
        }
      }
      if (res.statusCode < 200 || res.statusCode >= 300) return;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final messages =
          (body['messages'] as List? ?? []).whereType<Map<String, dynamic>>();
      final seen = await NotificationService.seenIds();
      final fresh = <String>[];
      for (final m in messages) {
        final id = m['id'] as String?;
        if (id == null || id.isEmpty || seen.contains(id)) continue;
        if (m['is_muted'] == true) continue;
        final chatId = m['chat_id'] as String? ?? '';
        if (chatId.isEmpty) continue;
        await notifications.showForChat(
          chatId: chatId,
          title: (m['chat_title'] as String?) ?? 'پیام جدید',
          chatType: (m['chat_type'] as String?) ?? 'private',
          body: (m['preview'] as String?)?.trim().isNotEmpty == true
              ? (m['preview'] as String)
              : NotificationService.previewFor(
                  messageType: m['message_type'] as String?,
                ),
        );
        fresh.add(id);
      }
      if (fresh.isNotEmpty) await NotificationService.markSeen(fresh);
      final serverTime = body['server_time'] as String?;
      if (serverTime != null && serverTime.isNotEmpty) {
        await NotificationService.saveCursor(serverTime);
      }
    } catch (_) {
      // Never crash the worker: the next window retries automatically.
    }
  }
}
