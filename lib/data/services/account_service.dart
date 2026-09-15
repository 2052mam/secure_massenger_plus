import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

class SavedAccount {
  final String userId;
  final String email;
  final String? mobileNumber;
  final String? username;
  final String displayName;
  final String? avatarUrl;
  final String accessToken;
  final String refreshToken;

  SavedAccount({
    required this.userId,
    required this.email,
    this.mobileNumber,
    this.username,
    required this.displayName,
    this.avatarUrl,
    required this.accessToken,
    required this.refreshToken,
  });

  String get handle => username != null && username!.isNotEmpty
      ? '@$username'
      : mobileNumber ?? email;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'email': email,
    'mobile_number': mobileNumber,
    'username': username,
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'access_token': accessToken,
    'refresh_token': refreshToken,
  };

  factory SavedAccount.fromJson(Map<String, dynamic> j) => SavedAccount(
    userId: j['user_id'] as String,
    email: j['email'] as String? ?? '',
    mobileNumber: j['mobile_number'] as String?,
    username: (j['username'] as String?)?.isNotEmpty == true ? j['username'] as String : null,
    displayName: j['display_name'] as String? ?? '',
    avatarUrl: j['avatar_url'] as String?,
    accessToken: j['access_token'] as String,
    refreshToken: j['refresh_token'] as String? ?? '',
  );

  factory SavedAccount.fromUser(UserModel u, String access, String refresh) =>
      SavedAccount(
        userId: u.id,
        email: u.email,
        mobileNumber: u.mobileNumber,
        username: u.username,
        displayName: u.displayName,
        avatarUrl: u.avatarUrl,
        accessToken: access,
        refreshToken: refresh,
      );
}

class AccountService {
  static const _key = 'saved_accounts_v1';
  static const _activeKey = 'active_account_id';

  static Future<List<SavedAccount>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => SavedAccount.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> save(SavedAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = await list();
    accounts.removeWhere((a) => a.userId == account.userId);
    accounts.add(account);
    // حداکثر ۳ اکانت
    while (accounts.length > 3) {
      accounts.removeAt(0);
    }
    await prefs.setString(
      _key,
      jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
    await prefs.setString(_activeKey, account.userId);
  }

  static Future<void> remove(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = await list();
    accounts.removeWhere((a) => a.userId == userId);
    await prefs.setString(
      _key,
      jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
    if (prefs.getString(_activeKey) == userId) await prefs.remove(_activeKey);
  }

  static Future<void> clearActive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeKey);
  }

  static Future<String?> activeId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeKey);
  }

  static Future<SavedAccount?> getActive() async {
    final id = await activeId();
    if (id == null) return null;
    final accounts = await list();
    try {
      return accounts.firstWhere((a) => a.userId == id);
    } catch (_) {
      return accounts.isEmpty ? null : accounts.first;
    }
  }
}
