import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_messenger/data/services/api_service.dart';
import 'package:secure_messenger/presentation/screens/media/view_once_photo_screen.dart';
import 'package:secure_messenger/presentation/widgets/media/photo_canvas.dart';

import 'test_image.dart';

void main() {
  const privacy = MethodChannel('secure_messenger/screen_privacy');
  final protection = <bool>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    protection.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(privacy, (call) async {
          protection.add(call.arguments as bool);
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(privacy, null);
  });

  testWidgets(
    'Photo zoom viewport fills the screen instead of an inset dialog',
    (tester) async {
      final transform = TransformationController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: PhotoCanvas(
              image: MemoryImage(testImageBytes),
              transformationController: transform,
            ),
          ),
        ),
      );
      final viewport = find.byKey(const ValueKey('photo-viewport'));
      expect(tester.getSize(viewport), const Size(800, 600));
      expect(find.byType(Dialog), findsNothing);
      final point = tester.getTopLeft(viewport) + const Offset(150, 200);
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(transform.value.getMaxScaleOnAxis(), closeTo(3, 0.01));
      expect(transform.value.entry(0, 3), closeTo(-300, 0.1));
      expect(transform.value.entry(1, 3), closeTo(-400, 0.1));
      await tester.drag(viewport, const Offset(70, 20));
      await tester.pumpAndSettle();
      expect(transform.value.entry(0, 3), greaterThan(-300));
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(transform.value.getMaxScaleOnAxis(), closeTo(1, 0.01));
      await tester.pumpWidget(const SizedBox());
      transform.dispose();
    },
  );

  testWidgets('View-once validates real image bytes before claim and reveal', (
    tester,
  ) async {
    final order = <String>[];
    final viewed = Completer<void>();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: ViewOncePhotoScreen(
            loadPhoto: () async {
              order.add('download');
              return testImageBytes;
            },
            consumePhoto: () async {
              order.add('claim');
              return DateTime(2026, 9, 7);
            },
            onViewed: (_) {
              order.add('viewed');
              viewed.complete();
            },
          ),
        ),
      );
      await viewed.future.timeout(const Duration(seconds: 5));
    });
    await tester.pumpAndSettle();
    expect(order, ['download', 'claim', 'viewed']);
    expect(find.byType(PhotoCanvas), findsOneWidget);
    expect(find.byType(RawImage), findsOneWidget);
    expect(find.byType(Image), findsNothing); // No second asynchronous decode.
    expect(protection.first, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(protection.last, isFalse);
  });

  testWidgets('Failed download is retryable and does not consume the photo', (
    tester,
  ) async {
    var claims = 0;
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ViewOncePhotoScreen(
          loadPhoto: () async {
            loads++;
            throw StateError('offline');
          },
          consumePhoto: () async {
            claims++;
            return DateTime(2026);
          },
          onViewed: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load media'), findsOneWidget);
    expect(claims, 0);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(claims, 0);
  });

  testWidgets('A lost single-use claim never reveals the downloaded image', (
    tester,
  ) async {
    final attempted = Completer<void>();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: ViewOncePhotoScreen(
            loadPhoto: () async => testImageBytes,
            consumePhoto: () async {
              attempted.complete();
              throw ApiException(statusCode: 410, message: 'Already viewed');
            },
            onViewed: (_) => fail('A failed claim cannot be marked viewed'),
          ),
        ),
      );
      await attempted.future.timeout(const Duration(seconds: 5));
    });
    await tester.pumpAndSettle();
    expect(find.byType(PhotoCanvas), findsNothing);
    expect(find.text('This photo is no longer available'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('Leaving during download never claims or reveals a photo later', (
    tester,
  ) async {
    final bytes = Completer<Uint8List>();
    var claims = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ViewOncePhotoScreen(
          loadPhoto: () => bytes.future,
          consumePhoto: () async {
            claims++;
            return DateTime(2026);
          },
          onViewed: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    bytes.complete(testImageBytes);
    await tester.pumpAndSettle();
    expect(claims, 0);
    expect(tester.takeException(), isNull);
    expect(protection.last, isFalse);
  });
}
