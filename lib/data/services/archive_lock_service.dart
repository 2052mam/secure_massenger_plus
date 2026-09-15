import 'api_service.dart';

class _Unlock {
  _Unlock(this.token, this.expiresAt);
  final String token;
  final DateTime expiresAt;

  bool get isValid => DateTime.now().isBefore(expiresAt);
}

/// Keeps the archive unlock token for the running app session only.
///
/// The 4 digit PIN itself is never stored anywhere on the device: it is sent
/// once, exchanged for a short lived server token, and forgotten. Killing the
/// app (or switching account) locks the archive again.
class ArchiveLockService {
  ArchiveLockService(this._api, {this.userId});

  final ApiService _api;
  final String? userId;

  // Survives provider rebuilds (e.g. a token refresh) but never a restart.
  static final Map<String, _Unlock> _unlocks = {};

  String get _key => userId ?? 'anonymous';

  bool get isUnlocked {
    final unlock = _unlocks[_key];
    if (unlock == null) return false;
    if (!unlock.isValid) {
      _unlocks.remove(_key);
      return false;
    }
    return true;
  }

  /// Header expected by the backend for every archived-chat request.
  Map<String, String> get headers {
    final unlock = _unlocks[_key];
    if (unlock == null || !unlock.isValid) return const {};
    return {'X-Archive-Token': unlock.token};
  }

  void lock() => _unlocks.remove(_key);

  static void lockAll() => _unlocks.clear();

  void _store(Map<String, dynamic> response) {
    final token = response['archive_token'] as String?;
    if (token == null || token.isEmpty) {
      _unlocks.remove(_key);
      return;
    }
    final seconds = response['expires_in'] as int? ?? 1800;
    // Expire a minute early so a request never races the server's clock.
    _unlocks[_key] = _Unlock(
      token,
      DateTime.now().add(Duration(seconds: seconds > 90 ? seconds - 60 : seconds)),
    );
  }

  /// Throws [ApiException] with status 403 when the PIN is wrong.
  Future<void> unlock(String pin) async {
    final response = await _api.post('/users/me/archive-pin/verify', {
      'pin': pin,
    });
    _store(response);
  }

  Future<void> setPin(String pin, {String? currentPin}) async {
    final response = await _api.post('/users/me/archive-pin', {
      'pin': pin,
      if (currentPin != null && currentPin.isNotEmpty) 'current_pin': currentPin,
    });
    _store(response);
  }

  Future<void> removePin(String pin) async {
    await _api.post('/users/me/archive-pin/remove', {'pin': pin});
    lock();
  }
}
