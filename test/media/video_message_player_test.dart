import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:secure_messenger/presentation/widgets/media/video_message_player.dart';
import 'package:secure_messenger/presentation/widgets/media/video_playback_controls.dart';

class FakeVideoController extends ValueNotifier<VideoPlayerValue>
    implements VideoPlayerController {
  int initializations = 0;
  bool disposed = false;
  Completer<void>? initializeGate;

  FakeVideoController()
    : super(
        const VideoPlayerValue(
          duration: Duration(minutes: 2),
          size: Size(1920, 1080),
          isInitialized: true,
        ),
      );

  @override
  int get playerId => VideoPlayerController.kUninitializedPlayerId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> initialize() async {
    initializations++;
    await initializeGate?.future;
  }

  @override
  Future<void> play() async {
    value = value.copyWith(isPlaying: true, isCompleted: false);
  }

  @override
  Future<void> pause() async {
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    value = value.copyWith(
      position: position,
      isCompleted: position >= value.duration,
    );
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    value = value.copyWith(playbackSpeed: speed);
  }

  @override
  Future<void> setVolume(double volume) async {
    value = value.copyWith(volume: volume);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    super.dispose();
  }
}

void main() {
  testWidgets('Video controls support seek, speed, mute, and replay', (
    tester,
  ) async {
    final controller = FakeVideoController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 220,
            child: VideoPlaybackControls(
              controller: controller,
              playbackOwner: controller,
              onFullscreen: () {},
              onRetry: () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Play'));
    await tester.pumpAndSettle();
    expect(controller.value.isPlaying, isTrue);
    await tester.tap(find.byTooltip('Forward 10 seconds'));
    await tester.pumpAndSettle();
    expect(controller.value.position, const Duration(seconds: 10));
    await tester.tap(find.byTooltip('Rewind 10 seconds'));
    await tester.pumpAndSettle();
    expect(controller.value.position, Duration.zero);
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(45000);
    slider.onChangeEnd!(45000);
    await tester.pumpAndSettle();
    expect(controller.value.position, const Duration(seconds: 45));
    await tester.tap(find.text('1×'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2.0×'));
    await tester.pumpAndSettle();
    expect(controller.value.playbackSpeed, 2);
    await tester.tap(find.byTooltip('Mute'));
    await tester.pumpAndSettle();
    expect(controller.value.volume, 0);
    await tester.tap(find.byTooltip('Unmute'));
    await tester.pumpAndSettle();
    expect(controller.value.volume, 1);
    controller.value = controller.value.copyWith(
      position: controller.value.duration,
      isPlaying: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Replay'));
    await tester.pumpAndSettle();
    expect(controller.value.position, Duration.zero);
    expect(controller.value.isPlaying, isTrue);
  });

  testWidgets(
    'Fullscreen reuses the authenticated controller and restores orientation',
    (tester) async {
      final controller = FakeVideoController();
      var factoryCalls = 0;
      Map<String, String>? headers;
      final orientations = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'SystemChrome.setPreferredOrientations')
              orientations.add(call.arguments);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280,
              child: VideoMessagePlayer(
                url: 'https://example.invalid/video',
                authToken: 'test-token',
                controllerFactory: (url, auth) {
                  factoryCalls++;
                  headers = auth;
                  return controller;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(headers, {'Authorization': 'Bearer test-token'});
      await controller.seekTo(const Duration(seconds: 25));
      await controller.setPlaybackSpeed(2);
      await tester.pump();
      await tester.tap(find.byTooltip('Full screen'));
      await tester.pumpAndSettle();
      expect(factoryCalls, 1);
      expect(controller.initializations, 1);
      expect(controller.value.position, const Duration(seconds: 25));
      expect(controller.value.playbackSpeed, 2);
      expect(find.byTooltip('Exit full screen'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(controller.value.position, const Duration(seconds: 25));
      expect(orientations.last, [
        'DeviceOrientation.portraitUp',
        'DeviceOrientation.portraitDown',
      ]);
      expect(controller.disposed, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(controller.disposed, isTrue);
    },
  );

  testWidgets(
    'Deleting a full-screen video closes the route before disposing its controller',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (_) async => null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final controller = FakeVideoController();
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, show, __) => show
                  ? SizedBox(
                      width: 280,
                      child: VideoMessagePlayer(
                        url: 'https://example.invalid/video',
                        controllerFactory: (_, __) => controller,
                      ),
                    )
                  : const Text('Message removed'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Full screen'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Exit full screen'), findsOneWidget);
      visible.value = false; // The same removal triggered by deletion polling.
      await tester.pumpAndSettle();
      expect(find.byTooltip('Exit full screen'), findsNothing);
      expect(find.text('Message removed'), findsOneWidget);
      expect(controller.disposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Disposing during video initialization is safe', (tester) async {
    final gate = Completer<void>();
    final controller = FakeVideoController()..initializeGate = gate;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: VideoMessagePlayer(
              url: 'https://example.invalid/video',
              controllerFactory: (_, __) => controller,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pumpAndSettle();
    expect(controller.disposed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
