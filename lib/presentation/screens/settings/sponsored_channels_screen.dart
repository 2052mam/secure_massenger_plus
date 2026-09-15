import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';

/// General-admin screen: sponsor / unsponsor any channel.
class SponsoredChannelsScreen extends ConsumerStatefulWidget {
  const SponsoredChannelsScreen({super.key});
  @override
  ConsumerState<SponsoredChannelsScreen> createState() => _SponsoredChannelsScreenState();
}

class _SponsoredChannelsScreenState extends ConsumerState<SponsoredChannelsScreen> {
  List<Map<String, dynamic>> _channels = [];
  List<Map<String, dynamic>> _sponsored = [];
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(authenticatedSessionProvider).api;
      final chatsRes = await api.get('/admin/chats', query: {'per_page': '100'});
      final sponsoredRes = await api.get('/admin/sponsored');
      if (!mounted) return;
      final all = (chatsRes['chats'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
      setState(() {
        _channels = all.where((c) => c['chat_type'] == 'channel').toList();
        _sponsored = (sponsoredRes['channels'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _toggle(Map<String, dynamic> channel, bool sponsor) async {
    try {
      final api = ref.read(authenticatedSessionProvider).api;
      await api.post("/admin/chats/${channel['id']}/sponsor", {'is_sponsored': sponsor});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sponsor ? 'کانال اسپانسر شد' : 'اسپانسر حذف شد')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sponsoredIds = _sponsored.map((c) => c['id'] as String).toSet();
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _channels
        : _channels.where((c) =>
            ((c['title'] as String?) ?? '').toLowerCase().contains(q) ||
            ((c['username'] as String?) ?? '').toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('کانال‌های اسپانسرشده (مدیر کل)')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: _load, child: const Text('تلاش مجدد')),
                    ]),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
                          ),
                          child: const Row(children: [
                            Icon(Icons.info_outline, color: Colors.amber, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'فقط مدیر کل برنامه می‌تواند کانال‌ها را اسپانسر کند. کانال‌های اسپانسرشده برای همه کاربران نمایش داده می‌شوند.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _searchCtrl,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'جستجوی کانال...',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('اسپانسرشده‌ها (${_sponsored.length})',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        if (_sponsored.isEmpty)
                          const Text('هنوز کانالی اسپانسر نشده است',
                              style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ..._sponsored.map((c) => Card(
                              child: ListTile(
                                leading: const CircleAvatar(child: Icon(Icons.campaign_outlined, size: 18)),
                                title: Text((c['title'] as String?) ?? 'کانال'),
                                subtitle: Text((c['username'] as String?)?.isNotEmpty == true
                                    ? '@${c['username']}'
                                    : 'بدون آیدی'),
                                trailing: TextButton(
                                  onPressed: () => _toggle(c, false),
                                  child: const Text('حذف اسپانسر', style: TextStyle(color: Colors.red)),
                                ),
                              ),
                            )),
                        const SizedBox(height: 12),
                        Text('همه کانال‌ها (${filtered.length})',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        ...filtered.map((c) {
                          final isSponsored = sponsoredIds.contains(c['id']) || c['is_sponsored'] == true;
                          return Card(
                            child: SwitchListTile(
                              secondary: const CircleAvatar(child: Icon(Icons.campaign_outlined, size: 18)),
                              title: Text((c['title'] as String?) ?? 'کانال',
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text((c['username'] as String?)?.isNotEmpty == true
                                  ? '@${c['username']}'
                                  : 'بدون آیدی'),
                              value: isSponsored,
                              onChanged: (v) => _toggle(c, v),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
      ),
    );
  }
}
