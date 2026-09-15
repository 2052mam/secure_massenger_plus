import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secure_messenger/data/services/api_service.dart';
import 'package:secure_messenger/data/services/presence_service.dart';

import '../support/messenger_test_support.dart';

void main() {
  testWidgets(
    'Foreground heartbeats pause in the background and keep the original account token',
    (tester) async {
      final states = <bool>[];
      final tokens = <String?>[];
      final client = MockClient((request) async {
        states.add((jsonDecode(request.body) as Map)['is_online'] as bool);
        tokens.add(request.headers['authorization']);
        return jsonResponse({'ok': true});
      });
      await http.runWithClient(() async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final presence = PresenceService(ApiService.withToken('alice-access'))
          ..start();
        await tester.pump();
        expect(states, [true]);
        await tester.pump(const Duration(seconds: 15));
        expect(states, [true, true]);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(states.last, isFalse);
        final count = states.length;
        await tester.pump(const Duration(seconds: 30));
        expect(states.length, count);
        ApiService().setToken('bob-access');
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(states.last, isTrue);
        presence.dispose();
        await tester.pump();
        expect(states.last, isFalse);
        expect(tokens.every((token) => token == 'Bearer alice-access'), isTrue);
        final stopped = states.length;
        await tester.pump(const Duration(seconds: 30));
        expect(states.length, stopped);
        ApiService().setToken(null);
      }, () => client);
    },
  );
}
