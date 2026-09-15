import 'package:flutter/material.dart';
import '../../../data/services/api_service.dart';

class PollCreateSheet extends StatefulWidget {
  final String chatId;
  final ApiService api;
  const PollCreateSheet({super.key, required this.chatId, required this.api});

  @override
  State<PollCreateSheet> createState() => _PollCreateSheetState();
}

class _PollCreateSheetState extends State<PollCreateSheet> {
  final _qCtrl = TextEditingController();
  final List<TextEditingController> _opts = [TextEditingController(), TextEditingController()];
  bool _multiple = false;
  bool _anonymous = true;
  bool _isQuiz = false;
  int? _correctIndex;
  final _expCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _qCtrl.dispose();
    for (final c in _opts) c.dispose();
    _expCtrl.dispose();
    super.dispose();
  }

  void _addOption() {
    if (_opts.length >= 10) return;
    setState(() => _opts.add(TextEditingController()));
  }

  void _removeOption(int i) {
    if (_opts.length <= 2) return;
    setState(() {
      _opts[i].dispose();
      _opts.removeAt(i);
      if (_correctIndex != null && _correctIndex! >= _opts.length) _correctIndex = null;
      if (_correctIndex == i) _correctIndex = null;
      if (_correctIndex != null && _correctIndex! > i) _correctIndex = _correctIndex! - 1;
    });
  }

  Future<void> _submit() async {
    final q = _qCtrl.text.trim();
    final options = _opts.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    if (q.isEmpty || q.length > 300) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سوال باید ۱-۳۰۰ کاراکتر باشد')));
      return;
    }
    if (options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حداقل ۲ گزینه لازم است')));
      return;
    }
    if (options.length > 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حداکثر ۱۰ گزینه')));
      return;
    }
    if (_isQuiz && (_correctIndex == null || _correctIndex! < 0 || _correctIndex! >= options.length)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('برای کوییز یک گزینه صحیح انتخاب کنید')));
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.api.post('/messages/', {
        'chat_id': widget.chatId,
        'message_type': 'poll',
        'content': q,
        'question': q,
        'options': options,
        'poll_type': _isQuiz ? 'quiz' : 'poll',
        'allows_multiple': _multiple,
        'is_anonymous': _anonymous,
        if (_isQuiz && _correctIndex != null) 'correct_option': _correctIndex,
        if (_isQuiz && _expCtrl.text.trim().isNotEmpty) 'explanation': _expCtrl.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نظرسنجی ارسال شد')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              const Text('ایجاد نظرسنجی / کوییز', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              TextField(
                controller: _qCtrl,
                maxLength: 300,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(labelText: 'سوال', border: OutlineInputBorder(), hintText: 'مثلاً: بهترین زمان جلسه؟'),
              ),
              const SizedBox(height: 12),
              ...List.generate(_opts.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _opts[i],
                          maxLength: 100,
                          decoration: InputDecoration(
                            labelText: 'گزینه ${i + 1}',
                            border: const OutlineInputBorder(),
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (_isQuiz)
                        Radio<int>(
                          value: i,
                          groupValue: _correctIndex,
                          onChanged: (v) => setState(() => _correctIndex = v),
                        ),
                      IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: _opts.length <= 2 ? null : () => _removeOption(i)),
                    ],
                  ),
                );
              }),
              Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _opts.length >= 10 ? null : _addOption, icon: const Icon(Icons.add), label: const Text('افزودن گزینه'))),
              SwitchListTile(value: _multiple, onChanged: (v) => setState(() => _multiple = v), title: const Text('چند گزینه‌ای'), subtitle: const Text('شرکت‌کننده می‌تواند چند گزینه انتخاب کند', style: TextStyle(fontSize: 11))),
              SwitchListTile(value: _anonymous, onChanged: (v) => setState(() => _anonymous = v), title: const Text('رأی ناشناس'), subtitle: const Text('رأی‌دهندگان مخفی می‌مانند', style: TextStyle(fontSize: 11))),
              SwitchListTile(value: _isQuiz, onChanged: (v) => setState(() => _isQuiz = v), title: const Text('حالت کوییز / آزمون'), subtitle: const Text('یک گزینه صحیح دارد', style: TextStyle(fontSize: 11))),
              if (_isQuiz)
                TextField(controller: _expCtrl, maxLength: 500, decoration: const InputDecoration(labelText: 'توضیح پاسخ صحیح (اختیاری)', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              FilledButton(onPressed: _sending ? null : _submit, child: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('ارسال نظرسنجی')),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
