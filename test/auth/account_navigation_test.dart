import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secure_messenger/app.dart';
import 'package:secure_messenger/data/services/account_service.dart';
import 'package:secure_messenger/data/services/storage_service.dart';
import 'package:secure_messenger/presentation/providers/auth_provider.dart';
import 'package:secure_messenger/presentation/screens/auth/login_screen.dart';
import 'package:secure_messenger/presentation/screens/auth/phone_verification_screen.dart';
import 'package:secure_messenger/presentation/screens/auth/two_factor_screen.dart';
import 'package:secure_messenger/presentation/screens/home/main_shell.dart';
import 'package:secure_messenger/presentation/screens/settings/account_switcher_screen.dart';

import '../support/messenger_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = TestStorage();
  setUpAll(storage.open);
  setUp(storage.reset);
  tearDownAll(storage.close);

  for (final requiresTotp in [false, true]) {
    testWidgets(
      'Add account -> phone login${requiresTotp ? ' + optional TOTP' : ''} lands on the new chat list',
      (tester) async {
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          final path = request.url.path;
          if (path.endsWith('/chats/')) return jsonResponse({'chats': []});
          if (path.endsWith('/users/online-status') || path.endsWith('/auth/logout')) {
            return jsonResponse({'ok': true});
          }
          if (path.endsWith('/auth/request-phone-code')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['mobile_number'], '+989121234567');
            return jsonResponse({
              'verification_id': 'phone-challenge',
              'mobile_number': '+989••••567',
            }, status: 202);
          }
          if (path.endsWith('/auth/verify-phone')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['verification_id'], 'phone-challenge');
            expect(body['code'], '123456');
            if (requiresTotp) {
              return jsonResponse({
                'require_2fa': true,
                'verification_id': 'totp-challenge',
              });
            }
            return jsonResponse({
              'user': testUser('bob').toJson(),
              'access_token': 'bob-access',
              'refresh_token': 'bob-refresh',
            });
          }
          if (path.endsWith('/auth/verify-login-2fa')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['verification_id'], 'totp-challenge');
            expect(body['code'], '123456');
            return jsonResponse({
              'user': testUser('bob').toJson(),
              'access_token': 'bob-access',
              'refresh_token': 'bob-refresh',
            });
          }
          throw StateError('Unexpected request: ${request.method} $path');
        });

        await http.runWithClient(() async {
          final auth = AuthNotifier();
          await auth.setLoggedIn(testUser('alice'), 'alice-access', 'alice-refresh');
          await tester.pumpWidget(
            ProviderScope(
              overrides: [authNotifierProvider.overrideWith((ref) => auth)],
              child: const SecureMessengerApp(),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Settings'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Accounts'));
          await tester.tap(find.text('Accounts'));
          await tester.pumpAndSettle();
          expect(find.byType(AccountSwitcherScreen), findsOneWidget);
          await tester.tap(find.text('Add account'));
          await tester.pumpAndSettle();
          expect(find.byType(LoginScreen), findsOneWidget);
          // The add-account route leaves Alice's active session intact until
          // Bob has completed phone verification.
          expect(StorageService.getUserId(), 'alice');
          expect((await AccountService.list()).single.userId, 'alice');

          await tester.enterText(find.byType(TextFormField).single, '+989121234567');
          await tester.tap(find.text('ارسال کد ورود'));
          await tester.pumpAndSettle();
          expect(find.byType(PhoneVerificationScreen), findsOneWidget);
          await tester.enterText(find.byType(TextField).single, '123456');
          await tester.tap(find.text('ورود'));
          await tester.pumpAndSettle();
          if (requiresTotp) {
            expect(find.byType(TwoFactorScreen), findsOneWidget);
            await tester.enterText(find.byType(TextField).single, '123456');
            await tester.tap(find.text('تأیید'));
          }
          await tester.pumpAndSettle();

          expect(find.byType(MainShell), findsOneWidget);
          expect(find.byType(LoginScreen, skipOffstage: false), findsNothing);
          expect(find.byType(PhoneVerificationScreen, skipOffstage: false), findsNothing);
          expect(find.byType(TwoFactorScreen, skipOffstage: false), findsNothing);
          expect(StorageService.getUserId(), 'bob');
          expect(StorageService.getToken(), 'bob-access');
          expect(await AccountService.activeId(), 'bob');
          expect((await AccountService.list()).map((account) => account.userId), containsAll(['alice', 'bob']));
          expect(
            requests.where((request) => request.url.path.endsWith('/chats/')).last.headers['authorization'],
            'Bearer bob-access',
          );
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }, () => client);
      },
    );
  }

  testWidgets('Refreshing the same account retains routes and renews account-owned clients', (tester) async {
    final tokens = <String?>[];
    final client = MockClient((request) async {
      tokens.add(request.headers['authorization']);
      return request.url.path.endsWith('/chats/')
          ? jsonResponse({'chats': []})
          : jsonResponse({'ok': true});
    });
    await http.runWithClient(() async {
      final auth = AuthNotifier();
      await auth.setLoggedIn(testUser('alice'), 'alice-access', 'alice-refresh');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith((ref) => auth)],
          child: const SecureMessengerApp(),
        ),
      );
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Keep this route'))));
      await tester.pumpAndSettle();
      await auth.setLoggedIn(testUser('alice'), 'renewed-access', 'alice-refresh');
      await tester.pumpAndSettle();
      expect(find.text('Keep this route'), findsOneWidget);
      expect(navigator.canPop(), isTrue);
      expect(tokens.last, 'Bearer renewed-access');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }, () => client);
  });
}
