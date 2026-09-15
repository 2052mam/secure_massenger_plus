import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_messenger/core/utils/media_utils.dart';
import 'package:secure_messenger/data/services/media_playback_coordinator.dart';

void main() {
  test('Transport positions are clamped, including unknown duration', () {
    expect(
      clampMediaPosition(
        const Duration(seconds: -5),
        const Duration(minutes: 1),
      ),
      Duration.zero,
    );
    expect(
      clampMediaPosition(
        const Duration(minutes: 2),
        const Duration(minutes: 1),
      ),
      const Duration(minutes: 1),
    );
    expect(
      clampMediaPosition(const Duration(seconds: 12), Duration.zero),
      Duration.zero,
    );
  });

  test('Time labels support short and long recordings', () {
    expect(formatMediaDuration(Duration.zero), '0:00');
    expect(formatMediaDuration(const Duration(seconds: 65)), '1:05');
    expect(
      formatMediaDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
    expect(formatMediaDuration(const Duration(seconds: -1)), '0:00');
  });

  test('One player pauses before another gets audio focus', () async {
    final coordinator = MediaPlaybackCoordinator();
    final first = Object();
    final second = Object();
    var pauses = 0;
    expect(
      await coordinator.activate(first, () async {
        pauses++;
      }),
      isTrue,
    );
    expect(
      await coordinator.activate(second, () async {
        pauses++;
      }),
      isTrue,
    );
    expect(pauses, 1);
    coordinator.release(
      first,
    ); // Disposing a stale player must not release second.
    await coordinator.pause();
    expect(pauses, 2);
  });

  test(
    'An in-flight activation cannot play after a newer request or leaving',
    () async {
      final coordinator = MediaPlaybackCoordinator();
      final paused = Completer<void>();
      await coordinator.activate(Object(), () => paused.future);
      final pending = coordinator.activate(Object(), () async {});
      final latest = coordinator.activate(Object(), () async {});
      paused.complete();
      expect(await pending, isFalse);
      expect(await latest, isTrue);
      await coordinator.pause();
    },
  );
}
