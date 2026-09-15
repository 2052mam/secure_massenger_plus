import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_messenger/data/models/message_model.dart';
import 'package:secure_messenger/data/models/reply_preview_model.dart';
import 'package:secure_messenger/presentation/widgets/chat/message_bubble.dart';
import 'package:secure_messenger/presentation/widgets/chat/reply_preview.dart';

Widget host(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    MaterialApp(
      home: Scaffold(
        body: Directionality(
          textDirection: direction,
          child: Center(child: child),
        ),
      ),
    );

MessageModel message({bool once = false}) => MessageModel(
  id: 'reply',
  chatId: 'chat',
  senderId: 'bob',
  messageType: once ? 'image' : 'text',
  content: once ? '' : 'Here is my response',
  createdAt: DateTime(2026, 9, 7),
  isViewOnce: once,
  replyToId: once ? null : 'original',
  replyTo: once
      ? null
      : const ReplyPreviewModel(
          id: 'original',
          senderId: 'alice',
          senderName: 'Alice',
          content: 'Original quoted text',
        ),
);

void main() {
  testWidgets(
    'Reply bubble displays the original author and text, and is tappable',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          MessageBubble(
            message: message(),
            isMine: true,
            currentUserId: 'bob',
            mediaUrl: '',
            onReplyTap: () => taps++,
          ),
        ),
      );
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Original quoted text'), findsOneWidget);
      expect(find.text('Here is my response'), findsOneWidget);
      await tester.tap(find.text('Original quoted text'));
      expect(taps, 1);
    },
  );

  testWidgets(
    'Media quotes have useful labels and unavailable originals are not clickable',
    (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 240,
            child: ReplyPreview(
              reply: ReplyPreviewModel(
                id: 'voice',
                senderId: 'bob',
                senderName: 'Bob',
                messageType: 'voice',
              ),
              currentUserId: 'bob',
            ),
          ),
        ),
      );
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Voice message'), findsOneWidget);
      var taps = 0;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 240,
            child: ReplyPreview(
              reply: const ReplyPreviewModel.unavailable('deleted'),
              onTap: () => taps++,
            ),
          ),
        ),
      );
      expect(find.text('Message unavailable'), findsOneWidget);
      await tester.tap(find.text('Message unavailable'));
      expect(taps, 0);
    },
  );

  testWidgets('RTL replies lay out without overflow on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(
        MessageBubble(message: message(), isMine: false, mediaUrl: ''),
        direction: TextDirection.rtl,
      ),
    );
    expect(find.text('Original quoted text'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'View-once tap opens a viewer callback, never a cached thumbnail',
    (tester) async {
      var opens = 0;
      final photo = message(once: true);
      await tester.pumpWidget(
        host(
          MessageBubble(
            message: photo,
            isMine: false,
            mediaUrl: 'https://example.invalid/private',
            onOpenViewOnce: () => opens++,
          ),
        ),
      );
      expect(find.text('Tap to open'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
      await tester.tap(find.text('Tap to open'));
      expect(opens, 1);
      expect(find.text('Photo viewed'), findsNothing);
      await tester.pumpWidget(
        host(
          MessageBubble(
            message: photo.copyWith(viewedAt: DateTime(2026, 9, 7)),
            isMine: false,
            mediaUrl: '',
            onOpenViewOnce: () => opens++,
          ),
        ),
      );
      await tester.tap(find.text('Photo viewed'));
      expect(opens, 1);
    },
  );

  testWidgets('Sender cannot consume their own view-once photo', (
    tester,
  ) async {
    var opens = 0;
    await tester.pumpWidget(
      host(
        MessageBubble(
          message: message(once: true),
          isMine: true,
          mediaUrl: '',
          onOpenViewOnce: () => opens++,
        ),
      ),
    );
    expect(find.text('Only the recipient can open'), findsOneWidget);
    await tester.tap(find.text('View-once photo'));
    expect(opens, 0);
  });
}
