import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secure_messenger/data/models/user_model.dart';
import 'package:secure_messenger/data/services/api_service.dart';
import 'package:secure_messenger/presentation/providers/auth_provider.dart';
import 'package:secure_messenger/presentation/screens/profile/profile_screen.dart';
import 'package:secure_messenger/presentation/widgets/chat/chat_avatar.dart';
import 'package:secure_messenger/presentation/widgets/chat/join_privacy_tile.dart';

class ProfileApi extends ApiService {
  ProfileApi() : super.withToken('alice');
  Map<String, dynamic> user = {
    'id': 'alice',
    'username': 'alice',
    'display_name': 'Alice',
    'avatar_url': 'https://example.invalid/avatar',
    'allow_group_adds': true,
  };
  final writes = <Map<String, dynamic>>[];
  bool fail = false;
  @override
  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (fail) throw ApiException(statusCode: 500, message: 'Could not save');
    writes.add(body);
    user = {...user, ...body};
    return user;
  }
}

class ProfileAuth extends AuthNotifier {
  ProfileAuth(this.api) {
    state = AsyncValue.data(UserModel.fromJson(api.user));
  }
  final ProfileApi api;
  @override
  Future<void> checkSession() async {
    state = AsyncValue.data(UserModel.fromJson(api.user));
  }
}

Widget host(Widget child, ProfileApi api) => ProviderScope(
  overrides: [
    authNotifierProvider.overrideWith((ref) => ProfileAuth(api)),
    authenticatedSessionProvider.overrideWith(
      (ref) => (userId: 'alice', token: 'alice', api: api),
    ),
  ],
  child: MaterialApp(home: child),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'locale': 'en'}));
  testWidgets(
    'Remove photo confirms, writes null, refreshes and shows initials',
    (tester) async {
      final api = ProfileApi();
      await tester.pumpWidget(host(const ProfileScreen(), api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remove-profile-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.writes, isEmpty);
      await tester.tap(find.byKey(const ValueKey('remove-profile-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(api.writes.single, {'avatar_url': null});
      expect(find.byKey(const ValueKey('remove-profile-photo')), findsNothing);
      expect(tester.widget<ChatAvatar>(find.byType(ChatAvatar)).url, isNull);
      expect(find.text('Alice'), findsWidgets);
    },
  );
  testWidgets('Join privacy updates only after successful server save', (
    tester,
  ) async {
    final api = ProfileApi();
    await tester.pumpWidget(host(const Scaffold(body: JoinPrivacyTile()), api));
    await tester.pumpAndSettle();
    api.fail = true;
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(find.text('Could not save'), findsOneWidget);
    api.fail = false;
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(api.writes.single, {'allow_group_adds': false});
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
  });
}
