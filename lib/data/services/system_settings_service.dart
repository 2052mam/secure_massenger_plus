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

  /// Opens this app's system App Info page (hosts "Pause app activity if
  /// unused" and the battery/autostart-adjacent toggles on every ROM).
  static Future<bool> openAppInfo() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openAppInfo') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// True when "Pause app activity if unused" is OFF for us. When it is ON,
  /// Android (and especially Xiaomi/Huawei/Oppo) may freeze the keep-alive
  /// service after swipe-away and killed-app notifications stop.
  static Future<bool> isHibernationExempt() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('isHibernationExempt') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Best-effort programmatic exemption. Returns the resulting state —
  /// false means the ROM refused and the user must flip the toggle in
  /// App Info manually (see [openAppInfo]).
  static Future<bool> setHibernationExempt() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('setHibernationExempt') ??
          false;
    } catch (_) {
      return false;
    }
  }
}
