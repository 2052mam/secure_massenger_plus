import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:secure_messenger/core/utils/api_datetime.dart';
import 'package:secure_messenger/core/utils/chat_list_time.dart';
import 'package:secure_messenger/data/models/chat_model.dart';
import 'package:secure_messenger/data/models/message_model.dart';
import 'package:secure_messenger/data/models/user_model.dart';
import 'package:secure_messenger/data/services/message_reconciler.dart';

void main() {
  test('All API models agree on legacy UTC, Z and explicit offsets', () {
    for (final value in [
      '2026-09-08T10:15:00',
      '2026-09-08T10:15:00Z',
      '2026-09-08T13:45:00+03:30',
      '2026-09-08T06:15:00-0400',
    ]) {
      final expected = DateTime.utc(2026, 9, 8, 10, 15);
      final chat = ChatModel.fromJson({
        'id': 'chat',
        'updated_at': value,
        'last_message': {'created_at': value},
      });
      final message = MessageModel.fromJson({
        'id': 'message',
        'chat_id': 'chat',
        'sender_id': 'alice',
        'created_at': value,
        'viewed_at': value,
      });
      final user = UserModel.fromJson({
        'id': 'alice',
        'username': 'alice',
        'display_name': 'Alice',
        'last_seen': value,
      });
      final sync = MessageSyncResult.fromJson({
        'viewed_at': {'message': value},
      });
      for (final date in [
        parseApiDateTime(value),
        chat.updatedAt,
        chat.lastMessage!.createdAt,
        message.createdAt,
        message.viewedAt,
        user.lastSeen,
        sync.viewedAt['message'],
      ]) {
        expect(date!.toUtc(), expected);
      }
      // Persisting an account must not strip the offset and shift last_seen.
      expect(UserModel.fromJson(user.toJson()).lastSeen!.toUtc(), expected);
    }
  });
  test('Malformed and missing timestamps remain unknown', () {
    for (final value in [null, '', ' ', 'not a time']) {
      expect(parseApiDateTime(value), isNull);
    }
  });
  test('Chat list shows a clock today and a date for older messages', () async {
    await initializeDateFormatting('fa');
    final now = DateTime(2026, 9, 8, 14);
    expect(formatChatListTime(DateTime(2026, 9, 8, 13, 45), now: now), '13:45');
    expect(formatChatListTime(DateTime(2026, 9, 7, 23, 59), now: now), 'Sep 7');
    expect(formatChatListTime(DateTime(2025, 9, 8), now: now), '2025/09/08');
    expect(formatChatListTime(now, now: now, locale: 'fa'), isNotEmpty);
  });
  test('Join privacy defaults, round trips and equality', () {
    final base = {'id': 'alice', 'username': 'alice', 'display_name': 'Alice'};
    final allowed = UserModel.fromJson(base);
    final restricted = UserModel.fromJson({...base, 'allow_group_adds': false});
    expect(allowed.allowGroupAdds, isTrue);
    expect(restricted, isNot(allowed));
    expect(UserModel.fromJson(restricted.toJson()).allowGroupAdds, isFalse);
  });
}
