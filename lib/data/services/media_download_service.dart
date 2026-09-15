import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../core/constants/api_constants.dart';
import 'media_cache_service.dart';
import 'storage_service.dart';

class MediaDownloadService {
  static Future<String?> downloadMedia({
    required String mediaUrl,
    required String fileName,
    String? token,
    Function(int received, int total)? onProgress,
    String? messageId,
  }) async {
    try {
      // Item10: if server wiped, serve from internal cache
      if (messageId != null) {
        final cached = MediaCacheService.getCachedFileForMessage(messageId);
        if (cached != null) {
          Directory? dir;
          try {
            dir = await getDownloadsDirectory();
          } catch (_) {}
          dir ??= await getApplicationDocumentsDirectory();
          final dest = File('${dir.path}/$fileName');
          await cached.copy(dest.path);
          return dest.path;
        }
      } else {
        final cachedUrl = MediaCacheService.getCachedFileForUrl(mediaUrl);
        if (cachedUrl != null) {
          Directory? dir;
          try {
            dir = await getDownloadsDirectory();
          } catch (_) {}
          dir ??= await getApplicationDocumentsDirectory();
          final dest = File('${dir.path}/$fileName');
          await cachedUrl.copy(dest.path);
          return dest.path;
        }
      }
      final authToken = token ?? StorageService.getToken();
      final fullUrl = mediaUrl.startsWith('http')
          ? mediaUrl
          : '${ApiConstants.baseUrl}${mediaUrl.startsWith('/') ? '' : '/'}$mediaUrl';

      final uri = Uri.parse(fullUrl).replace(queryParameters: {'download': '1'});

      final request = http.Request('GET', uri);
      if (authToken != null && authToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $authToken';
      }

      final response = await http.Client().send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Fallback to internal cache on 404/410 after wipe
        final fb = messageId != null
            ? MediaCacheService.getCachedFileForMessage(messageId)
            : MediaCacheService.getCachedFileForUrl(mediaUrl);
        if (fb != null) {
          Directory? dir;
          try {
            dir = await getDownloadsDirectory();
          } catch (_) {}
          dir ??= await getApplicationDocumentsDirectory();
          final dest = File('${dir.path}/$fileName');
          await fb.copy(dest.path);
          return dest.path;
        }
        throw Exception('Download failed with status ${response.statusCode}');
      }

      final total = response.contentLength ?? 0;
      int received = 0;
      final List<int> bytes = [];

      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (onProgress != null && total > 0) {
          onProgress(received, total);
        }
      }

      final Uint8List fileBytes = Uint8List.fromList(bytes);

      if (kIsWeb) {
        // Web download behavior if running on web
        return fileName;
      } else {
        // Mobile / Desktop directory save
        Directory? dir;
        try {
          dir = await getDownloadsDirectory();
        } catch (_) {}
        dir ??= await getApplicationDocumentsDirectory();

        final filePath = '${dir.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
        return filePath;
      }
    } catch (e) {
      debugPrint('Error downloading file: $e');
      rethrow;
    }
  }

  static String formatBytes(int bytes, [int decimals = 1]) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (bytes.toString().length - 1) ~/ 3;
    if (i >= suffixes.length) i = suffixes.length - 1;
    double num = bytes / (1 << (i * 10));
    return '${num.toStringAsFixed(decimals)} ${suffixes[i]}';
  }
}
