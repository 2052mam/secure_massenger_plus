import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_messenger/core/constants/api_constants.dart';
import 'package:secure_messenger/data/models/user_model.dart';
import 'package:secure_messenger/presentation/widgets/chat/chat_avatar.dart';
import 'package:secure_messenger/presentation/widgets/chat/chat_header.dart';

Widget host(Widget header, {String locale = 'en'}) => MaterialApp(
  locale: Locale(locale),
  supportedLocales: const [Locale('fa'), Locale('en')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: Scaffold(appBar: AppBar(title: header)),
);

UserModel peer({
  bool online = true,
  bool hidden = false,
  String? photo = '/api/v1/media/bob',
}) => UserModel(
  id: 'bob',
  email: '',
  username: 'bob',
  displayName: 'Bob',
  avatarUrl: photo,
  isOnline: online,
  showLastSeen: !hidden,
  showProfilePhoto: !hidden,
  lastSeen: DateTime.utc(2026, 9, 7, 12),
);

void main() {
  testWidgets(
    'Empty chats show the real peer, authenticated avatar and online status',
    (tester) async {
      var opened = false;
      await tester.pumpWidget(
        host(
          ChatHeader(
            title: 'Old title',
            chatType: 'private',
            otherUser: peer(),
            token: 'test-token',
            onTap: () => opened = true,
          ),
        ),
      );
      expect(
        find.text('Bob'),
        findsWidgets,
      ); // Name plus fallback initial if loading.
      expect(find.text('Online'), findsOneWidget);
      final image =
          tester.widget<CircleAvatar>(find.byType(CircleAvatar)).foregroundImage
              as NetworkImage;
      expect(
        image.url,
        Uri.parse(
          '${ApiConstants.baseUrl}/',
        ).resolve('/api/v1/media/bob').toString(),
      );
      expect(image.headers, {'Authorization': 'Bearer test-token'});
      await tester.tap(find.byKey(const ValueKey('chat-header')));
      expect(opened, isTrue);
    },
  );

  testWidgets(
    'Presence refresh and privacy changes replace the header without reopening',
    (tester) async {
      await tester.pumpWidget(
        host(
          ChatHeader(
            title: 'Bob',
            chatType: 'private',
            otherUser: peer(online: false),
          ),
        ),
      );
      expect(find.textContaining('Last seen'), findsOneWidget);
      expect(find.text('Online'), findsNothing);
      await tester.pumpWidget(
        host(
          ChatHeader(
            title: 'Bob',
            chatType: 'private',
            otherUser: peer(hidden: true),
          ),
        ),
      );
      expect(find.text('Last seen hidden'), findsOneWidget);
      expect(
        tester.widget<CircleAvatar>(find.byType(CircleAvatar)).foregroundImage,
        isNull,
      );
    },
  );

  testWidgets('An external avatar never receives the session bearer token', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ChatAvatar(
          title: 'Bob',
          url: 'https://external.invalid/avatar',
          token: 'secret',
        ),
      ),
    );
    final image =
        tester.widget<CircleAvatar>(find.byType(CircleAvatar)).foregroundImage
            as NetworkImage;
    expect(image.headers, isNull);
  });

  testWidgets(
    'Groups show member counts and use the group action, including RTL',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = false;
      await tester.pumpWidget(
        host(
          ChatHeader(
            title: 'نام یک گروه بسیار طولانی',
            chatType: 'group',
            membersCount: 12,
            onTap: () => opened = true,
          ),
          locale: 'fa',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('12 عضو'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-header')));
      expect(opened, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Invalid or missing avatars retain an initial fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const ChatAvatar(title: 'Bob', url: 'file:///private/file')),
    );
    expect(
      tester.widget<CircleAvatar>(find.byType(CircleAvatar)).foregroundImage,
      isNull,
    );
    expect(find.text('B'), findsOneWidget);
  });
}
