import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/api_constants.dart';
import 'notification_service.dart';

/// What a background poll cycle concluded.
enum PollOutcome {
  /// At least one new banner was shown.
  delivered,
  /// Poll succeeded, nothing new to show.
  noNew,
  /// Tokens are dead (signed out / device terminated elsewhere): the caller
  /// should stop polling instead of retrying forever.
  signedOut,
  /// Network/server failure: keep the schedule, the next tick retries.
  failed,
}

/// The single "check server, raise banners" routine shared by every
/// notification path (foreground chat poller uses unread-diff instead, while
/// the WorkManager task AND the foreground keep-alive service both call
/// [pollAndNotify]). SharedPreferences-backed dedupe + cursor keep all paths
/// from double-notifying.
///
/// Deliberately dependency-free (http + prefs + local notifications only) so
/// it runs identically in the UI isolate, the WorkManager isolate and the
/// foreground-service isolate — no FCM, no Play Services, nothing sanctionable.
class NotificationPoller {
  static Future<PollOutcome> pollAndNotify() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('notif_enabled') == false) return PollOutcome.noNew;
      var token = prefs.getString('access_token');
      final refreshToken = prefs.getString('refresh_token');
      if (token == null || token.isEmpty) return PollOutcome.signedOut;

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
            // Signed out / device terminated elsewhere: stay silent and let
            // the caller shut the schedule down.
            return PollOutcome.signedOut;
          }
        } catch (_) {
          return PollOutcome.failed;
        }
      }
      if (res.statusCode == 401) return PollOutcome.signedOut;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return PollOutcome.failed;
      }

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
      return fresh.isNotEmpty ? PollOutcome.delivered : PollOutcome.noNew;
    } catch (_) {
      // Never crash the caller: the next tick retries automatically.
      return PollOutcome.failed;
    }
  }
}
