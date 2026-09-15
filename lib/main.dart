import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app.dart';
import 'core/theme/app_theme.dart';
import 'data/services/background_poll_service.dart';
import 'data/services/connection_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/push_service.dart';
import 'data/services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Hive.initFlutter();
  await StorageService.init();

  // Local notifications work with zero push infrastructure (no FCM), so they
  // keep working under sanctions/filtering. The foreground poller notifies
  // instantly while alive; the keep-alive service covers swipe-away; the
  // WorkManager task is the backup when the service is disabled.
  FlutterForegroundTask.initCommunicationPort();
  await NotificationService().init();
  // FCM is best-effort: without google-services.json it silently stays in
  // polling-only mode and every path below keeps working.
  await PushService.init();
  await ConnectionService.init();
  await BackgroundPollService.init();

  runApp(
    const ProviderScope(
      child: SecureMessengerApp(),
    ),
  );
}
