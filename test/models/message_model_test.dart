import 'package:flutter_test/flutter_test.dart';
import 'package:secure_messenger/data/models/message_model.dart';
import 'package:secure_messenger/data/models/reply_preview_model.dart';

void main() {
  final base = <String, dynamic>{
    'id': 'reply',
    'chat_id': 'chat',
    'sender_id': 'bob',
    'message_type': 'text',
    'content': 'My reply',
    'created_at': '2026-09-07T12:00:00',
    'reply_to_id': 'original',
    'reply_to': {
      'id': 'original',
      'sender_id': 'alice',
      'sender_name': 'Alice',
      'message_type': 'text',
      'content': 'Original text',
    },
  };

  test('Parses and retains original quote across status updates', () {
    final message = MessageModel.fromJson(base);
    expect(message.replyTo!.content, 'Original text');
    expect(message.replyTo!.senderName, 'Alice');
    final updated = message.copyWith(status: 'read');
    expect(updated.replyTo, message.replyTo);
    expect(updated.replyToId, 'original');
    expect(updated.content, 'My reply');
  });

  test('Old API payloads remain readable without a nested quote', () {
    final old = Map<String, dynamic>.from(base)..remove('reply_to');
    expect(MessageModel.fromJson(old).replyToId, 'original');
    expect(MessageModel.fromJson(old).replyTo, isNull);
  });

  test(
    'Deleted originals discard all private fields, even in malformed payloads',
    () {
      final quote = ReplyPreviewModel.fromJson({
        'id': 'original',
        'is_unavailable': true,
        'content': 'must not show',
        'sender_name': 'must not show',
        'media_url': '/secret',
      });
      expect(quote.isUnavailable, isTrue);
      expect(quote.senderName, isNull);
      expect(quote.content, isNull);
      expect(quote.mediaUrl, isNull);
    },
  );

  test('View-once quotes never carry a thumbnail or caption', () {
    final quote = ReplyPreviewModel.fromJson({
      'id': 'photo',
      'is_view_once': true,
      'content': 'secret caption',
      'media_url': '/api/v1/media/private',
      'message_type': 'image',
    });
    expect(quote.isViewOnce, isTrue);
    expect(quote.content, isNull);
    expect(quote.mediaUrl, isNull);
    final message = MessageModel.fromJson({
      ...base,
      'is_view_once': true,
      'media_url': '/private',
    });
    expect(message.asReplyPreview.content, isNull);
    expect(message.asReplyPreview.mediaUrl, isNull);
  });

  test('View-once and quote changes participate in message equality', () {
    final message = MessageModel.fromJson(base);
    expect(message.copyWith(viewedAt: DateTime(2026, 9, 7)), isNot(message));
    expect(
      message.copyWith(
        replyTo: const ReplyPreviewModel.unavailable('original'),
      ),
      isNot(message),
    );
  });
}
