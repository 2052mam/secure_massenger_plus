import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../core/constants/api_constants.dart';
import 'storage_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;
  ApiService._() : _useStoredToken = true;

  /// Account-owned requests never pick up another account's token mid-flight.
  /// A null token here means unauthenticated, not "fall back to storage".
  ApiService.withToken(String? token) : _token = token, _useStoredToken = false;

  /// Fired when the server rejects the current token because the device was
  /// terminated elsewhere (Item 4). The auth provider signs the user out.
  static void Function(String code)? onUnauthorized;

  final bool _useStoredToken;
  String? _token;

  void setToken(String? token) {
    _token = token;
  }

  Map<String, String> get _headers {
    final h = {'Accept': 'application/json'};
    final token =
        _token ?? (_useStoredToken ? StorageService.getToken() : null);
    if (token != null) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  Map<String, String> get _jsonHeaders {
    final h = _headers;
    h['Content-Type'] = 'application/json';
    return h;
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(
        statusCode: 0,
        message: 'اتصال به سرور برقرار نشد. اینترنت را بررسی کنید.',
        code: 'timeout',
      );
    } on SocketException {
      throw ApiException(
        statusCode: 0,
        message: 'اتصال به سرور برقرار نشد. اینترنت یا فیلترشکن را بررسی کنید.',
        code: 'network',
      );
    } on http.ClientException catch (e) {
      throw ApiException(
        statusCode: 0,
        message: 'خطای اتصال: ${e.message}',
        code: 'network',
      );
    }
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) =>
      _guard(() async {
        final res = await http
            .post(
              Uri.parse('${ApiConstants.baseUrl}$path'),
              headers: {..._jsonHeaders, ...?headers},
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 30));
        return _handle(res, path: path);
      });

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) =>
      _guard(() async {
        final uri = Uri.parse(
          '${ApiConstants.baseUrl}$path',
        ).replace(queryParameters: query);
        final res = await http
            .get(uri, headers: {..._headers, ...?headers})
            .timeout(const Duration(seconds: 30));
        return _handle(res, path: path);
      });

  /// Ephemeral media is kept in memory and never passed to an image disk cache.
  Future<Uint8List> getBytes(String path) => _guard(() async {
        final response = await http
            .get(
              Uri.parse('${ApiConstants.baseUrl}$path'),
              headers: {..._headers, 'Cache-Control': 'no-store'},
            )
            .timeout(const Duration(seconds: 45));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw _errorFor(response, fallback: 'بارگذاری عکس ناموفق بود');
        }
        return response.bodyBytes;
      });

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body,
  ) =>
      _guard(() async {
        final res = await http
            .put(
              Uri.parse('${ApiConstants.baseUrl}$path'),
              headers: _jsonHeaders,
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 30));
        return _handle(res, path: path);
      });

  Future<Map<String, dynamic>> uploadFile(
    String path,
    File file, {
    String fieldName = 'file',
    Map<String, String>? fields,
  }) =>
      _guard(() async {
        final uri = Uri.parse('${ApiConstants.baseUrl}$path');
        final request = http.MultipartRequest('POST', uri);
        request.headers.addAll(_headers);
        if (fields != null) request.fields.addAll(fields);

        final ext = file.path.split('.').last.toLowerCase();
        String mime = 'application/octet-stream';
        if (['jpg', 'jpeg'].contains(ext)) {
          mime = 'image/jpeg';
        } else if (ext == 'png') {
          mime = 'image/png';
        } else if (ext == 'gif') {
          mime = 'image/gif';
        } else if (ext == 'webp') {
          mime = 'image/webp';
        } else if (ext == 'mp4') {
          mime = 'video/mp4';
        } else if (ext == 'mp3') {
          mime = 'audio/mpeg';
        } else if (ext == 'm4a') {
          mime = 'audio/mp4';
        }

        request.files.add(
          await http.MultipartFile.fromPath(
            fieldName,
            file.path,
            contentType: MediaType.parse(mime),
          ),
        );

        final streamed = await request.send();
        final res = await http.Response.fromStream(streamed);
        return _handle(res, path: path);
      });

  Map<String, dynamic> _handle(http.Response res, {String? path}) {
    final body = _decodeBody(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    }
    throw _errorFor(res, body: body, path: path);
  }

  /// Never throws: HTML proxy errors, empty bodies and non-object JSON all
  /// become a plain map so the UI never shows a red `<!DOCTYPE ...>` crash.
  Map<String, dynamic> _decodeBody(http.Response res) {
    if (res.body.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{'data': decoded};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  ApiException _errorFor(
    http.Response res, {
    Map<String, dynamic>? body,
    String? path,
    String? fallback,
  }) {
    body ??= _decodeBody(res);
    final code = body['code'] as String?;
    var message = body['error'] as String?;
    message ??= fallback;
    if (message == null || message.isEmpty || _looksLikeHtml(message)) {
      message = _friendlyMessage(res.statusCode);
    }
    // A reverse proxy / Passenger crash returns HTML with no JSON body.
    if ((message.isEmpty || _looksLikeHtml(res.body)) &&
        _looksLikeHtml(res.body)) {
      message = _friendlyMessage(res.statusCode);
    }
    if (res.statusCode == 401 &&
        (code == 'device_terminated' || code == 'session_ended')) {
      // Fire async: throwing must not depend on the logout completing.
      final cb = onUnauthorized;
      if (cb != null) scheduleMicrotask(() => cb(code!));
    }
    return ApiException(
      statusCode: res.statusCode,
      message: message,
      code: code,
    );
  }

  bool _looksLikeHtml(String text) {
    final t = text.trimLeft().toLowerCase();
    return t.startsWith('<!doctype') ||
        t.startsWith('<html') ||
        t.startsWith('<head') ||
        t.startsWith('<body');
  }

  String _friendlyMessage(int status) {
    if (status == 0) return 'اتصال به سرور برقرار نشد.';
    if (status == 400) return 'درخواست نامعتبر است.';
    if (status == 401) return 'نشست شما منقضی شده است. لطفاً دوباره وارد شوید.';
    if (status == 403) return 'دسترسی ندارید.';
    if (status == 404) return 'یافت نشد.';
    if (status == 409) return 'این مورد قبلاً ثبت شده است.';
    if (status == 410) return 'این مورد دیگر در دسترس نیست.';
    if (status == 422) return 'نشست نامعتبر است. لطفاً دوباره وارد شوید.';
    if (status == 429) return 'تعداد درخواست‌ها زیاد است. کمی بعد تلاش کنید.';
    if (status >= 500) {
      return 'خطای موقت سرور. لطفاً چند لحظه بعد دوباره تلاش کنید.';
    }
    return 'خطای ناشناخته ($status)';
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? code;
  ApiException({
    required this.statusCode,
    required this.message,
    this.code,
  });

  /// True when the current device was signed out remotely.
  bool get isDeviceTerminated =>
      statusCode == 401 &&
      (code == 'device_terminated' || code == 'session_ended');

  @override
  String toString() => message;
}
