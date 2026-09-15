import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_messenger/data/services/screen_privacy_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Overlapping view-once routes release screen protection only once',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel('secure_messenger/screen_privacy');
      final calls = <bool>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.arguments as bool);
        return null;
      });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(channel, null);
      });

      final releaseFirst = await ScreenPrivacyService.acquire();
      final releaseSecond = await ScreenPrivacyService.acquire();
      expect(calls, [true, true]);
      await releaseFirst();
      await releaseFirst(); // A repeated cleanup cannot release the other route.
      expect(calls, [true, true]);
      await releaseSecond();
      expect(calls, [true, true, false]);
    },
  );
}
