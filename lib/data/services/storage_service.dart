import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static late Box _box;
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _box = await Hive.openBox('secure_messenger');
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<void> saveToken(String token) async {
    await _prefs.setString('access_token', token);
  }

  static String? getToken() => _prefs.getString('access_token');

  static Future<void> saveRefreshToken(String token) async {
    await _prefs.setString('refresh_token', token);
  }

  static String? getRefreshToken() => _prefs.getString('refresh_token');

  static Future<void> clearTokens() async {
    await _prefs.remove('access_token');
    await _prefs.remove('refresh_token');
    await _prefs.remove('user_id');
  }

  static Future<void> saveDeviceId(String id) async {
    await _prefs.setString('device_id', id);
  }

  static String? getDeviceId() => _prefs.getString('device_id');

  static Future<void> saveUserId(String id) async {
    await _prefs.setString('user_id', id);
  }

  static String? getUserId() => _prefs.getString('user_id');
}
