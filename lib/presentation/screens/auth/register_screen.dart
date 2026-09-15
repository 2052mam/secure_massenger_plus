import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/device_service.dart';
import '../../../data/services/terms_service.dart';
import '../../widgets/chat/terms_dialog.dart';
import 'phone_verification_screen.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  final String? initialMobile;
  const RegisterScreen({super.key, this.initialMobile});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  bool _termsAccepted = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialMobile != null && widget.initialMobile!.isNotEmpty) {
      _mobileCtrl.text = widget.initialMobile!;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _mobileCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _showTerms() async {
    final accepted = await TermsDialog.show(context, requireAccept: true);
    if (accepted == true && mounted) setState(() => _termsAccepted = true);
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    if (!_termsAccepted) {
      setState(() => _error = 'برای ثبت‌نام باید قوانین را بخوانید و بپذیرید');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final deviceInfo = await DeviceService.getDeviceInfo();
      final username = _usernameCtrl.text.trim().toLowerCase();
      print(_mobileCtrl.text);
      final res = await ApiService().post('/auth/register', {
        'email': _emailCtrl.text.trim().toLowerCase(),
        'mobile_number': _mobileCtrl.text.trim(),
        'password': _passwordCtrl.text,
        if (username.isNotEmpty) 'username': username,
        'display_name': _displayNameCtrl.text.trim(),
        'device_info': deviceInfo,
        'terms_accepted': true,
        'terms_version': TermsService.currentVersion,
      });

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PhoneVerificationScreen(
            verificationId: res['verification_id'] as String,
            mobileNumber:
                res['mobile_number'] as String? ?? _mobileCtrl.text.trim(),
            flow: PhoneVerificationFlow.registration,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'خطا در ارتباط با سرور');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ثبت‌نام')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'ایجاد حساب جدید',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'برای ادامه، یک کد تأیید با پیامک ارسال می‌شود. Google Authenticator اختیاری است.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _displayNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'نام نمایشی',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'حداقل ۲ کاراکتر'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'آیدی (اختیاری)',
                    prefixIcon: Icon(Icons.alternate_email),
                    helperText:
                        'فقط حروف کوچک، عدد و _ — بعداً هم می‌توانید بسازید',
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    if (t.length < 3 || t.length > 30) return '۳ تا ۳۰ کاراکتر';
                    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(t))
                      return 'فرمت نامعتبر';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'ایمیل',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) {
                    if (v == null || !v.contains('@')) return 'ایمیل نامعتبر';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _mobileCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'شماره موبایل',
                    hintText: '09149141414',
                    prefixIcon: Icon(Icons.phone_outlined),
                    helperText: 'با کد کشور وارد کنید؛ مثال: 09121234567',
                  ),
                  validator: (v) {
                    final compact = (v ?? '').replaceAll(
                      RegExp(r'[\s()\-.]'),
                      '',
                    );
                    if (!RegExp(r'^(?:\+|00)?[0-9]{8,15}$').hasMatch(compact)) {
                      return 'شماره موبایل نامعتبر';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'رمز عبور',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.length < 8) ? 'حداقل ۸ کاراکتر' : null,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _showTerms,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _termsAccepted
                            ? Colors.green
                            : Colors.grey.shade300,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      color: _termsAccepted
                          ? Colors.green.withValues(alpha: 0.06)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _termsAccepted
                              ? Icons.check_circle
                              : Icons.rule_outlined,
                          color: _termsAccepted ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'قوانین و مقررات',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                'برای مطالعه و پذیرش لمس کنید (اسکرول تا انتها)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_termsAccepted)
                          const Text(
                            'پذیرفته شد',
                            style: TextStyle(color: Colors.green, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('ثبت‌نام و ادامه'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
