import 'package:flutter/material.dart';
import '../../../data/services/api_service.dart';

class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen({super.key});
  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  final _api = ApiService();
  List<dynamic> _devices = [];
  List<dynamic> _notifications = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get('/devices/');
      final notifRes = await _api.get('/devices/notifications');
      if (!mounted) return;
      setState(() {
        _devices = res['devices'] as List? ?? [];
        _notifications = notifRes['messages'] is List ? notifRes['messages'] as List : (notifRes['notifications'] as List? ?? []);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _terminate(String deviceId) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('پایان نشست'), content: const Text('این دستگاه از حساب خارج شود؟'), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('لغو')), TextButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('تایید', style: TextStyle(color: Colors.red))) ]));
    if (confirm != true) return;
    try {
      await _api.post('/devices/$deviceId/terminate', {});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نشست پایان یافت')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _terminateOthers() async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('پایان همه نشست‌های دیگر'), content: const Text('همه دستگاه‌ها به‌جز دستگاه فعلی خارج شوند؟ (مانند تلگرام)'), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('لغو')), TextButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('پایان همه', style: TextStyle(color: Colors.red))) ]));
    if (confirm != true) return;
    try {
      await _api.post('/devices/terminate-others', {});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نشست‌های دیگر پایان یافت')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دستگاه‌ها و نشست‌ها'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, style: const TextStyle(color: Colors.red)), ElevatedButton(onPressed: _load, child: const Text('تلاش مجدد'))])) : RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const Icon(Icons.devices, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('این دستگاه', style: Theme.of(context).textTheme.titleMedium),
                    const Text('نشست فعلی شما - مانند تلگرام همیشه فعال است', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ])),
                  Text('${_devices.length} دستگاه', style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            if (_notifications.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('هشدارهای امنیتی (پیام ذخیره‌شده مانند تلگرام)', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              ..._notifications.take(5).map((n) => Card(
                color: Colors.amber.withValues(alpha: 0.08),
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  title: Text((n['content'] as String?)?.split('\n').first ?? 'ورود جدید', style: const TextStyle(fontSize: 13)),
                  subtitle: Text((n['created_at'] ?? '').toString(), style: const TextStyle(fontSize: 11)),
                  isThreeLine: false,
                ),
              )),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Text('همه نشست‌های فعال', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (_devices.length > 1)
                TextButton.icon(icon: const Icon(Icons.power_settings_new, size: 18, color: Colors.red), label: const Text('پایان همه نشست‌های دیگر', style: TextStyle(color: Colors.red, fontSize: 12)), onPressed: _terminateOthers),
            ]),
            const SizedBox(height: 8),
            ..._devices.map((d) {
              final isCurrent = d['is_current'] == true;
              final lastActive = d['last_active_at'] as String?;
              return Card(
                color: isCurrent ? Colors.blue.withValues(alpha: 0.06) : null,
                child: ListTile(
                  leading: Icon(d['device_type'] == 'mobile' ? Icons.phone_android : d['device_type'] == 'desktop' ? Icons.computer : Icons.devices, color: isCurrent ? Colors.blue : Colors.grey),
                  title: Row(children: [
                    Expanded(child: Text((d['device_name'] ?? d['device_model'] ?? 'ناشناس') as String, style: TextStyle(fontWeight: isCurrent? FontWeight.w600:FontWeight.normal))),
                    if (isCurrent) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)), child: const Text('فعلی', style: TextStyle(color: Colors.green, fontSize: 11)))
                  ]),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('IP: ${d['ip_address'] ?? '-'} • ${(d['device_model'] ?? '')} ${(d['os'] ?? '')} - ${d['app_version'] ?? ''}', style: const TextStyle(fontSize: 11)),
                    if (lastActive != null)
                      Text('آخرین فعالیت: $lastActive', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ]),
                  trailing: isCurrent ? null : IconButton(icon: const Icon(Icons.logout, color: Colors.red), onPressed: ()=>_terminate(d['id'] as String)),
                ),
              );
            }),
            if (_devices.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('دستگاهی یافت نشد'))),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8)),
              child: const Row(children: [
                Icon(Icons.info_outline, size: 18, color: Colors.blue),
                SizedBox(width: 8),
                Expanded(child: Text('مانند تلگرام: در صورت ورود با دستگاه جدید، هشداری در «پیام‌های ذخیره‌شده» مشاهده می‌کنید و می‌توانید نشست را ببندید.', style: TextStyle(fontSize: 12, color: Colors.grey))),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
