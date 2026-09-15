import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_model.dart';

/// Sanctions-proof notifications (Item 3). There is deliberately NO
/// Firebase/FCM anywhere in this app:
///
/// * App alive (foreground OR background): the existing 3-second chat-list
///   poller diffs unread counts and raises a local notification instantly,
///   like Telegram/Instagram.
/// * App killed: a WorkManager periodic task (see [BackgroundPollService])
///   polls `GET /notifications/pending` every ~15 minutes (Android minimum)
///   and shows the same notifications.
///
/// Tapping a notification deep-links into the chat.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  static const _channelId = 'secure_messenger_messages';
  static const _channelName = 'پیام‌های جدید';
  static const _channelDesc = 'اعلان پیام‌های جدید چت‌ها';
  static const _prefsEnabledKey = 'notif_enabled';
  static const _prefsSeenIdsKey = 'notif_seen_ids';
  static const _prefsCursorKey = 'notif_cursor';
  static const _maxSeenIds = 200;
  static const _maxPerCycle = 5;

  /// Chats currently open on screen — never notify for these. Managed by
  /// ChatScreen initState/dispose. (Per-isolate: empty in background.)
  final Set<String> suppressedChats = {};

  /// Set by the app shell: false while signed out (taps then are ignored).
  static bool appReady = false;

  /// Fired on notification tap. Payload format: `chatId|title|chatType`.
  static void Function(String chatId, String title, String chatType)?
      onNotificationTap;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: android, iOS: darwin);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onTap,
    );
    _initialized = true;
  }

  /// Android 13+ runtime permission + iOS permission. Called once after
  /// login and whenever notifications are re-enabled in settings.
  Future<bool> requestPermissions() async {
    var granted = true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final androidGranted = await android?.requestNotificationsPermission();
      if (androidGranted == false) granted = false;
    } catch (_) {}
    try {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final iosGranted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      if (iosGranted == false) granted = false;
    } catch (_) {}
    return granted;
  }

  void _onTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    openFromPayload(payload);
  }

  /// Handles a tap that launched the app from a killed state.
  Future<void> handleLaunchDetails() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      final payload = details?.notificationResponse?.payload;
      if (details?.didNotificationLaunchApp == true &&
          payload != null &&
          payload.isNotEmpty) {
        openFromPayload(payload);
      }
    } catch (_) {}
  }

  /// Deep-links `chatId|title|chatType` payloads into the chat screen.
  static void openFromPayload(String payload) {
    final parts = payload.split('|');
    if (parts.length < 3) return;
    if (!appReady) return;
    onNotificationTap?.call(parts[0], parts[1], parts[2]);
  }

  static int _stableId(String chatId) {
    var hash = 0;
    for (final unit in chatId.codeUnits) {
      hash = ((hash * 31) + unit) & 0x7fffffff;
    }
    return hash;
  }

  Future<void> showForChat({
    required String chatId,
    required String title,
    required String chatType,
    required String body,
    int count = 1,
  }) async {
    if (!await isEnabled()) return;
    if (suppressedChats.contains(chatId)) return;
    await init();
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      ticker: title,
      styleInformation: BigTextStyleInformation(body),
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );
    final displayTitle = count > 1 ? '$title ($count پیام جدید)' : title;
    try {
      await _plugin.show(
        _stableId(chatId),
        displayTitle,
        body,
        details,
        payload: '$chatId|$title|$chatType',
      );
    } catch (_) {}
  }

  Future<void> cancelForChat(String chatId) async {
    try {
      await _plugin.cancel(_stableId(chatId));
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefsEnabledKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsEnabledKey, enabled);
      if (!enabled) await cancelAll();
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Shared foreground/background bookkeeping (SharedPreferences is readable
  // from the WorkManager isolate, so both sides dedupe through it).
  // ------------------------------------------------------------------

  static Future<Set<String>> seenIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsSeenIdsKey);
      if (raw == null || raw.isEmpty) return <String>{};
      final list = (jsonDecode(raw) as List).whereType<String>();
      return list.toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> markSeen(Iterable<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = await seenIds()..addAll(ids);
      final trimmed = seen.length > _maxSeenIds
          ? seen.skip(seen.length - _maxSeenIds)
          : seen;
      await prefs.setString(_prefsSeenIdsKey, jsonEncode(trimmed.toList()));
    } catch (_) {}
  }

  static Future<String?> cursor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefsCursorKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveCursor(String cursor) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsCursorKey, cursor);
    } catch (_) {}
  }

  /// Called after every chat-list poll (every 3s while the app is alive).
  /// [previous] is null on the very first load: everything is baselined as
  /// seen so a fresh start never replays old history as notifications.
  Future<void> notifyForChatList({
    required List<ChatModel>? previous,
    required List<ChatModel> current,
    required String? currentUserId,
  }) async {
    if (!await isEnabled()) return;
    final prevUnread = <String, int>{
      for (final c in previous ?? const <ChatModel>[]) c.id: c.unreadCount,
    };
    if (previous == null) {
      // Baseline pass: silence, but remember every latest id.
      await markSeen([
        for (final c in current)
          if (c.lastMessage?.id != null) c.lastMessage!.id!,
      ]);
      return;
    }
    final seen = await seenIds();
    final candidates = <ChatModel>[];
    for (final chat in current) {
      if (chat.isMuted) continue;
      if (chat.unreadCount <= 0) {
        // Opened/read elsewhere: drop any stale banner for this chat.
        unawaited(cancelForChat(chat.id));
        continue;
      }
      final last = chat.lastMessage;
      if (last?.id == null || seen.contains(last!.id)) continue;
      if (currentUserId != null && last.senderId == currentUserId) {
        // Own messages never notify; still baselined below.
        continue;
      }
      if (suppressedChats.contains(chat.id)) continue;
      // Only genuinely new arrivals: unread grew, or the latest id changed.
      final grew = chat.unreadCount > (prevUnread[chat.id] ?? 0);
      String? prevLastId;
      for (final c in previous) {
        if (c.id == chat.id) {
          prevLastId = c.lastMessage?.id;
          break;
        }
      }
      if (!grew && prevLastId == last.id) continue;
      candidates.add(chat);
    }
    // Newest first so the per-cycle cap keeps the freshest banners.
    candidates.sort((a, b) {
      final ta = a.lastMessage?.createdAt;
      final tb = b.lastMessage?.createdAt;
      if (ta == null || tb == null) return 0;
      return tb.compareTo(ta);
    });
    // Baseline every latest id so the next poll (and the background task)
    // only react to real arrivals, not to the same rows.
    await markSeen([
      for (final c in current)
        if (c.lastMessage?.id != null) c.lastMessage!.id!,
    ]);
    for (final chat in candidates.take(_maxPerCycle)) {
      final last = chat.lastMessage!;
      await showForChat(
        chatId: chat.id,
        title: chat.displayTitle,
        chatType: chat.chatType,
        body: previewFor(
          messageType: last.messageType,
          content: last.content,
        ),
        count: chat.unreadCount,
      );
    }
  }

  /// User-facing one-line preview, mirroring the server's wording.
  static String previewFor({String? messageType, String? content}) {
    final text = content?.trim() ?? '';
    if (text.isNotEmpty && messageType != 'location') return _truncate(text);
    switch (messageType) {
      case 'image':
        return '📷 عکس';
      case 'video':
        return '🎬 ویدیو';
      case 'voice':
        return '🎤 پیام صوتی';
      case 'audio':
      case 'music':
        return text.isNotEmpty ? '🎵 $text' : '🎵 موسیقی';
      case 'file':
        return text.isNotEmpty ? '📎 $text' : '📎 فایل';
      case 'sticker':
        return 'استیکر';
      case 'gif':
        return 'GIF';
      case 'location':
        return '📍 موقعیت مکانی';
      case 'live_location':
        return '📍 موقعیت زنده';
      case 'video_note':
      case 'round_video':
        return '🎥 ویدیو مسیج';
      default:
        return text.isNotEmpty ? _truncate(text) : 'پیام جدید';
    }
  }

  static String _truncate(String text, [int max = 120]) {
    final single = text.replaceAll(RegExp(r'\s+'), ' ');
    if (single.length <= max) return single;
    return '${single.substring(0, max - 1)}…';
  }
}
