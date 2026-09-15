import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/api_constants.dart';
import '../../../data/models/user_model.dart';
import '../../widgets/chat/chat_avatar.dart';
import 'dart:io';

import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../widgets/chat/chat_labels.dart';
import 'profile_photos_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  bool _loading = false;
  bool _saving = false;
  String? _seededUserId;

  @override
  void initState() {
    super.initState();
    _seedFrom(ref.read(authNotifierProvider).valueOrNull);
  }

  /// The session may still be loading when this screen opens. Seeding the
  /// fields only once, from whichever snapshot arrives first, keeps the saved
  /// values intact instead of sending empty strings back to the server.
  void _seedFrom(UserModel? user) {
    if (user == null || _seededUserId == user.id) return;
    _seededUserId = user.id;
    _nameCtrl.text = user.displayName;
    _usernameCtrl.text = user.username ?? '';
    _bioCtrl.text = user.bio ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (_loading || _saving) return;
    final api = ref.read(authenticatedSessionProvider).api;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _loading = true);
    try {
      final uploadRes = await api.uploadFile(
        '/media/upload',
        File(picked.path),
      );
      final mediaId = uploadRes['id'] as String;
      final fullUrl =
          uploadRes['url'] as String? ?? '${ApiConstants.baseUrl}/media/$mediaId';
      // New pictures join the profile album (and become the main photo),
      // so previous ones stay available like in Telegram.
      await api.post('/users/me/photos', {
        'photo_url': fullUrl,
        'media_id': mediaId,
      });
      if (!mounted) return;
      await ref.read(authNotifierProvider.notifier).checkSession();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('عکس پروفایل به‌روز شد')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeAvatar() async {
    if (_loading || _saving) return;
    final isFa = ref.read(localeProvider).languageCode == 'fa';
    final api = ref.read(authenticatedSessionProvider).api;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isFa ? 'حذف عکس پروفایل؟' : 'Remove profile photo?'),
        content: Text(
          isFa
              ? 'پروفایل شما بدون عکس نمایش داده می‌شود.'
              : 'Your profile will be shown without a photo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isFa ? 'لغو' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isFa ? 'حذف' : 'Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      // Clearing the visible photo keeps the album intact: individual photos
      // can still be deleted from the profile photos screen.
      await api.put('/users/me', {'avatar_url': null});
      if (!mounted) return;
      await ref.read(authNotifierProvider.notifier).checkSession();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_loading || _saving) return;
    final user = ref.read(authNotifierProvider).valueOrNull;
    final isFa = ref.read(localeProvider).languageCode == 'fa';
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isFa ? 'پروفایل هنوز آماده نیست' : 'Profile not ready'),
        ),
      );
      return;
    }
    final name = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim().toLowerCase();
    // Telegram-like: @id is optional — clearing the field removes it.
    if (username.isNotEmpty && !RegExp(r'^[a-z0-9_]{3,30}$').hasMatch(username)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isFa ? 'آیدی باید ۳ تا ۳۰ کاراکتر (حروف انگلیسی، عدد، _) باشد' : 'Username must be 3-30 chars (a-z, 0-9, _)')),
      );
      return;
    }
    // The bio is always sent (an empty value clears it); name only when it
    // changed. Username is sent when changed — empty string removes it.
    final body = <String, dynamic>{'bio': _bioCtrl.text.trim()};
    if (name.isNotEmpty && name != user.displayName) body['display_name'] = name;
    if (username != (user.username ?? '')) body['username'] = username;
    setState(() => _saving = true);
    try {
      await ref.read(authenticatedSessionProvider).api.put('/users/me', body);
      if (!mounted) return;
      await ref.read(authNotifierProvider.notifier).checkSession();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('پروفایل ذخیره شد')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFa = ref.watch(localeProvider).languageCode == 'fa';
    final labels = ChatLabels.of(context);
    final user = ref.watch(authNotifierProvider).valueOrNull;
    if (user != null && _seededUserId != user.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _seedFrom(user));
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isFa ? 'ویرایش پروفایل' : 'Edit Profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isFa ? 'ذخیره' : 'Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              GestureDetector(
                onTap: _loading
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ProfilePhotosScreen(
                            manage: true,
                            title: user?.displayName,
                            initialUrl: user?.avatarUrl,
                          ),
                        ),
                      ),
                child: Stack(
                  children: [
                    ChatAvatar(
                      radius: 56,
                      title: user?.displayName ?? '?',
                      url: user?.avatarUrl,
                      token: ref.watch(authenticatedSessionProvider).token,
                    ),
                    if (_loading)
                      const Positioned.fill(child: CircularProgressIndicator())
                    else
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          child: const Icon(
                            Icons.camera_alt,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              TextButton.icon(
                key: const ValueKey('open-profile-photos'),
                onPressed: _loading || _saving
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ProfilePhotosScreen(
                            manage: true,
                            title: user?.displayName,
                            initialUrl: user?.avatarUrl,
                          ),
                        ),
                      ),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(labels.profilePhotos),
              ),
              if (user?.avatarUrl?.isNotEmpty == true)
                TextButton.icon(
                  key: const ValueKey('remove-profile-photo'),
                  onPressed: _loading || _saving ? null : _removeAvatar,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(
                    isFa ? 'حذف عکس پروفایل' : 'Remove profile photo',
                  ),
                ),
              const SizedBox(height: 32),
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: isFa ? 'نام نمایشی' : 'Display Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _usernameCtrl,
                decoration: InputDecoration(
                  labelText: isFa ? 'آیدی (اختیاری)' : 'Username (optional)',
                  prefixText: '@',
                  helperText: isFa ? 'خالی بگذارید تا آیدی حذف شود' : 'Leave empty to remove your @id',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _bioCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: isFa ? 'بایو' : 'Bio',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
