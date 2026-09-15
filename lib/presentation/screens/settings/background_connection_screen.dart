import 'dart:io';

import 'package:flutter/material.dart';

import '../../../data/services/connection_service.dart';
import '../../../data/services/system_settings_service.dart';

/// Telegram-style background-connection settings: the keep-alive service
/// plus the two system exemptions (battery + autostart) that decide whether
/// notifications arrive after the app is swiped away — no FCM involved.
class BackgroundConnectionScreen extends StatefulWidget {
  const BackgroundConnectionScreen({super.key});

  @override
  State<BackgroundConnectionScreen> createState() =>
      _BackgroundConnectionScreenState();
}

class _BackgroundConnectionScreenState
    extends State<BackgroundConnectionScreen> {
  bool _enabled = true;
  bool _running = false;
  bool _batteryExempt = false;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final enabled = await ConnectionService.isEnabled();
    final running = await ConnectionService.isRunning;
    final exempt = await ConnectionService.isBatteryExempt;
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _running = running;
      _batteryExempt = exempt;
      _loaded = true;
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _enabled = value;
      _busy = true;
    });
    await ConnectionService.setEnabled(value);
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _fixBattery() async {
    await ConnectionService.requestBatteryExemption();
    // The system dialog resolves asynchronously; re-read on return.
    await Future.delayed(const Duration(seconds: 1));
    await _refresh();
  }

  Future<void> _openAutoStart() async {
    final opened = await SystemSettingsService.openAutoStartSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'در تنظیمات بازشده، «شروع خودکار» را برای SecureMessenger فعال کنید.'
              : 'باز کردن تنظیمات ممکن نشد. لطفاً دستی در تنظیمات گوشی اجازه شروع خودکار بدهید.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final healthy = _enabled && _running && _batteryExempt;
    return Scaffold(
      appBar: AppBar(title: const Text('اتصال پس‌زمینه')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: healthy
                        ? Colors.green.withValues(alpha: 0.08)
                        : Colors.orange.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            healthy
                                ? Icons.check_circle_outline
                                : Icons.warning_amber_outlined,
                            color: healthy ? Colors.green : Colors.orange,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              healthy
                                  ? 'اتصال پس‌زمینه فعال است. پیام‌ها حتی با بسته بودن برنامه می‌رسند.'
                                  : 'برای دریافت پیام وقتی برنامه بسته است، موارد زیر را کامل کنید.',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!Platform.isAndroid)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'سرویس نگه‌دارنده اتصال مخصوص اندروید است.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  SwitchListTile(
                    secondary: const Icon(Icons.sync_outlined),
                    title: const Text('اتصال پس‌زمینه'),
                    subtitle: const Text(
                      'سرویس سبک نگه‌دارنده (مثل تلگرام) — با اعلان دائمی «متصل». خاموش = اعلان فقط در بازه‌های ~۱۵ دقیقه‌ای.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _enabled,
                    onChanged: _busy ? null : _toggle,
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(
                      _running
                          ? Icons.play_circle_outline
                          : Icons.pause_circle_outline,
                      color: _running ? Colors.green : Colors.grey,
                    ),
                    title: const Text('وضعیت سرویس'),
                    subtitle: Text(
                      _running ? 'در حال اجرا' : 'متوقف شده',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: _refresh,
                            child: const Text('به‌روزرسانی'),
                          ),
                  ),
                  ListTile(
                    leading: Icon(
                      _batteryExempt
                          ? Icons.battery_saver_outlined
                          : Icons.battery_alert_outlined,
                      color: _batteryExempt ? Colors.green : Colors.orange,
                    ),
                    title: const Text('معافیت از بهینه‌سازی باتری'),
                    subtitle: Text(
                      _batteryExempt
                          ? 'فعال است — اتصال در حالت خواب گوشی هم کار می‌کند.'
                          : 'لازم است — بدون آن، شیائومی/هواوی اتصال را در خواب می‌بندند.',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: _batteryExempt
                        ? const Icon(Icons.check,
                            color: Colors.green, size: 20)
                        : FilledButton.tonal(
                            onPressed: _fixBattery,
                            child: const Text('فعال‌سازی'),
                          ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.rocket_launch_outlined,
                        color: Colors.blue),
                    title: const Text('شروع خودکار (Autostart)'),
                    subtitle: const Text(
                      'در گوشی‌های شیائومی/هواوی/اوپو/ویوو: اجازه شروع خودکار تا اتصال بعد از بستن برنامه زنده بماند.',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: _openAutoStart,
                      child: const Text('باز کردن'),
                    ),
                  ),
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'نکته باتری: این اتصال هر ~۲۰ ثانیه یک بررسی سبک انجام می‌دهد؛ مصرف آن در حد نگه‌داشتن اتصال تلگرام است. بدون هیچ سرور پوش (گوگل/اپل) کار می‌کند، پس تحریم و فیلترینگ اثری روی آن ندارد.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
