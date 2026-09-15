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

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    final res = await http
        .post(
          Uri.parse('${ApiConstants.baseUrl}$path'),
          headers: {..._jsonHeaders, ...?headers},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    return _handle(res);
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse(
      '${ApiConstants.baseUrl}$path',
    ).replace(queryParameters: query);
    final res = await http
        .get(uri, headers: {..._headers, ...?headers})
        .timeout(const Duration(seconds: 30));
    return _handle(res);
  }

  /// Ephemeral media is kept in memory and never passed to an image disk cache.
  Future<Uint8List> getBytes(String path) async {
    final response = await http
        .get(
          Uri.parse('${ApiConstants.baseUrl}$path'),
          headers: {..._headers, 'Cache-Control': 'no-store'},
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'بارگذاری عکس ناموفق بود';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        message = body['error'] as String? ?? message;
      } catch (_) {
        // A reverse proxy may return an HTML error instead of JSON.
      }
      throw ApiException(statusCode: response.statusCode, message: message);
    }
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await http
        .put(
          Uri.parse('${ApiConstants.baseUrl}$path'),
          headers: _jsonHeaders,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    return _handle(res);
  }

  Future<Map<String, dynamic>> uploadFile(
    String path,
    File file, {
    String fieldName = 'file',
    Map<String, String>? fields,
  }) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$path');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers);
    if (fields != null) request.fields.addAll(fields);

    final ext = file.path.split('.').last.toLowerCase();
    String mime = 'application/octet-stream';
    if (['jpg', 'jpeg'].contains(ext))
      mime = 'image/jpeg';
    else if (ext == 'png')
      mime = 'image/png';
    else if (ext == 'gif')
      mime = 'image/gif';
    else if (ext == 'webp')
      mime = 'image/webp';
    else if (ext == 'mp4')
      mime = 'video/mp4';
    else if (ext == 'mp3')
      mime = 'audio/mpeg';
    else if (ext == 'm4a')
      mime = 'audio/mp4';

    request.files.add(
      await http.MultipartFile.fromPath(
        fieldName,
        file.path,
        contentType: MediaType.parse(mime),
      ),
    );

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    return _handle(res);
  }

  Map<String, dynamic> _handle(http.Response res) {
    final body = res.body.isNotEmpty
        ? jsonDecode(res.body) as Map<String, dynamic>
        : <String, dynamic>{};
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    }
    throw ApiException(
      statusCode: res.statusCode,
      message: body['error'] as String? ?? 'خطای ناشناخته',
    );
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException({required this.statusCode, required this.message});

  @override
  String toString() => message;
}
