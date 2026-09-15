import 'package:flutter_test/flutter_test.dart';
import 'package:secure_messenger/data/models/message_model.dart';
import 'package:secure_messenger/data/models/reply_preview_model.dart';
import 'package:secure_messenger/data/services/message_reconciler.dart';

MessageModel message(
  String id, {
  String type = 'text',
  String sender = 'bob',
  String? replyTo,
  String status = 'read',
}) => MessageModel(
  id: id,
  chatId: 'chat',
  senderId: sender,
  messageType: type,
  content: 'Body $id',
  status: status,
  createdAt: DateTime.utc(2026, 9, 7),
  replyToId: replyTo,
  replyTo: replyTo == null
      ? null
      : ReplyPreviewModel(
          id: replyTo,
          content: 'Original body',
          mediaUrl: '/private-photo',
        ),
);

void main() {
  for (final type in [
    'text',
    'image',
    'video',
    'voice',
    'audio',
    'file',
    'system',
  ]) {
    test(
      'Read/received $type disappears without a new message or re-entry',
      () {
        final reconciler = MessageReconciler();
        final messages = [message('deleted', type: type), message('keep')];
        expect(
          reconciler.batches(messages).expand((ids) => ids),
          contains('deleted'),
        );
        final updated = reconciler.reconcile(
          messages,
          update: const MessageSyncResult(deletedIds: {'deleted'}),
        );
        expect(updated.map((m) => m.id), ['keep']);
        // A late history/poll payload cannot reinsert the deleted bubble.
        expect(reconciler.reconcile(messages).map((m) => m.id), ['keep']);
      },
    );
  }

  test(
    'Deleted originals outside the page are polled and quotes are redacted',
    () {
      final reconciler = MessageReconciler();
      final reply = message('reply', replyTo: 'old-original');
      expect(reconciler.batches([reply]).single, ['reply', 'old-original']);
      final updated = reconciler.reconcile([
        reply,
      ], update: const MessageSyncResult(deletedIds: {'old-original'})).single;
      expect(updated.replyTo!.isUnavailable, isTrue);
      expect(updated.replyTo!.content, isNull);
      expect(updated.replyTo!.mediaUrl, isNull);
      expect(updated.content, 'Body reply');
      expect(
        reconciler.reconcile([reply]).single.replyTo!.isUnavailable,
        isTrue,
      );
    },
  );

  test('All loaded/history/search IDs are batched, not truncated at 100', () {
    final reconciler = MessageReconciler();
    final messages = List.generate(
      205,
      (i) => message('m-$i', replyTo: 'original'),
    );
    final batches = reconciler.batches(
      messages,
      selectedReply: message('composer-original'),
    );
    expect(batches.map((ids) => ids.length), [100, 100, 7]);
    final ids = batches.expand((ids) => ids).toList();
    expect(ids.length, ids.toSet().length);
    expect(ids, containsAll(['m-204', 'original', 'composer-original']));
  });

  test('A clear followed by new messages does not resurrect old content', () {
    final reconciler = MessageReconciler();
    final old = [message('first'), message('second')];
    reconciler.remove(old.map((m) => m.id));
    expect(reconciler.reconcile([...old, message('new')]).map((m) => m.id), [
      'new',
    ]);
  });

  test(
    'Read ticks and view-once consumption cannot regress on a stale poll',
    () {
      final reconciler = MessageReconciler();
      final viewedAt = DateTime.utc(2026, 9, 7, 12);
      final original = message(
        'photo',
      ).copyWith(isViewOnce: true, viewedAt: viewedAt);
      final updated = reconciler.reconcile(
        [original],
        update: MessageSyncResult.fromJson({
          'statuses': {'photo': 'delivered'},
          'viewed_at': {'photo': null},
          'deleted_ids': [],
        }),
      ).single;
      expect(updated.status, 'read');
      expect(updated.viewedAt, viewedAt);
      final delivered = message('sent', status: 'sent');
      expect(
        reconciler
            .reconcile([
              delivered,
            ], update: const MessageSyncResult(statuses: {'sent': 'read'}))
            .single
            .status,
        'read',
      );
    },
  );

  test(
    'A missing legacy field or failed network response is not a deletion',
    () {
      final reconciler = MessageReconciler();
      expect(
        reconciler
            .reconcile([
              message('keep'),
            ], update: MessageSyncResult.fromJson({}))
            .single
            .id,
        'keep',
      );
      expect(reconciler.batches([]), isEmpty);
    },
  );
}
