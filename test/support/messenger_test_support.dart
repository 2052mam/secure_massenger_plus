import 'dart:convert';
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secure_messenger/data/models/user_model.dart';
import 'package:secure_messenger/data/services/api_service.dart';
import 'package:secure_messenger/data/services/storage_service.dart';

class TestStorage {
  late Directory directory;

  Future<void> open() async {
    directory = await Directory.systemTemp.createTemp('messenger-regression-');
    Hive.init(directory.path);
    await reset();
  }

  Future<void> reset() async {
    SharedPreferences.setMockInitialValues({
      'locale': 'en',
      'theme_mode': 'light',
    });
    await StorageService.init();
    ApiService().setToken(null);
  }

  Future<void> close() async {
    await Hive.close();
    await directory.delete(recursive: true);
  }
}

UserModel testUser(String id) => UserModel(
  id: id,
  email: '$id@example.test',
  username: id,
  displayName: '${id[0].toUpperCase()}${id.substring(1)}',
);

http.Response jsonResponse(Map<String, dynamic> body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Opening a text-only chat should not need native recorder/codec binaries.
class IdleRecordPlatform extends RecordPlatform {
  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
