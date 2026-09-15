import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secure_messenger/data/services/account_service.dart';
import 'package:secure_messenger/data/services/api_service.dart';
import 'package:secure_messenger/data/services/storage_service.dart';
import 'package:secure_messenger/presentation/providers/auth_provider.dart';
import 'package:secure_messenger/presentation/providers/chat_list_provider.dart';

import '../support/messenger_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = TestStorage();
  setUpAll(storage.open);
  setUp(storage.reset);
  tearDownAll(storage.close);

  for (final staleStatus in [200, 401]) {
    test(
      'Late session check ($staleStatus) cannot replace or log out a new account',
      () async {
        final gate = Completer<http.Response>();
        final started = Completer<void>();
        final client = MockClient((request) async {
          expect(
            request.headers['authorization'],
            anyOf('Bearer alice-access', 'Bearer alice-refresh'),
          );
          if (request.url.path.endsWith('/auth/refresh'))
            return jsonResponse({'error': 'Expired'}, status: 401);
          if (!started.isCompleted) started.complete();
          return gate.future;
        });
        await http.runWithClient(() async {
          final auth = AuthNotifier();
          final container = ProviderContainer(
            overrides: [authNotifierProvider.overrideWith((ref) => auth)],
          );
          addTearDown(container.dispose);
          container.read(authNotifierProvider);
          await auth.setLoggedIn(
            testUser('alice'),
            'alice-access',
            'alice-refresh',
          );
          final checking = auth.checkSession();
          await started.future;
          await auth.setLoggedIn(testUser('bob'), 'bob-access', 'bob-refresh');
          gate.complete(
            staleStatus == 200
                ? jsonResponse(testUser('alice').toJson())
                : jsonResponse({'error': 'Expired'}, status: 401),
          );
          await checking;
          expect(container.read(authNotifierProvider).valueOrNull!.id, 'bob');
          expect(StorageService.getToken(), 'bob-access');
          expect(StorageService.getUserId(), 'bob');
          expect(await AccountService.activeId(), 'bob');
        }, () => client);
      },
    );
  }

  test(
    'Failed switch leaves the current working account and credentials intact',
    () async {
      await http.runWithClient(
        () async {
          final auth = AuthNotifier();
          final container = ProviderContainer(
            overrides: [authNotifierProvider.overrideWith((ref) => auth)],
          );
          addTearDown(container.dispose);
          container.read(authNotifierProvider);
          await auth.setLoggedIn(
            testUser('alice'),
            'alice-access',
            'alice-refresh',
          );
          await expectLater(
            auth.switchAccount(
              SavedAccount.fromUser(
                testUser('bob'),
                'expired-bob',
                'expired-refresh',
              ),
            ),
            throwsA(isA<ApiException>()),
          );
          expect(container.read(authNotifierProvider).valueOrNull!.id, 'alice');
          expect(StorageService.getToken(), 'alice-access');
          expect(await AccountService.activeId(), 'alice');
        },
        () => MockClient(
          (_) async => jsonResponse({'error': 'Expired'}, status: 401),
        ),
      );
    },
  );

  test(
    'Saved access tokens can refresh before switching, without another 2FA login',
    () async {
      final headers = <String?>[];
      final client = MockClient((request) async {
        final token = request.headers['authorization'];
        headers.add(token);
        if (token == 'Bearer expired-bob')
          return jsonResponse({'error': 'Expired'}, status: 401);
        if (request.url.path.endsWith('/auth/refresh')) {
          expect(token, 'Bearer bob-refresh');
          return jsonResponse({'access_token': 'new-bob'});
        }
        expect(token, 'Bearer new-bob');
        return jsonResponse(testUser('bob').toJson());
      });
      await http.runWithClient(() async {
        final auth = AuthNotifier();
        addTearDown(auth.dispose);
        await auth.setLoggedIn(
          testUser('alice'),
          'alice-access',
          'alice-refresh',
        );
        await auth.switchAccount(
          SavedAccount.fromUser(testUser('bob'), 'expired-bob', 'bob-refresh'),
        );
        expect(StorageService.getToken(), 'new-bob');
        expect(StorageService.getUserId(), 'bob');
        expect(
          (await AccountService.list()).map((a) => a.userId),
          containsAll(['alice', 'bob']),
        );
        expect(headers, [
          'Bearer expired-bob',
          'Bearer bob-refresh',
          'Bearer new-bob',
        ]);
      }, () => client);
    },
  );

  test(
    'An old in-flight chat-list poll cannot expose the previous account after switching',
    () async {
      final oldResponse = Completer<http.Response>();
      final started = Completer<void>();
      final client = MockClient((request) async {
        if (request.headers['authorization'] == 'Bearer alice-access') {
          if (!started.isCompleted) started.complete();
          return oldResponse.future;
        }
        return jsonResponse({
          'chats': [
            {
              'id': 'bob-chat',
              'chat_type': 'group',
              'title': 'Bob private chat',
              'updated_at': '2026-09-07T12:00:00Z',
            },
          ],
        });
      });
      await http.runWithClient(() async {
        final auth = AuthNotifier();
        final container = ProviderContainer(
          overrides: [authNotifierProvider.overrideWith((ref) => auth)],
        );
        container.read(authNotifierProvider);
        await auth.setLoggedIn(
          testUser('alice'),
          'alice-access',
          'alice-refresh',
        );
        final subscription = container.listen(
          chatListProvider,
          (_, __) {},
          fireImmediately: true,
        );
        try {
          await started.future;
          await auth.setLoggedIn(testUser('bob'), 'bob-access', 'bob-refresh');
          await container.read(chatListProvider.notifier).loadChats();
          oldResponse.complete(
            jsonResponse({
              'chats': [
                {
                  'id': 'alice-chat',
                  'chat_type': 'group',
                  'title': 'Alice private chat',
                  'updated_at': '2026-09-07T12:00:00Z',
                },
              ],
            }),
          );
          await Future<void>.delayed(Duration.zero);
          expect(
            container.read(chatListProvider).valueOrNull!.chats.map(
              (c) => c.id,
            ),
            ['bob-chat'],
          );
        } finally {
          subscription.close();
          container.dispose();
        }
      }, () => client);
    },
  );

  test(
    'Fixed unauthenticated API requests do not fall back to an active account',
    () async {
      await StorageService.saveToken('active-token');
      ApiService().setToken('active-token');
      await http.runWithClient(
        () async {
          await ApiService.withToken(null).post('/auth/login', {});
        },
        () => MockClient((request) async {
          expect(request.headers.containsKey('authorization'), isFalse);
          return jsonResponse({});
        }),
      );
    },
  );
}
