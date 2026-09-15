import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:record/record.dart';
import 'package:secure_messenger/presentation/providers/auth_provider.dart';
import 'package:secure_messenger/presentation/screens/chat/chat_screen.dart';
import 'package:secure_messenger/presentation/screens/profile/user_profile_screen.dart';

import '../support/messenger_test_support.dart';

Map<String, dynamic> message(String id, {String? replyTo, String? content}) => {
  'id': id,
  'chat_id': 'chat',
  'sender_id': 'bob',
  'message_type': 'text',
  'content': content ?? 'Body $id',
  'status': 'read',
  'created_at': '2026-09-07T12:00:00Z',
  'reply_to_id': replyTo,
  if (replyTo != null)
    'reply_to': {
      'id': replyTo,
      'sender_name': 'Bob',
      'content': 'Quoted original',
    },
};

class ChatApiFixture {
  List<Map<String, dynamic>> messages = [
    message('original'),
    message('reply', replyTo: 'original'),
  ];
  final deleted = <String>{};
  final batches = <List<String>>[];
  int fullLoads = 0;
  bool online = true;
  String chatType = 'private';
  Map<String, bool> capabilities = {};
  Completer<http.Response>? nextPoll;
  bool joined = false;
  bool invalidInvite = false;
  int joins = 0;

  Map<String, dynamic> get peer => {
    ...testUser('bob').toJson(),
    'is_online': online,
    'last_seen': '2026-09-07T12:00:00Z',
  };

  Future<http.Response> respond(http.Request request) async {
    final path = request.url.path;
    if (path == '/api/v1/chats/chat/info')
      return jsonResponse({
        'chat_type': chatType,
        'capabilities': capabilities,
        'members_count': 2,
        'my_role': 'member',
        'other_user': chatType == 'private' ? peer : null,
      });
    if (path == '/api/v1/users/bob') return jsonResponse(peer);
    if (path == '/api/v1/users/blocked') return jsonResponse({'users': []});
    if (path.endsWith('/background')) return jsonResponse({'background': null});
    if (path == '/api/v1/messages/search/chat') {
      return jsonResponse({'messages': messages});
    }
    if (path.endsWith('/pinned')) {
      return jsonResponse({'messages': [], 'can_pin': false});
    }
    if (path == '/api/v1/messages/chat') {
      if (request.url.queryParameters.containsKey('from_id')) {
        return jsonResponse({
          'messages': [
            message('original'),
            message('reply', replyTo: 'original'),
          ],
          'has_more': false,
        });
      }
      if (request.url.queryParameters.containsKey('after_id')) {
        final pending = nextPoll;
        nextPoll = null;
        if (pending != null) return pending.future;
        return jsonResponse({'messages': []});
      }
      fullLoads++;
      return jsonResponse({'messages': messages, 'has_more': false});
    }
    if (path == '/api/v1/messages/statuses') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final ids = (body['message_ids'] as List).cast<String>();
      batches.add(ids);
      return jsonResponse({
        'deleted_ids': ids.where(deleted.contains).toList(),
        'statuses': {},
        'viewed_at': {},
      });
    }
    if (path == '/api/v1/messages/chat/chat/read' ||
        path == '/api/v1/messages/chat/group/read')
      return jsonResponse({'ok': true});
    if (path == '/api/v1/chats/') return jsonResponse({'chats': []});
    if (path == '/api/v1/chats/invite-preview' ||
        path == '/api/v1/chats/join') {
      if (invalidInvite)
        return jsonResponse({'error': 'Invalid invite'}, status: 404);
      if (path.endsWith('/join')) {
        joins++;
        joined = true;
      }
      return jsonResponse({
        'id': 'group',
        'chat_type': 'group',
        'title': 'Invited group',
        'members_count': joined ? 2 : 1,
        'is_member': joined,
      });
    }
    if (path == '/api/v1/chats/group/info')
      return jsonResponse({
        'chat_type': 'group',
        'title': 'Invited group',
        'members_count': 2,
        'my_role': 'member',
      });
    if (path == '/api/v1/messages/group')
      return jsonResponse({'messages': [], 'has_more': false});
    throw StateError('Unexpected request: ${request.method} $path');
  }
}

