import 'dart:io';

import 'package:flutter/services.dart';

/// Opens OEM-specific system screens (autostart / battery) that Flutter
/// plugins don't cover. The native side lives in MainActivity.
class SystemSettingsService {
  static const _channel = MethodChannel('secure_messenger/system');

  /// Opens the vendor's autostart manager (Xiaomi/Huawei/Oppo/Vivo/...)
  /// so the user can allow SecureMessenger to start in the background.
  /// Falls back to the app-details settings page. Returns false when
  /// nothing could be opened.
  static Future<bool> openAutoStartSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openAutoStartSettings') ??
          false;
    } catch (_) {
      return false;
    }
  }
}
