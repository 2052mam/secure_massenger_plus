import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'storage_service.dart';

class DeviceService {
  static final _uuid = Uuid();

  static Future<Map<String, dynamic>> getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    String deviceId = StorageService.getDeviceId() ?? _uuid.v4();
    await StorageService.saveDeviceId(deviceId);

    String model = 'Unknown';
    String os = 'Unknown';
    String deviceName = 'Unknown';
    String? mac;

    try {
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        model = android.model;
        os = 'Android ${android.version.release}';
        deviceName = android.device;
        // MAC is restricted on modern Android; we use androidId as strong fingerprint component
        mac = android.id;
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        model = ios.utsname.machine;
        os = '${ios.systemName} ${ios.systemVersion}';
        deviceName = ios.name;
        mac = ios.identifierForVendor;
      }
    } catch (_) {}

    return {
      'device_id': deviceId,
      'model': model,
      'os': os,
      'device_name': deviceName,
      'mac_address': mac,
      'app_version': '1.0.0',
    };
  }
}