Future<void> openChat(WidgetTester tester) async {
  final auth = AuthNotifier();
  await auth.setLoggedIn(testUser('alice'), 'alice-access', 'alice-refresh');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authNotifierProvider.overrideWith((ref) => auth)],
      child: const MaterialApp(
        home: ChatScreen(chatId: 'chat', title: 'Bob'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = TestStorage();
  late RecordPlatform previousRecord;
  setUpAll(storage.open);
  setUp(() async {
    await storage.reset();
    previousRecord = RecordPlatform.instance;
    RecordPlatform.instance = IdleRecordPlatform();
  });
  tearDown(() => RecordPlatform.instance = previousRecord);
  tearDownAll(storage.close);

  testWidgets(
    'A read incoming deletion and its quote disappear on the next 3-second poll',
    (tester) async {
      final api = ChatApiFixture();
      await http.runWithClient(() async {
        await openChat(tester);
        expect(find.text('Body original'), findsOneWidget);
        expect(find.text('Quoted original'), findsOneWidget);
        api.deleted.add('original');
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(find.text('Body original'), findsNothing);
        expect(find.text('Quoted original'), findsNothing);
        expect(find.text('Body reply'), findsOneWidget);
        expect(find.text('Message unavailable'), findsOneWidget);
        expect(
          api.fullLoads,
          1,
        ); // No route re-entry/full-history reload needed.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }, () => MockClient(api.respond));
    },
  );

  testWidgets(
    'A delayed new-message poll cannot resurrect a confirmed deletion',
    (tester) async {
      final api = ChatApiFixture();
      await http.runWithClient(() async {
        await openChat(tester);
        final pending = Completer<http.Response>();
        api.nextPoll = pending;
        api.deleted.add('original');
        await tester.pump(const Duration(seconds: 3));
        await tester.pump();
        expect(find.text('Body original'), findsNothing);
        pending.complete(
          jsonResponse({
            'messages': [message('original')],
          }),
        );
        await tester.pumpAndSettle();
        expect(find.text('Body original'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }, () => MockClient(api.respond));
    },
  );

  testWidgets(
    'An empty chat has a live profile header and navigates to the correct user',
    (tester) async {
      final api = ChatApiFixture()..messages = [];
      await http.runWithClient(() async {
        await openChat(tester);
        expect(find.text('Online'), findsOneWidget);
        api.online = false;
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(find.text('Online'), findsNothing);
        expect(find.textContaining('Last seen'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('chat-header')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<UserProfileScreen>(find.byType(UserProfileScreen))
              .userId,
          'bob',
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }, () => MockClient(api.respond));
    },
  );

  testWidgets(
    'A deleted reply original clears the composer without erasing the draft',
    (tester) async {
      final api = ChatApiFixture();
      await http.runWithClient(() async {
        await openChat(tester);
        await tester.longPress(find.text('Body original'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reply'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Cancel reply'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'My unsent draft');
        api.deleted.add('original');
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Cancel reply'), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'My unsent draft',
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }, () => MockClient(api.respond));
    },
  );

  testWidgets('Deletion polling stays active inside message search', (
    tester,
  ) async {
    final api = ChatApiFixture();
    await http.runWithClient(() async {
      await openChat(tester);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('جستجو در چت'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Body');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      api.deleted.add('original');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Body original'), findsNothing);
      expect(find.text('Quoted original'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Body',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }, () => MockClient(api.respond));
  });

  testWidgets('Deletion polling stays active in an old reply history window', (
    tester,
  ) async {
    final api = ChatApiFixture()
      ..messages = [message('reply', replyTo: 'original')];
    await http.runWithClient(() async {
      await openChat(tester);
      await tester.tap(find.text('Quoted original'));
      await tester.pumpAndSettle();
      expect(find.text('Back to latest messages'), findsOneWidget);
      expect(find.text('Body original'), findsOneWidget);
      api.deleted.add('original');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Body original'), findsNothing);
      expect(find.text('Back to latest messages'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }, () => MockClient(api.respond));
  });

  testWidgets(
    'Screen polling covers more than one batch of already read messages',
    (tester) async {
      final api = ChatApiFixture()
        ..messages = List.generate(125, (i) => message('m-$i'));
      await http.runWithClient(() async {
        await openChat(tester);
        expect(api.batches.every((ids) => ids.length <= 100), isTrue);
        expect(api.batches.expand((ids) => ids), containsAll(['m-0', 'm-124']));
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }, () => MockClient(api.respond));
    },
  );

  for (final existingMember in [false, true]) {
    testWidgets(
      'Tapping a shared private invite opens its group (member=$existingMember)',
      (tester) async {
        const link =
            'securemessenger://join/550e8400-e29b-41d4-a716-446655440000';
        final api = ChatApiFixture()
          ..messages = [message('invite', content: link)]
          ..joined = existingMember;
        await http.runWithClient(() async {
          await openChat(tester);
          await tester.tap(find.text(link));
          await tester.pumpAndSettle();
          if (!existingMember) {
            expect(find.text('Join group'), findsOneWidget);
            expect(api.joins, 0);
            await tester.tap(find.byKey(const ValueKey('join-invite')));
            await tester.pumpAndSettle();
          }
          expect(find.text('Invited group'), findsOneWidget);
          final screens = tester.widgetList<ChatScreen>(
            find.byType(ChatScreen),
          );
          expect(screens.single.chatId, 'group');
          expect(screens.single.chatType, 'group');
          expect(api.joins, existingMember ? 0 : 1);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }, () => MockClient(api.respond));
      },
    );
  }

  testWidgets(
    'Invalid invitations report an error and leave the current chat open',
    (tester) async {
      const link =
          'securemessenger://join/550e8400-e29b-41d4-a716-446655440000';
      final api = ChatApiFixture()
        ..messages = [message('invite', content: link)]
        ..invalidInvite = true;
      await http.runWithClient(() async {
        await openChat(tester);
        await tester.tap(find.text(link));
        await tester.pumpAndSettle();
        expect(find.textContaining('This invite is invalid'), findsOneWidget);
        expect(
          tester.widget<ChatScreen>(find.byType(ChatScreen)).chatId,
          'chat',
        );
        expect(api.joins, 0);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }, () => MockClient(api.respond));
    },
  );
  for (final type in ['group', 'channel']) {
    testWidgets('$type composer follows live server permissions', (
      tester,
    ) async {
      final api = ChatApiFixture()..chatType = type;
      await http.runWithClient(() async {
        await openChat(tester);
        expect(find.byType(TextField), findsNothing);
        if (type == 'channel') expect(find.text('Mute'), findsOneWidget);
        api.capabilities = {
          'send_messages': true,
          'send_photos': false,
          'send_videos': false,
          'send_voice': false,
        };
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);
        final attach = find.ancestor(
          of: find.byIcon(Icons.attach_file_rounded),
          matching: find.byType(IconButton),
        );
        expect(tester.widget<IconButton>(attach).onPressed, isNull);
        api.capabilities = {'send_messages': false};
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }, () => MockClient(api.respond));
    });
  }
}
