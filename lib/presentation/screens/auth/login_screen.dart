import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/account_service.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/device_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/chat/chat_avatar.dart';
import 'phone_verification_screen.dart';
import 'register_screen.dart';
import 'two_factor_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  /// True when this screen was pushed by "Add account" while another account
  /// is still signed in. Backing out keeps the current account unchanged.
  final bool isAddAccount;

  const LoginScreen({super.key, this.isAddAccount = false});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mobileCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _legacyMode = false;
  String? _error;

  List<SavedAccount> _saved = [];
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _loadSavedAccounts();
  }

  @override
  void dispose() {
    _mobileCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAccounts() async {
    final list = await AccountService.list();
    if (!mounted) return;
    final currentId = ref.read(authNotifierProvider).valueOrNull?.id;
    setState(() => _saved = list.where((account) => account.userId != currentId).toList());
  }

  bool _validPhone(String value) {
    final compact = value.replaceAll(RegExp(r'[\s()\-.]'), '');
    return RegExp(r'^(?:\+|00)?[0-9]{8,15}$').hasMatch(compact);
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_legacyMode) {
        await _submitLegacy();
      } else {
        await _submitPhone();
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      if (_legacyMode && error.statusCode == 401 && error.message.contains('2FA')) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TwoFactorScreen(
              email: _emailCtrl.text.trim(),
              password: _passwordCtrl.text,
            ),
          ),
        );
      } else {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'خطا در ارتباط با سرور');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitPhone() async {
    final mobile = _mobileCtrl.text.trim();
    // Item 7: Do NOT send verification code immediately for unregistered users.
    // First check if the number exists; if not, redirect to registration.
    try {
      final check = await ApiService().post('/auth/check-phone', {
        'mobile_number': mobile,
      });
      final exists = check['exists'] == true;
      if (!exists && mounted) {
        // Redirect to registration screen to complete necessary steps first.
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RegisterScreen(initialMobile: mobile),
          ),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('این شماره ثبت نشده — لطفاً ابتدا ثبت‌نام کنید')),
          );
        }
        return;
      }
    } catch (_) {
      // If check fails (network), proceed to request code as fallback.
    }
    final response = await ApiService().post('/auth/request-phone-code', {
      'mobile_number': mobile,
    });
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhoneVerificationScreen(
          verificationId: response['verification_id'] as String,
          mobileNumber: response['mobile_number'] as String? ?? mobile,
          flow: PhoneVerificationFlow.login,
        ),
      ),
    );
  }

  Future<void> _submitLegacy() async {
    final response = await ApiService().post('/auth/login', {
      'email': _emailCtrl.text.trim(),
      'password': _passwordCtrl.text,
      'device_info': await DeviceService.getDeviceInfo(),
    });
    if (!mounted) return;
    await _saveSession(response);
  }

  Future<void> _saveSession(Map<String, dynamic> response) async {
    final user = UserModel.fromJson(response['user'] as Map<String, dynamic>);
    await ref.read(authNotifierProvider.notifier).setLoggedIn(
          user,
          response['access_token'] as String,
          response['refresh_token'] as String? ?? '',
        );
  }

  Future<void> _useSavedAccount(SavedAccount account) async {
    if (_switching) return;
    setState(() {
      _switching = true;
      _error = null;
    });
    try {
      await ref.read(authNotifierProvider.notifier).switchAccount(account);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _switching = false;
        _error = 'ورود با این حساب ممکن نشد. شماره موبایل یا رمز عبور را وارد کنید.';
      });
      await AccountService.remove(account.userId);
      await _loadSavedAccounts();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = widget.isAddAccount && Navigator.of(context).canPop();
    final phoneMode = !_legacyMode;
    return Scaffold(
      appBar: widget.isAddAccount
          ? AppBar(
              title: const Text('افزودن حساب'),
              leading: canPop
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'بازگشت به حساب فعلی',
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  : null,
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 72, color: AppTheme.primaryColor),
                  const SizedBox(height: 16),
                  Text(
                    widget.isAddAccount ? 'افزودن حساب جدید' : 'ورود به SecureMessenger',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    phoneMode
                        ? 'شماره موبایل خود را وارد کنید تا کد ورود پیامک شود'
                        : 'ورود ایمیلی فقط برای حساب‌های قدیمیِ بدون شماره موبایل است',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (_saved.isNotEmpty) ...[
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text('ادامه با حساب‌های ذخیره‌شده', style: Theme.of(context).textTheme.labelLarge),
                    ),
                    const SizedBox(height: 8),
                    ..._saved.map(
                      (account) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: ChatAvatar(
                            title: account.displayName,
                            url: account.avatarUrl,
                            token: account.accessToken,
                          ),
                          title: Text(account.displayName),
                          subtitle: Text(account.handle),
                          trailing: _switching
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.login, size: 20),
                          onTap: _switching ? null : () => _useSavedAccount(account),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('یا')),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (phoneMode)
                    TextFormField(
                      controller: _mobileCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'شماره موبایل',
                        hintText: '09149141414',
                        prefixIcon: Icon(Icons.phone_outlined),
                        helperText: 'با کد کشور وارد کنید؛ مثال: 09121234567',
                      ),
                      validator: (value) => _validPhone(value ?? '') ? null : 'شماره موبایل نامعتبر است',
                    )
                  else ...[
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'ایمیل',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'ایمیل الزامی است';
                        return value.contains('@') ? null : 'ایمیل نامعتبر';
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
                          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (value) => (value == null || value.length < 8) ? 'حداقل ۸ کاراکتر' : null,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(phoneMode ? 'ارسال کد ورود' : 'ورود'),
                    ),
                  ),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() {
                              _legacyMode = !_legacyMode;
                              _error = null;
                            }),
                    child: Text(phoneMode ? 'حساب قدیمی دارم (ورود با ایمیل)' : 'ورود با شماره موبایل'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    ),
                    child: const Text('حساب ندارید؟ ثبت‌نام کنید'),
                  ),
                  if (canPop)
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('انصراف و بازگشت به حساب فعلی'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
