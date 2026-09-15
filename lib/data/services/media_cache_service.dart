import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../core/constants/api_constants.dart';
import '../../data/models/message_model.dart';
import 'storage_service.dart';

/// Internal persistent cache for received media (images, videos, files, audio).
/// Keeps a local copy irrespective of explicit download, so after the server
/// wipes the original (e.g. admin erases media or retention policy) the user
/// can still open / download / forward via the cached file (Telegram-like).
class MediaCacheService {
  static const _boxName = 'media_cache_v1';
  static Box<String>? _box;
  static Directory? _cacheDir;
  static bool _initDone = false;

  static Future<void> init() async {
    if (_initDone) return;
    try {
      _box = await Hive.openBox<String>(_boxName);
      final docs = await getApplicationDocumentsDirectory();
      _cacheDir = Directory('${docs.path}/.media_cache');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
      _initDone = true;
    } catch (e) {
      debugPrint('MediaCache init failed: $e');
    }
  }

  static String _keyForMessage(MessageModel m) => 'msg:${m.id}';
  static String _keyForUrl(String url) => 'url:$url';

  static String? _cachedPathForKey(String key) {
    try {
      return _box?.get(key);
    } catch (_) {
      return null;
    }
  }

  static File? getCachedFileForMessage(String messageId) {
    final p = _cachedPathForKey('msg:$messageId');
    if (p == null) return null;
    final f = File(p);
    return f.existsSync() ? f : null;
  }

  static File? getCachedFileForUrl(String mediaUrl) {
    final p = _cachedPathForKey(_keyForUrl(mediaUrl));
    if (p == null) return null;
    final f = File(p);
    return f.existsSync() ? f : null;
  }

  static bool isCachedMessage(String messageId) =>
      getCachedFileForMessage(messageId) != null;

  static bool isCachedUrl(String url) => getCachedFileForUrl(url) != null;

  static String _extFor(MessageModel m) {
    if (m.messageType == 'image') return 'jpg';
    if (m.messageType == 'video' || m.messageType == 'video_note') return 'mp4';
    if (m.messageType == 'voice') return 'm4a';
    if (m.messageType == 'audio' && (m.mediaUrl ?? '').contains('.')) {
      final seg = m.mediaUrl!.split('.').last.split('?').first;
      if (seg.length <= 5) return seg;
    }
    if (m.messageType == 'file' && m.originalName != null && m.originalName!.contains('.')) {
      return m.originalName!.split('.').last;
    }
    return 'bin';
  }

  static Future<File?> cacheMessageMedia(MessageModel m,
      {String? token}) async {
    if (_cacheDir == null || _box == null) await init();
    if (_cacheDir == null || _box == null) return null;
    // Do not cache view-once / ephemeral secrets locally beyond RAM.
    if (m.isViewOnce || m.isEncrypted) return null;
    // Also respect isSpoiler? spoiler can still be cached (user explicitly taps)
    final url = m.mediaUrl;
    if (url == null || url.isEmpty) return null;
    // Already cached for this message id?
    if (isCachedMessage(m.id)) return getCachedFileForMessage(m.id);
    // Already cached for same url (dedup)
    final existingByUrl = getCachedFileForUrl(url);
    if (existingByUrl != null) {
      try {
        await _box!.put(_keyForMessage(m), existingByUrl.path);
      } catch (_) {}
      return existingByUrl;
    }
    return _downloadToCache(
      mediaUrl: url,
      messageId: m.id,
      ext: _extFor(m),
      token: token,
    );
  }

  static Future<File?> _downloadToCache({
    required String mediaUrl,
    required String messageId,
    required String ext,
    String? token,
  }) async {
    try {
      final authToken = token ?? StorageService.getToken();
      final fullUrl = mediaUrl.startsWith('http')
          ? mediaUrl
          : '${ApiConstants.baseUrl}${mediaUrl.startsWith('/') ? '' : '/'}$mediaUrl';
      final uri = Uri.parse(fullUrl);
      final request = http.Request('GET', uri);
      if (authToken != null && authToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $authToken';
      }
      final response = await http.Client().send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // 404/410 after server wipe -> not an error, just no cache
        return null;
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
      }
      if (bytes.isEmpty) return null;
      final dir = _cacheDir!;
      final fileName = '${messageId}.$ext';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      final path = file.path;
      try {
        await _box!.put('msg:$messageId', path);
        await _box!.put(_keyForUrl(mediaUrl), path);
      } catch (_) {}
      return file;
    } catch (e) {
      debugPrint('MediaCache download failed for $messageId: $e');
      return null;
    }
  }

  /// Cache a list of messages in background without blocking UI.
  static void cacheMessagesInBackground(List<MessageModel> messages,
      {String? token}) {
    if (messages.isEmpty) return;
    // Fire-and-forget, throttled
    unawaited(Future(() async {
      await init();
      for (final m in messages) {
        if (m.mediaUrl == null || m.mediaUrl!.isEmpty) continue;
        if (m.isViewOnce || m.isEncrypted) continue;
        // Only cache image/video/file/audio/voice
        if (!{'image', 'video', 'video_note', 'file', 'audio', 'voice', 'gif', 'sticker'}.contains(m.messageType)) continue;
        // Avoid spamming cache on every poll: skip if already cached
        if (isCachedMessage(m.id)) continue;
        await cacheMessageMedia(m, token: token);
        // Small delay to avoid burst
        await Future.delayed(const Duration(milliseconds: 120));
      }
    }));
  }

  static Future<File?> getOrDownloadForForward(MessageModel m,
      {String? token}) async {
    final cached = getCachedFileForMessage(m.id) ?? (m.mediaUrl != null ? getCachedFileForUrl(m.mediaUrl!) : null);
    if (cached != null && await cached.exists()) return cached;
    // Try to (re-)download quietly; if server wiped, cached is the fallback
    if (m.mediaUrl == null) return null;
    return cacheMessageMedia(m, token: token);
  }

  static Future<void> clearCache() async {
    try {
      await _cacheDir?.delete(recursive: true);
      await _box?.clear();
      await _cacheDir?.create(recursive: true);
    } catch (_) {}
  }

  static int get cachedCount => _box?.length ?? 0;

  static Future<int> cacheSizeBytes() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;
    int total = 0;
    await for (final e in _cacheDir!.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }
}
