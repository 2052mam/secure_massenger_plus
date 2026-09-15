import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/user_model.dart';
import '../../data/services/account_service.dart';
import '../../data/services/api_service.dart';
import '../../data/services/storage_service.dart';

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<UserModel?>>((ref) {
      return AuthNotifier()..checkSession();
    });

/// Published only after credentials and auth state agree. A token refresh for
/// the same user updates request clients without resetting their route stack.
/// Older clients/requests retain their original account's credentials.
final authenticatedSessionProvider =
    Provider<({String? userId, String? token, ApiService api})>((ref) {
      final user = ref.watch(authNotifierProvider).valueOrNull;
      final token = user == null ? null : StorageService.getToken();
      return (userId: user?.id, token: token, api: ApiService.withToken(token));
    });

class AuthNotifier extends StateNotifier<AsyncValue<UserModel?>> {
  AuthNotifier() : super(const AsyncValue.loading());

  int _sessionGeneration = 0;

  bool _isCurrent(int generation) =>
      mounted && generation == _sessionGeneration;

  Future<({UserModel user, String accessToken})> _loadSession(
    String accessToken,
    String refreshToken,
  ) async {
    Map<String, dynamic> response;
    try {
      response = await ApiService.withToken(accessToken).get('/users/me');
    } on ApiException catch (error) {
      if (![401, 422].contains(error.statusCode) || refreshToken.isEmpty)
        rethrow;
      final refreshed = await ApiService.withToken(
        refreshToken,
      ).post('/auth/refresh', {});
      accessToken = refreshed['access_token'] as String;
      response = await ApiService.withToken(accessToken).get('/users/me');
    }
    return (user: UserModel.fromJson(response), accessToken: accessToken);
  }

  Future<void> checkSession() async {
    final generation = ++_sessionGeneration;
    final previous = state.valueOrNull;
    var token = StorageService.getToken();
    if (token == null || token.isEmpty) {
      // No active token, but the device may still hold a valid saved account
      // (e.g. after an "add account" flow was cancelled). Restoring it keeps
      // the user out of the login screen they already passed once.
      var saved = await AccountService.getActive();
      if (saved == null) {
        final all = await AccountService.list();
        if (all.isNotEmpty) saved = all.last;
      }
      if (saved != null) {
        try {
          final session = await _loadSession(
            saved.accessToken,
            saved.refreshToken,
          );
          if (!_isCurrent(generation)) return;
          await _saveSession(
            session.user,
            session.accessToken,
            saved.refreshToken,
            generation,
          );
          return;
        } catch (_) {
          // Saved session is dead — drop it and fall through to signed-out.
          await AccountService.remove(saved.userId);
        }
      }
      if (!_isCurrent(generation)) return;
      ApiService().setToken(null);
      state = const AsyncValue.data(null);
      return;
    }
    try {
      final refreshToken = StorageService.getRefreshToken() ?? '';
      final session = await _loadSession(token, refreshToken);
      if (!_isCurrent(generation)) return;
      await _saveSession(
        session.user,
        session.accessToken,
        refreshToken,
        generation,
      );
    } catch (error, stack) {
      // A response belonging to the previous account must never log out the
      // account that has just finished signing in / switching.
      if (!_isCurrent(generation)) return;
      if (error is ApiException &&
          [401, 403, 404, 422].contains(error.statusCode)) {
        await _clearSession(generation);
      } else if (previous == null) {
        // Keep credentials on transient network failures; retry remains possible.
        state = AsyncValue.error(error, stack);
      }
    }
  }

  Future<void> _saveSession(
    UserModel user,
    String accessToken,
    String refreshToken,
    int generation,
  ) async {
    if (!_isCurrent(generation)) return;
    await StorageService.saveToken(accessToken);
    if (!_isCurrent(generation)) return;
    await StorageService.saveRefreshToken(refreshToken);
    if (!_isCurrent(generation)) return;
    await StorageService.saveUserId(user.id);
    if (!_isCurrent(generation)) return;
    await AccountService.save(
      SavedAccount.fromUser(user, accessToken, refreshToken),
    );
    if (!_isCurrent(generation)) return;
    ApiService().setToken(accessToken);
    state = AsyncValue.data(user);
  }

  Future<void> setLoggedIn(
    UserModel user,
    String accessToken,
    String refreshToken,
  ) {
    return _saveSession(user, accessToken, refreshToken, ++_sessionGeneration);
  }

  Future<void> switchAccount(SavedAccount account) async {
    final generation = ++_sessionGeneration;
    // Validate/refresh BEFORE replacing the current user's credentials. A bad
    // saved session must not strand a valid account on the login screen.
    final session = await _loadSession(
      account.accessToken,
      account.refreshToken,
    );
    if (!_isCurrent(generation)) return;
    if (session.user.id != account.userId) {
      throw ApiException(statusCode: 403, message: 'حساب ذخیره‌شده معتبر نیست');
    }
    await _saveSession(
      session.user,
      session.accessToken,
      account.refreshToken,
      generation,
    );
  }

  void setUser(UserModel? user) {
    ++_sessionGeneration;
    state = AsyncValue.data(user);
  }

  Future<void> _clearSession(int generation) async {
    if (!_isCurrent(generation)) return;
    await StorageService.clearTokens();
    if (!_isCurrent(generation)) return;
    await AccountService.clearActive();
    if (!_isCurrent(generation)) return;
    ApiService().setToken(null);
    state = const AsyncValue.data(null);
  }

  Future<void> _logout({required bool keepAccounts}) async {
    final generation = ++_sessionGeneration;
    final userId = state.valueOrNull?.id ?? StorageService.getUserId();
    final token = StorageService.getToken();
    if (token != null) {
      try {
        await ApiService.withToken(token).post('/auth/logout', {});
      } catch (_) {}
    }
    if (!_isCurrent(generation)) return;
    if (!keepAccounts && userId != null) await AccountService.remove(userId);
    await _clearSession(generation);
  }

  Future<void> logout() => _logout(keepAccounts: false);

  /// Sign out of the active account but keep it in the saved-accounts list, so
  /// it can be resumed from the login screen without retyping credentials.
  Future<void> logoutKeepAccounts() => _logout(keepAccounts: true);
}
