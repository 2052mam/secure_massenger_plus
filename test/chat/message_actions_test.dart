import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_messenger/data/models/message_model.dart';
import 'package:secure_messenger/presentation/widgets/chat/message_actions_sheet.dart';

MessageModel message({
  String type = 'text',
  String? content = '  سلام 👋\nHello, world!  ',
  bool once = false,
}) => MessageModel(
  id: 'message',
  chatId: 'chat',
  senderId: 'bob',
  messageType: type,
  content: content,
  createdAt: DateTime.utc(2026, 9, 7),
  isViewOnce: once,
);

Future<void> showActions(
  WidgetTester tester,
  MessageModel value, {
  bool canDelete = false,
  String locale = 'en',
  ValueChanged<bool>? onDelete,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      supportedLocales: const [Locale('en'), Locale('fa')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            child: const Text('Actions'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => MessageActionsSheet(
                message: value,
                canDeleteForAll: canDelete,
                onReply: () {},
                onForward: () {},
                onDelete: onDelete ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Actions'));
  await tester.pumpAndSettle();
}

void main() {
  for (final type in ['text', 'image', 'video', 'voice', 'file']) {
    testWidgets('Copies exact $type body/caption without metadata', (
      tester,
    ) async {
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData')
          copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final value = message(type: type);
      await showActions(tester, value);
      await tester.tap(find.byKey(const ValueKey('copy-message')));
      await tester.pumpAndSettle();
      expect(copied, value.content);
      expect(find.text('Text copied'), findsOneWidget);
      expect(find.byType(MessageActionsSheet), findsNothing);
    });
  }

  testWidgets(
    'Persian copy action works for outgoing as well as received messages',
    (tester) async {
      await showActions(tester, message(), canDelete: true, locale: 'fa');
      expect(find.text('کپی متن'), findsOneWidget);
      expect(find.text('حذف برای همه'), findsOneWidget);
    },
  );

  testWidgets('View-once and captionless media never offer Copy', (
    tester,
  ) async {
    await showActions(
      tester,
      message(type: 'image', once: true, content: 'private caption'),
    );
    expect(find.byKey(const ValueKey('copy-message')), findsNothing);
    expect(find.text('Forward'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await showActions(tester, message(type: 'image', content: '   '));
    expect(find.byKey(const ValueKey('copy-message')), findsNothing);
  });

  testWidgets('Existing deletion actions keep their separate scope', (
    tester,
  ) async {
    bool? forAll;
    await showActions(
      tester,
      message(),
      canDelete: true,
      onDelete: (value) => forAll = value,
    );
    await tester.tap(find.text('Delete for everyone'));
    await tester.pumpAndSettle();
    expect(forAll, isTrue);
    await showActions(tester, message(), onDelete: (value) => forAll = value);
    expect(find.text('Delete for everyone'), findsNothing);
    await tester.tap(find.text('Delete for me'));
    await tester.pumpAndSettle();
    expect(forAll, isFalse);
  });
}
