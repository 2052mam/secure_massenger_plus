import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:secure_messenger/presentation/widgets/media/voice_message_player.dart';

class FakeAudioPlayer extends Fake implements AudioPlayer {
  final positions = StreamController<Duration>.broadcast();
  final durations = StreamController<Duration?>.broadcast();
  final buffered = StreamController<Duration>.broadcast();
  final states = StreamController<PlayerState>.broadcast();
  bool active = false;
  bool completed = false;
  bool disposed = false;
  bool failLoad = false;
  int plays = 0;
  int loads = 0;
  Duration lastSeek = Duration.zero;
  double selectedSpeed = 1;
  Map<String, String>? requestHeaders;

  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<Duration?> get durationStream => durations.stream;
  @override
  Stream<Duration> get bufferedPositionStream => buffered.stream;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => const Stream.empty();

  void emitState() => states.add(
    PlayerState(
      active,
      completed ? ProcessingState.completed : ProcessingState.ready,
    ),
  );

  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    loads++;
    requestHeaders = headers;
    if (failLoad) throw StateError('Offline');
    durations.add(const Duration(seconds: 120));
    buffered.add(const Duration(seconds: 90));
    emitState();
    return const Duration(seconds: 120);
  }

  @override
  Future<void> play() async {
    active = true;
    plays++;
    emitState();
  }

  @override
  Future<void> pause() async {
    active = false;
    emitState();
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    lastSeek = position ?? Duration.zero;
    completed = lastSeek >= const Duration(seconds: 120);
    positions.add(lastSeek);
    emitState();
  }

  @override
  Future<void> setSpeed(double speed) async {
    selectedSpeed = speed;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await Future.wait([
      positions.close(),
      durations.close(),
      buffered.close(),
      states.close(),
    ]);
  }

  void finish() {
    completed = true;
    positions.add(const Duration(seconds: 120));
    emitState();
  }
}

Widget host(FakeAudioPlayer player) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: VoiceMessagePlayer(
        url: 'https://example.invalid/audio',
        token: 'test-token',
        player: player,
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'Voice play, rewind, forward, scrub, speed and replay use the engine',
    (tester) async {
      final player = FakeAudioPlayer();
      await tester.pumpWidget(host(player));
      await tester.tap(find.byTooltip('Play'));
      await tester.pumpAndSettle();
      expect(player.requestHeaders, {'Authorization': 'Bearer test-token'});
      expect(player.plays, 1);
      expect(find.text('0:00 / 2:00'), findsOneWidget);

      await tester.tap(find.byTooltip('Forward 10 seconds'));
      await tester.pumpAndSettle();
      expect(player.lastSeek, const Duration(seconds: 10));
      await tester.tap(find.byTooltip('Rewind 10 seconds'));
      await tester.pumpAndSettle();
      expect(player.lastSeek, Duration.zero);
      await tester.tap(find.byTooltip('Rewind 10 seconds'));
      await tester.pumpAndSettle();
      expect(player.lastSeek, Duration.zero);

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(60000);
      slider.onChanged!(60000);
      player.positions.add(const Duration(seconds: 1));
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 60000);
      slider.onChangeEnd!(60000);
      await tester.pumpAndSettle();
      expect(player.lastSeek, const Duration(minutes: 1));

      await tester.tap(find.text('1×'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2×'));
      await tester.pumpAndSettle();
      expect(player.selectedSpeed, 2);
      expect(find.text('2×'), findsOneWidget);

      player.finish();
      await tester.pumpAndSettle();
      expect(player.active, isFalse);
      expect(find.byTooltip('Replay'), findsOneWidget);
      await tester.tap(find.byTooltip('Replay'));
      await tester.pumpAndSettle();
      expect(player.lastSeek, Duration.zero);
      expect(player.plays, 2);
      expect(player.loads, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(player.disposed, isTrue);
    },
  );

  testWidgets('Voice load failures offer a working retry', (tester) async {
    final player = FakeAudioPlayer()..failLoad = true;
    await tester.pumpWidget(host(player));
    await tester.tap(find.byTooltip('Play'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load media'), findsOneWidget);
    player.failLoad = false;
    await tester.tap(find.byTooltip('Retry'));
    await tester.pumpAndSettle();
    expect(player.loads, 2);
    expect(player.active, isTrue);
  });

  testWidgets(
    'Paused voice seeks without starting playback, including on RTL phones',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final player = FakeAudioPlayer();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: SizedBox(
                width: 220,
                child: VoiceMessagePlayer(
                  url: 'https://example.invalid/audio',
                  player: player,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Play'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Pause'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Forward 10 seconds'));
      await tester.pumpAndSettle();
      expect(player.lastSeek, const Duration(seconds: 10));
      expect(player.active, isFalse);
      expect(player.plays, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
