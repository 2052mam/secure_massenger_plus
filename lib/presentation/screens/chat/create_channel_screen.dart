import 'package:flutter/material.dart';
import '../../../data/services/api_service.dart';

/// Channel creation is a broadcast setup, not the group member-creation dialog.
class CreateChannelScreen extends StatefulWidget {
  const CreateChannelScreen({super.key, required this.api});
  final ApiService api;
  @override
  State<CreateChannelScreen> createState() => _CreateChannelScreenState();
}

class _CreateChannelScreenState extends State<CreateChannelScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _username = TextEditingController();
  bool _public = false;
  bool _saving = false;
  String _t(String en, String fa) =>
      Localizations.localeOf(context).languageCode == 'fa' ? fa : en;
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final result = await widget.api.post('/chats/channel', {
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'is_public': _public,
        'username': _public ? _username.text.trim().toLowerCase() : null,
      });
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_t('New channel', 'کانال جدید'))),
    body: SafeArea(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.campaign_outlined, size: 64),
            const SizedBox(height: 16),
            Text(
              _t(
                'Broadcast to subscribers. Only administrators with publishing rights can post; subscribers cannot send messages.',
                'انتشار برای مشترکان. فقط مدیران دارای دسترسی انتشار می‌توانند پست ارسال کنند؛ مشترکان امکان ارسال پیام ندارند.',
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _title,
              enabled: !_saving,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: _t('Channel name', 'نام کانال'),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? _t('Enter a channel name', 'نام کانال را وارد کنید')
                  : null,
            ),
            TextFormField(
              controller: _description,
              enabled: !_saving,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _t('Description', 'توضیحات'),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_t('Public channel', 'کانال عمومی')),
              subtitle: Text(
                _public
                    ? _t(
                        'Anyone can find and join using its username.',
                        'همه می‌توانند با نام کاربری کانال را پیدا و عضو شوند.',
                      )
                    : _t(
                        'Private: people need an invitation link.',
                        'خصوصی: عضویت به لینک دعوت نیاز دارد.',
                      ),
              ),
              value: _public,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _public = value),
            ),
            if (_public)
              TextFormField(
                controller: _username,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: _t('Public username', 'نام کاربری عمومی'),
                  prefixText: '@',
                ),
                validator: (value) =>
                    !_public ||
                        RegExp(
                          r'^[a-z0-9_]{3,30}$',
                        ).hasMatch((value ?? '').trim().toLowerCase())
                    ? null
                    : _t(
                        'Use 3–30 letters, numbers or underscores',
                        'از ۳ تا ۳۰ حرف انگلیسی، عدد یا زیرخط استفاده کنید',
                      ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _create,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_t('Create channel', 'ایجاد کانال')),
            ),
          ],
        ),
      ),
    ),
  );
}
