import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reference-counted FLAG_SECURE leases prevent a late route cleanup from
/// disabling protection on a newly opened view-once route.
class ScreenPrivacyService {
  static const _channel = MethodChannel('secure_messenger/screen_privacy');
  static int _leases = 0;
  static Future<void> _pending = Future<void>.value();

  static Future<void> _setProtected(bool enabled) {
    return _pending = _pending.catchError((Object _) {}).then((_) async {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod<void>('setProtected', enabled);
      }
    });
  }

  static Future<Future<void> Function()> acquire() async {
    ++_leases;
    try {
      await _setProtected(true);
    } catch (_) {
      --_leases;
      rethrow;
    }
    var released = false;
    return () async {
      if (released) return;
      released = true;
      if (--_leases == 0) await _setProtected(false);
    };
  }
}
