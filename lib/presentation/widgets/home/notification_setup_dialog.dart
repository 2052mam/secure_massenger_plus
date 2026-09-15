import 'package:flutter/material.dart';

import '../../../data/services/connection_service.dart';
import '../../../data/services/system_settings_service.dart';

/// One-time, Telegram-style notification setup checklist. Shown once after
/// login when something that killed-app delivery needs is still missing.
/// Every row re-checks live, so the user watches items flip green.
Future<void> showNotificationSetupDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _NotificationSetupDialog(),
  );
}

class _NotificationSetupDialog extends StatefulWidget {
  const _NotificationSetupDialog();

  @override
  State<_NotificationSetupDialog> createState() =>
      _NotificationSetupDialogState();
}

class _NotificationSetupDialogState extends State<_NotificationSetupDialog> {
  bool? _batteryExempt;
  bool? _hibernationExempt;
  bool _busyBattery = false;
  bool _busyHibernation = false;
  bool _hibernationRefused = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final battery = await ConnectionService.isBatteryExempt;
    final hibernation = await SystemSettingsService.isHibernationExempt();
    if (!mounted) return;
    setState(() {
      _batteryExempt = battery;
      _hibernationExempt = hibernation;
    });
  }

  Future<void> _fixBattery() async {
    setState(() => _busyBattery = true);
    await ConnectionService.requestBatteryExemption();
    await Future.delayed(const Duration(seconds: 1));
    await _refresh();
    if (mounted) setState(() => _busyBattery = false);
  }

  Future<void> _fixHibernation() async {
    setState(() {
      _busyHibernation = true;
      _hibernationRefused = false;
    });
    final ok = await SystemSettingsService.setHibernationExempt();
    await _refresh();
    if (!mounted) return;
    setState(() {
      _busyHibernation = false;
      _hibernationRefused = !ok;
    });
    if (!ok && mounted) {
      // The ROM refused the programmatic fix: take the user straight to
      // App Info where the toggle lives.
      await SystemSettingsService.openAppInfo();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'گزینه «توقف فعالیت برنامه در صورت عدم استفاده» را خاموش کنید.',
          ),
        ),
      );
      await _refresh();
    }
  }

  Future<void> _openAutoStart() async {
    await SystemSettingsService.openAutoStartSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'در تنظیمات بازشده، «شروع خودکار» را برای SecureMessenger فعال کنید.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اعلان پایدار مثل تلگرام'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'برای اینکه پیام‌ها حتی با بسته بودن کامل برنامه برسند، '
              'این ۳ مورد را کامل کنید:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            _SetupRow(
              done: _batteryExempt,
              busy: _busyBattery,
              icon: Icons.battery_saver_outlined,
              title: 'فعالیت در پس‌زمینه (باتری)',
              hint: 'بدون آن، گوشی اتصال را در حالت خواب می‌بندد.',
              actionLabel: 'فعال‌سازی',
              onAction: _fixBattery,
            ),
            _SetupRow(
              done: _hibernationExempt,
              busy: _busyHibernation,
              icon: Icons.pause_circle_outline,
              title: 'عدم توقف خودکار برنامه',
              hint: _hibernationRefused
                  ? 'گوشی اجازه خودکار نداد — در صفحه تنظیمات، گزینه «توقف فعالیت برنامه در صورت عدم استفاده» را خاموش کنید.'
                  : 'اگر روشن بماند، اندروید اتصال را بعد از بستن برنامه می‌بندد.',
              actionLabel:
                  _hibernationRefused ? 'باز کردن تنظیمات' : 'رفع خودکار',
              onAction: _fixHibernation,
            ),
            _SetupRow(
              done: null, // Not detectable: always a manual step.
              busy: false,
              icon: Icons.rocket_launch_outlined,
              title: 'شروع خودکار (شیائومی/هواوی/...)',
              hint: 'تا اتصال بعد از بستن برنامه و ری‌استارت گوشی زنده بماند.',
              actionLabel: 'باز کردن',
              onAction: _openAutoStart,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('انجام شد'),
        ),
      ],
    );
  }
}

class _SetupRow extends StatelessWidget {
  final bool? done;
  final bool busy;
  final IconData icon;
  final String title;
  final String hint;
  final String actionLabel;
  final Future<void> Function() onAction;

  const _SetupRow({
    required this.done,
    required this.busy,
    required this.icon,
    required this.title,
    required this.hint,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = done == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: done == null && !busy
                ? Icon(icon, color: Colors.blue, size: 22)
                : busy || done == null
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        resolved
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: resolved ? Colors.green : Colors.orange,
                        size: 22,
                      ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  hint,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          if (!resolved)
            TextButton(
              onPressed: busy ? null : onAction,
              child: Text(actionLabel),
            ),
        ],
      ),
    );
  }
}
