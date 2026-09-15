import 'dart:async';

import 'package:flutter/widgets.dart';

import 'api_service.dart';

/// Foreground presence belongs to a session, not to one tab or chat route.
/// Heartbeats use ordinary HTTP; the backend expires them after 60 seconds.
class PresenceService with WidgetsBindingObserver {
  PresenceService(this._api);

  final ApiService _api;
  Timer? _heartbeat;
  Future<void> _pending = Future<void>.value();
  bool _sending = false;
  bool _active = false;
  bool _disposed = false;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _setActive(state == null || state == AppLifecycleState.resumed);
  }

  void _setActive(bool active) {
    if (_disposed || active == _active) return;
    _active = active;
    _heartbeat?.cancel();
    unawaited(_send(active));
    if (active) {
      _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
        if (!_sending) unawaited(_send(true));
      });
    }
  }

  Future<void> _send(bool online) {
    // Serialize lifecycle changes: a slow "online" request cannot overtake
    // the final "offline" request. The API instance retains this user's token.
    _sending = true;
    return _pending = _pending
        .then((_) async {
          try {
            await _api.post('/users/online-status', {'is_online': online});
          } catch (_) {
            // Offline / process termination is covered by server-side expiry.
          }
        })
        .whenComplete(() => _sending = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _setActive(state == AppLifecycleState.resumed);
  }

  void dispose({bool reportOffline = true}) {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _heartbeat?.cancel();
    if (_active && reportOffline) unawaited(_send(false));
  }
}
