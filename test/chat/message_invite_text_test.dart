import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_messenger/core/utils/chat_invite_link.dart';
import 'package:secure_messenger/data/models/chat_invite_model.dart';
import 'package:secure_messenger/presentation/widgets/chat/chat_invite_dialog.dart';
import 'package:secure_messenger/presentation/widgets/chat/message_text.dart';

void main() {
  const link = 'securemessenger://join/550e8400-e29b-41d4-a716-446655440000';
  testWidgets(
    'A link embedded in a caption is tappable, without losing long press',
    (tester) async {
      ChatInviteLink? opened;
      var longPresses = 0;
      const text = 'Join here: $link, thanks!';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GestureDetector(
              onLongPress: () => longPresses++,
              child: MessageText(
                text: text,
                onInviteTap: (value) => opened = value,
              ),
            ),
          ),
        ),
      );
      final richText = find.descendant(
        of: find.byType(MessageText),
        matching: find.byType(RichText),
      );
      final paragraph = tester.renderObject<RenderParagraph>(richText);
      final match = ChatInviteLink.findIn(text).single;
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: match.start, extentOffset: match.end),
          )
          .first;
      await tester.tapAt(tester.getTopLeft(richText) + box.toRect().center);
      await tester.pump();
      expect(opened!.value, link);
      opened = null;
      await tester.longPressAt(
        tester.getTopLeft(richText) + box.toRect().center,
      );
      await tester.pump();
      expect(longPresses, 1);
      expect(opened, isNull);
    },
  );

  testWidgets(
    'Replacing linked text disposes recognizers and does not open stale invites',
    (tester) async {
      var opens = 0;
      Widget host(String text) => MaterialApp(
        home: Scaffold(
          body: MessageText(text: text, onInviteTap: (_) => opens++),
        ),
      );
      await tester.pumpWidget(host(link));
      await tester.tap(find.text(link));
      expect(opens, 1);
      await tester.pumpWidget(host('Plain message'));
      await tester.tap(find.text('Plain message'));
      expect(opens, 1);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Invite preview requires an explicit Join confirmation', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Open invite'),
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (_) => const ChatInviteDialog(
                    invite: ChatInviteModel(
                      id: 'group',
                      chatType: 'group',
                      title: 'Private group',
                      membersCount: 4,
                      isMember: false,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open invite'));
    await tester.pumpAndSettle();
    expect(find.text('Private group'), findsOneWidget);
    expect(find.text('4 members'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.byKey(const ValueKey('join-invite')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
