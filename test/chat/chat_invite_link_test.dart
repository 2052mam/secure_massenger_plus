import 'package:flutter_test/flutter_test.dart';
import 'package:secure_messenger/core/utils/chat_invite_link.dart';

void main() {
  const legacy = 'securemessenger://join/550e8400-e29b-41d4-a716-446655440000';
  const signed =
      'securemessenger://join/eyJjaGF0X2lkIjoiZ3JvdXAifQ.ABC_def-123';
  for (final link in [
    legacy,
    signed,
    'securemessenger://public/my_group',
    'https://t.me/my_group',
    'http://t.me/my_group',
    't.me/my_group',
  ]) {
    test('Recognizes an in-app invitation: $link', () {
      final parsed = ChatInviteLink.tryParse(link);
      expect(parsed, isNotNull);
      expect(parsed!.value, link.startsWith('t.me/') ? 'https://$link' : link);
    });
  }

  test(
    'Multiple links in Persian/English captions retain surrounding punctuation',
    () {
      const text = 'Join ($signed), یا این لینک: $legacy، سپس t.me/my_group.';
      final matches = ChatInviteLink.findIn(text).toList();
      expect(matches.length, 3);
      expect(matches.map((m) => text.substring(m.start, m.end)), [
        signed,
        legacy,
        't.me/my_group',
      ]);
    },
  );

  test('RTL formatting markers are not sent as part of the invite', () {
    final text = '\u2066$legacy\u2069';
    expect(ChatInviteLink.findIn(text).single.link.value, legacy);
  });

  for (final text in [
    'https://evil.test/my_group',
    'https://t.me.evil.test/my_group',
    'https://bob@t.me/my_group',
    'https://t.me:99/my_group',
    'securemessenger://join/',
    'securemessenger://join/id/extra',
    'securemessenger://join/id?token=another',
    'securemessenger://join/id#fragment',
    'securemessenger://public/a',
    't.me/my_group/extra',
  ]) {
    test('Rejects unsupported or malformed URL: $text', () {
      expect(ChatInviteLink.tryParse(text), isNull);
    });
  }

  test(
    'A similar domain or nested external URL does not become an invitation',
    () {
      for (final text in [
        'evil.t.me/my_group',
        'https://evil.test/t.me/my_group',
        'notsecuremessenger://join/id',
      ]) {
        expect(ChatInviteLink.findIn(text), isEmpty);
      }
    },
  );
}
