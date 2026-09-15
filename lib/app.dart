import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/app_theme.dart';
import 'data/services/background_poll_service.dart';
import 'data/services/connection_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/system_settings_service.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/providers/locale_provider.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/chat/chat_screen.dart';
import 'presentation/screens/home/main_shell.dart';

class SecureMessengerApp extends ConsumerStatefulWidget {
  const SecureMessengerApp({super.key});

  @override
  ConsumerState<SecureMessengerApp> createState() => _SecureMessengerAppState();
}

class _SecureMessengerAppState extends ConsumerState<SecureMessengerApp> {
  bool _launchHandled = false;
  bool _bgStarted = false;

  /// The navigator key is minted fresh on EVERY identity change. A static
  /// global key would reparent the old Navigator (with its Login/Code route
  /// stack) into the rebuilt tree and silently ignore the new `home:` —
  /// leaving the user stuck on the code screen after a successful login.
  bool _navKeyInit = false;
  String? _navUserId;
  GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    NotificationService.onNotificationTap = _openChat;
  }

  void _openChat(String chatId, String title, String chatType) {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          chatId: chatId,
          title: title,
          chatType: chatType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final authState = ref.watch(authNotifierProvider);
    final userId = authState.valueOrNull?.id;

    // New identity => new Navigator, so `home:` below takes effect and no
    // route from the previous session (login/code/register/2FA screens)
    // can survive. Same-user refreshes keep the existing Navigator.
    if (!_navKeyInit || _navUserId != userId) {
      _navKeyInit = true;
      _navUserId = userId;
      _navigatorKey = GlobalKey<NavigatorState>();
    }

    // Notification taps only make sense while signed in.
    NotificationService.appReady = userId != null;
    if (userId != null && !_bgStarted) {
      _bgStarted = true;
      // Side effects run post-frame, never mid-build: the permission dialog
      // and worker registration must not race the login route transition.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Ask once per login: Android 13+ / iOS both need explicit consent.
        NotificationService().requestPermissions();
        // Keep-alive service first (survives swipe-away), WorkManager stays
        // as the backup for when the service is disabled.
        ConnectionService.startIfEnabled();
        BackgroundPollService.start();
        // Silently opt out of "Pause app activity if unused" when the ROM
        // allows it: hibernation would freeze the service after swipe-away.
        // When refused, the setup dialog guides the user to flip it manually.
        SystemSettingsService.setHibernationExempt();
        if (!_launchHandled) {
          _launchHandled = true;
          // A tap that launched the app from killed state: open that chat.
          Future.delayed(
            const Duration(milliseconds: 800),
            () => NotificationService().handleLaunchDetails(),
          );
        }
      });
    } else if (userId == null) {
      _bgStarted = false;
    }

    return MaterialApp(
      // An identity change discards every route from the previous session,
      // including nested login/register/2FA and account-management routes.
      // Theme, locale and profile refreshes for the SAME user retain routes.
      // (Works together with the per-identity _navigatorKey above: a static
      // navigator key would reparent the old route stack and break this.)
      key: ValueKey(userId ?? 'signed-out'),
      navigatorKey: _navigatorKey,
      title: 'SecureMessenger',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: const [Locale('fa', 'IR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(
          textDirection: locale.languageCode == 'fa'
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: authState.when(
        data: (user) {
          if (user != null) return const MainShell();
          return const LoginScreen();
        },
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, __) => const LoginScreen(),
      ),
    );
  }
}
