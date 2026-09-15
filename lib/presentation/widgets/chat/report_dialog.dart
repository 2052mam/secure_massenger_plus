import 'package:flutter/material.dart';
import '../../../data/services/api_service.dart';

class ReportDialog extends StatefulWidget {
  final ApiService api;
  final String targetType; // user, group, channel, message
  final String? targetUserId;
  final String? targetChatId;
  final String? targetMessageId;
  final String title;

  const ReportDialog({
    super.key,
    required this.api,
    required this.targetType,
    this.targetUserId,
    this.targetChatId,
    this.targetMessageId,
    required this.title,
  });

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  String _reason = 'spam';
  final _descCtrl = TextEditingController();
  bool _sending = false;

  final reasons = [
    {'value': 'spam', 'label': 'اسپم', 'labelEn': 'Spam', 'icon': Icons.report},
    {'value': 'harassment', 'label': 'مزاحمت / آزار', 'labelEn': 'Harassment', 'icon': Icons.person_off},
    {'value': 'violence', 'label': 'خشونت', 'labelEn': 'Violence', 'icon': Icons.warning},
    {'value': 'child_abuse', 'label': 'سوءاستفاده از کودکان', 'labelEn': 'Child Abuse', 'icon': Icons.child_care},
    {'value': 'pornography', 'label': 'محتوای مستهجن', 'labelEn': 'Pornography', 'icon': Icons.block},
    {'value': 'fake_account', 'label': 'اکانت جعلی', 'labelEn': 'Fake Account', 'icon': Icons.person_search},
    {'value': 'copyright', 'label': 'نقض کپی‌رایت', 'labelEn': 'Copyright', 'icon': Icons.copyright},
    {'value': 'illegal_drugs', 'label': 'مواد مخدر', 'labelEn': 'Illegal Drugs', 'icon': Icons.medication},
    {'value': 'personal_data', 'label': 'افشای اطلاعات شخصی', 'labelEn': 'Personal Data', 'icon': Icons.privacy_tip},
    {'value': 'other', 'label': 'سایر', 'labelEn': 'Other', 'icon': Icons.more_horiz},
  ];

  Future<void> _submit() async {
    setState(() => _sending = true);
    try {
      final endpoint = widget.targetType == 'user'
          ? '/reports/user'
          : widget.targetType == 'message'
              ? '/reports/message'
              : '/reports/chat';
      final body = <String, dynamic>{
        'reason': _reason,
        'description': _descCtrl.text.trim(),
      };
      if (widget.targetUserId != null) body['target_user_id'] = widget.targetUserId;
      if (widget.targetChatId != null) body['target_chat_id'] = widget.targetChatId;
      if (widget.targetMessageId != null) body['message_id'] = widget.targetMessageId;
      await widget.api.post(endpoint, body);
      // Telegram parity: reporting a user also blocks them automatically.
      if (widget.targetType == 'user' && widget.targetUserId != null) {
        try {
          await widget.api.post('/users/block/${widget.targetUserId}', {});
        } catch (_) {
          // ignore block failure – report already succeeded
        }
      }
      if (mounted) {
        Navigator.pop(context, true);
        if (widget.targetType == 'user') {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('گزارش ارسال شد و کاربر بلاک شد (مانند تلگرام).')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('گزارش با موفقیت ارسال شد. پس از بررسی مدیریت اقدام خواهد شد.')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('گزارش ${widget.title}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('دلیل گزارش را انتخاب کنید (مانند تلگرام):', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 8),
            ...reasons.map((r) => RadioListTile<String>(
                  value: r['value'] as String,
                  groupValue: _reason,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(r['label'] as String, style: const TextStyle(fontSize: 14)),
                  secondary: Icon(r['icon'] as IconData, size: 20),
                  onChanged: (v) => setState(() => _reason = v!),
                )),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'توضیحات اضافی (اختیاری) ...', border: OutlineInputBorder(), contentPadding: EdgeInsets.all(12)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _sending ? null : () => Navigator.pop(context), child: const Text('لغو')),
        ElevatedButton(onPressed: _sending ? null : _submit, child: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('ارسال گزارش')),
      ],
    );
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }
}
