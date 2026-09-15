import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/user_model.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/device_service.dart';
import '../../providers/auth_provider.dart';
import 'two_factor_screen.dart';

enum PhoneVerificationFlow { registration, login }

/// Telegram-style SMS code entry for both registration and phone-first login.
/// The code is intentionally never kept in persistent storage.
class PhoneVerificationScreen extends ConsumerStatefulWidget {
  final String verificationId;
  final String mobileNumber;
  final PhoneVerificationFlow flow;

  const PhoneVerificationScreen({
    super.key,
    required this.verificationId,
    required this.mobileNumber,
    required this.flow,
  });

  @override
  ConsumerState<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState
    extends ConsumerState<PhoneVerificationScreen> {
  final _codeCtrl = TextEditingController();
  late String _verificationId;
  bool _loading = false;
  bool _resending = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_loading) return;
    final code = _codeCtrl.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'کد ۶ رقمی را وارد کنید');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });
    try {
      final response = await ApiService().post('/auth/verify-phone', {
        'verification_id': _verificationId,
        'code': code,
        'device_info': await DeviceService.getDeviceInfo(),
      });
      if (!mounted) return;
      if (response['require_2fa'] == true) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => TwoFactorScreen(
              verificationId: response['verification_id'] as String,
            ),
          ),
        );
        return;
      }
      await _saveSession(response);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'خطا در تأیید کد');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSession(Map<String, dynamic> response) async {
    final user = UserModel.fromJson(response['user'] as Map<String, dynamic>);
    await ref.read(authNotifierProvider.notifier).setLoggedIn(
          user,
          response['access_token'] as String,
          response['refresh_token'] as String? ?? '',
        );
  }

  Future<void> _resend() async {
    if (_loading || _resending) return;
    setState(() {
      _resending = true;
      _error = null;
      _message = null;
    });
    try {
      final response = await ApiService().post('/auth/resend-phone-code', {
        'verification_id': _verificationId,
      });
      if (!mounted) return;
      setState(() {
        _verificationId = response['verification_id'] as String;
        _codeCtrl.clear();
        _message = 'کد جدید ارسال شد.';
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'ارسال دوباره کد ممکن نیست');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final registering = widget.flow == PhoneVerificationFlow.registration;
    return Scaffold(
      appBar: AppBar(
        title: Text(registering ? 'تأیید شماره موبایل' : 'ورود با شماره موبایل'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.sms_outlined, size: 68, color: Colors.blue),
                const SizedBox(height: 18),
                Text(
                  registering ? 'شماره خود را تأیید کنید' : 'کد ورود را وارد کنید',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'کد ۶ رقمی به ${widget.mobileNumber} ارسال شد.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: _codeCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, letterSpacing: 10),
                  decoration: const InputDecoration(
                    labelText: 'کد پیامک',
                    counterText: '',
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) => _verify(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    style: const TextStyle(color: Colors.green),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _verify,
                    child: _loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(registering ? 'تأیید و ورود' : 'ورود'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _resending ? null : _resend,
                  child: _resending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('کد را دریافت نکردید؟ ارسال دوباره'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
