/// A chat owns one coordinator, so voice and video never talk over each other.
/// Players retain their position when another player takes audio focus.
class MediaPlaybackCoordinator {
  Object? _owner;
  Future<void> Function()? _pause;
  Future<void> _pendingPause = Future<void>.value();
  int _generation = 0;

  Future<void> _enqueuePause(Future<void> Function()? pause) {
    return _pendingPause = _pendingPause.then((_) async {
      try {
        await pause?.call();
      } catch (_) {
        // A disposed player must not prevent the next one from taking focus.
      }
    });
  }

  Future<bool> activate(Object owner, Future<void> Function() pause) async {
    final generation = ++_generation;
    final previousPause = identical(_owner, owner) ? null : _pause;
    _owner = owner;
    _pause = pause;
    await _enqueuePause(previousPause);
    return generation == _generation && identical(_owner, owner);
  }

  void release(Object owner) {
    if (!identical(owner, _owner)) return;
    ++_generation;
    _owner = null;
    _pause = null;
  }

  Future<void> pause() {
    ++_generation;
    final pause = _pause;
    _owner = null;
    _pause = null;
    return _enqueuePause(pause);
  }
}
