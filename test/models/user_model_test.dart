import 'package:flutter_test/flutter_test.dart';
import 'package:secure_messenger/data/models/user_model.dart';

void main() {
  final base = <String, dynamic>{
    'id': 'bob',
    'username': 'bob',
    'display_name': 'Bob',
  };

  test('Legacy naive last_seen is UTC, not the phone timezone', () {
    for (final value in [
      '2026-09-07T12:30:00',
      '2026-09-07T12:30:00Z',
      '2026-09-07T16:00:00+03:30',
    ]) {
      final user = UserModel.fromJson({...base, 'last_seen': value});
      expect(user.lastSeen!.toUtc(), DateTime.utc(2026, 9, 7, 12, 30));
    }
  });

  test('Avatar and presence/privacy changes participate in equality', () {
    final user = UserModel.fromJson(base);
    for (final update in [
      {'avatar_url': '/api/v1/media/new-avatar'},
      {'is_online': true},
      {'show_last_seen': false},
      {'show_profile_photo': false},
      {'bio': 'New bio'},
    ]) {
      expect(UserModel.fromJson({...base, ...update}), isNot(user));
    }
  });

  test('Hidden/missing timestamps stay unknown', () {
    expect(UserModel.fromJson(base).lastSeen, isNull);
    expect(
      UserModel.fromJson({...base, 'last_seen': 'invalid'}).lastSeen,
      isNull,
    );
  });
}
