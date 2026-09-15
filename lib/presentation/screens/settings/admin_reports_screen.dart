import 'package:flutter/material.dart';
import '../../../data/services/api_service.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});
  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _api = ApiService();
  List<dynamic> _reports = [];
  bool _loading = true;
  String _filter = 'pending';
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      final vals = ['pending', 'resolved', 'all'];
      setState(() => _filter = vals[_tabs.index]);
      _load();
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get('/reports/', query: {'status': _filter});
      if (!mounted) return;
      setState(() { _reports = res['reports'] as List? ?? []; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _handleUserReport(String reportId, String action) async {
    String? reason;
    if (action == 'limit' || action == 'deactivate') {
      reason = await showDialog<String>(context: context, builder: (ctx) {
        final c = TextEditingController(text: 'نقض قوانین');
        return AlertDialog(
          title: Text(action == 'limit' ? 'محدود کردن کاربر (Telegram: cannot start new chats)' : 'غیرفعال‌سازی حساب'),
          content: TextField(controller: c, decoration: const InputDecoration(hintText: 'دلیل', border: OutlineInputBorder())),
          actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('لغو')), ElevatedButton(onPressed: ()=>Navigator.pop(ctx, c.text), child: const Text('تایید'))],
        );
      });
      if (reason == null) return;
    }
    try {
      await _api.post('/reports/$reportId/handle-user', {'action': action, 'reason': reason, 'duration_days': action=='limit'? 7: null});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(action=='dismiss'? 'گزارش رد شد' : action=='limit'? 'کاربر محدود شد (چت‌های قبلی باقی، چت جدید مسدود)' : 'حساب غیرفعال شد')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _handleChatReport(String reportId, String action) async {
    final reasonCtrl = TextEditingController();
    final reason = action=='dismiss' ? null : await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: Text(action=='suspend'? 'تعلیق': action=='close'? 'بستن': 'حذف'), content: TextField(controller: reasonCtrl, decoration: const InputDecoration(hintText: 'دلیل نمایش به مالک', border: OutlineInputBorder()), autofocus: true), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('لغو')), ElevatedButton(onPressed: ()=>Navigator.pop(ctx, reasonCtrl.text), child: const Text('تایید'))]));
    if (action!='dismiss' && reason==null) return;
    try {
      await _api.post('/reports/$reportId/handle-chat', {'action': action, 'reason': reason});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(action=='dismiss'? 'رد شد' : action=='suspend'? 'گروه/کانال تعلیق شد' : action=='close'? 'بسته شد' : 'حذف شد')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('گزارش‌ها - پنل مدیریت'),
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'در انتظار'), Tab(text: 'حل‌شده'), Tab(text: 'همه')], onTap: (i){ final vals=['pending','resolved','all']; setState(()=>_filter=vals[i]); _load(); }),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _error!=null ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red))) : _reports.isEmpty ? const Center(child: Text('گزارشی یافت نشد')) : RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          itemCount: _reports.length,
          padding: const EdgeInsets.all(12),
          itemBuilder: (_, i){
            final r = _reports[i] as Map<String,dynamic>;
            final type = r['target_type'] as String? ?? '';
            final status = r['status'] as String? ?? '';
            final reason = r['reason'] as String? ?? '';
            final desc = r['description'] as String? ?? '';
            final reporter = r['reporter'] as Map<String,dynamic>?;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: type=='user'? Colors.orange.withValues(alpha:0.12): Colors.purple.withValues(alpha:0.12), borderRadius: BorderRadius.circular(8)), child: Text(type=='user'? 'کاربر': type=='chat'? 'گروه/کانال': 'پیام', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: type=='user'? Colors.orange: Colors.purple))),
                    const SizedBox(width: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: status=='pending'? Colors.amber.withValues(alpha:0.15): Colors.green.withValues(alpha:0.15), borderRadius: BorderRadius.circular(8)), child: Text(status=='pending'? 'در انتظار': status=='resolved'? 'حل‌شده': status, style: TextStyle(fontSize: 11, color: status=='pending'? Colors.amber: Colors.green))),
                    const Spacer(),
                    Text((r['created_at'] as String? ?? '').split('T').first, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ]),
                  const SizedBox(height: 8),
                  Text('دلیل: $reason', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  if (desc.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey))),
                  const SizedBox(height: 8),
                  if (reporter != null) Text('گزارشگر: ${reporter['display_name'] ?? reporter['username'] ?? ''} (@${reporter['username'] ?? ''})', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  if ((r['target_user'] as Map?) != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('کاربر هدف: ${(r['target_user'] as Map)['display_name']} @${(r['target_user'] as Map)['username']}', style: const TextStyle(fontSize: 12, color: Colors.red))),
                  if ((r['target_chat'] as Map?) != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('چت هدف: ${(r['target_chat'] as Map)['title']} (${(r['target_chat'] as Map)['chat_type']})', style: const TextStyle(fontSize: 12, color: Colors.purple))),
                  const Divider(height: 16),
                  if (status=='pending') Wrap(spacing: 8, children: type=='user' ? [
                    ElevatedButton.icon(icon: const Icon(Icons.block, size: 16), label: const Text('محدود (چت جدید مسدود)', style: TextStyle(fontSize: 11)), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), onPressed: ()=>_handleUserReport(r['id'] as String, 'limit')),
                    ElevatedButton.icon(icon: const Icon(Icons.person_off, size: 16), label: const Text('غیرفعال', style: TextStyle(fontSize: 11)), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: ()=>_handleUserReport(r['id'] as String, 'deactivate')),
                    OutlinedButton(onPressed: ()=>_handleUserReport(r['id'] as String, 'dismiss'), child: const Text('رد', style: TextStyle(fontSize: 11))),
                  ] : type=='chat' ? [
                    ElevatedButton.icon(icon: const Icon(Icons.pause_circle_outline, size: 16), label: const Text('تعلیق', style: TextStyle(fontSize: 11)), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), onPressed: ()=>_handleChatReport(r['id'] as String, 'suspend')),
                    ElevatedButton.icon(icon: const Icon(Icons.lock_outline, size: 16), label: const Text('بستن', style: TextStyle(fontSize: 11)), onPressed: ()=>_handleChatReport(r['id'] as String, 'close')),
                    ElevatedButton.icon(icon: const Icon(Icons.delete_forever, size: 16), label: const Text('حذف', style: TextStyle(fontSize: 11)), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: ()=>_handleChatReport(r['id'] as String, 'delete')),
                    OutlinedButton(onPressed: ()=>_handleChatReport(r['id'] as String, 'dismiss'), child: const Text('رد')),
                  ] : [
                    OutlinedButton(onPressed: ()=>_handleUserReport(r['id'] as String, 'dismiss'), child: const Text('رد')),
                  ]) else Text('اقدام: ${r['resolution'] ?? ''} ${r['resolution_reason'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose(){ _tabs.dispose(); super.dispose(); }
}
