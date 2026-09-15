import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secure_messenger/app.dart';
import 'package:secure_messenger/data/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('messenger-widget-test-');
    Hive.init(directory.path);
    await StorageService.init();
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets('Logged-out app opens sign-in (not the template counter)', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: SecureMessengerApp()));
    await tester.pumpAndSettle();
    expect(find.text('ورود به SecureMessenger'), findsOneWidget);
    expect(find.text('حساب ندارید؟ ثبت‌نام کنید'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
