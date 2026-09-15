import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/user_model.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/device_service.dart';
import '../../providers/auth_provider.dart';

/// The optional Google Authenticator step. New phone-first logins pass a
/// verified challenge ID; email/password is retained only for legacy accounts.
class TwoFactorScreen extends ConsumerStatefulWidget {
  final String? email;
  final String? password;
  final String? verificationId;

  const TwoFactorScreen({
    super.key,
    this.email,
    this.password,
    this.verificationId,
  }) : assert(
         verificationId != null || (email != null && password != null),
         'Provide an SMS verification ID or legacy email/password credentials.',
       );

  bool get isPhoneLogin => verificationId != null;

  @override
  ConsumerState<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends ConsumerState<TwoFactorScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final code = _codeCtrl.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'کد ۶ رقمی وارد کنید');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = widget.isPhoneLogin
          ? await ApiService().post('/auth/verify-login-2fa', {
              'verification_id': widget.verificationId,
              'code': code,
              'device_info': await DeviceService.getDeviceInfo(),
            })
          : await ApiService().post('/auth/login', {
              'email': widget.email,
              'password': widget.password,
              'totp_code': code,
              'device_info': await DeviceService.getDeviceInfo(),
            });
      if (!mounted) return;
      final user = UserModel.fromJson(response['user'] as Map<String, dynamic>);
      await ref.read(authNotifierProvider.notifier).setLoggedIn(
            user,
            response['access_token'] as String,
            response['refresh_token'] as String? ?? '',
          );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'خطا در ورود');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تأیید دو مرحله‌ای')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.security, size: 64, color: Colors.blue),
              const SizedBox(height: 16),
              Text(
                widget.isPhoneLogin
                    ? 'پیامک تأیید شد. کد Google Authenticator را وارد کنید'
                    : 'کد Google Authenticator را وارد کنید',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, letterSpacing: 10),
                decoration: const InputDecoration(labelText: 'کد ۶ رقمی', counterText: ''),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('تأیید'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
