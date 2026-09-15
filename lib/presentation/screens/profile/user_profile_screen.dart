import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/user_model.dart';
import '../../../data/services/api_service.dart';
import '../../providers/locale_provider.dart';
import '../../../data/services/storage_service.dart';
import '../../widgets/chat/chat_avatar.dart';
import '../../widgets/chat/chat_labels.dart';
import '../../widgets/chat/shared_media_tab.dart';
import 'profile_photos_screen.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  UserModel? _user;
  bool _loading = true;
  String? _error;
  String? _chatId;

  @override
  void initState() {
    super.initState();
    _load();
    _checkBlocked();
    _loadChatId();
  }

  Future<void> _loadChatId() async {
    try {
      final res = await ApiService().post('/chats/private', {'user_id': widget.userId});
      if (mounted && res['chat_id'] != null) {
        setState(() => _chatId = res['chat_id'] as String);
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().get('/users/${widget.userId}');
      if (!mounted) return;
      setState(() {
        _user = UserModel.fromJson(res);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _block() async {
    try {
      await ApiService().post('/users/block/${widget.userId}', {});
      if (mounted) {
        setState(() => _isBlocked = true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ربراک کالب دش')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _unblock() async {
    try {
      await ApiService().post('/users/unblock/${widget.userId}', {});
      if (mounted) {
        setState(() => _isBlocked = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('کالبنآ دش')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  bool _isBlocked = false;

  Future<void> _checkBlocked() async {
    try {
      final res = await ApiService().get('/users/blocked');
      final users = res['users'] as List? ?? [];
      if (!mounted) return;
      setState(() {
        _isBlocked = users.any((u) => u['id'] == widget.userId);
      });
    } catch (_) {}
  }

  /// Telegram opens the person's photos full screen; several photos can be
  /// swiped through when the user published more than one.
  void _openPhotos() {
    final user = _user;
    if (user == null || !user.showProfilePhoto) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfilePhotosScreen(
          userId: widget.userId,
          title: user.displayName,
          initialUrl: user.avatarUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFa = ref.watch(localeProvider).languageCode == 'fa';

    return Scaffold(
      appBar: AppBar(title: Text(isFa ? 'پروفایل' : 'Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : _user == null
          ? const Center(child: Text('یافت نشد'))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: GestureDetector(
                    key: const ValueKey('open-user-photos'),
                    onTap: _user!.showProfilePhoto ? _openPhotos : null,
                    child: Hero(
                      tag: 'user-photo-${widget.userId}',
                      child: ChatAvatar(
                        title: _user!.displayName,
                        url: _user!.showProfilePhoto ? _user!.avatarUrl : null,
                        token: StorageService.getToken(),
                        radius: 60,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    _user!.displayName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (_user!.hasUsername)
                  Center(
                    child: Text(
                      '@${_user!.username}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 15),
                    ),
                  ),
                if (_user!.bio != null && _user!.bio!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_user!.bio!),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ListTile(
                  leading: Icon(
                    _user!.isOnline ? Icons.circle : Icons.circle_outlined,
                    color: _user!.isOnline ? Colors.green : Colors.grey,
                    size: 16,
                  ),
                  title: Text(
                    _user!.isOnline
                        ? (isFa ? 'آنلاین' : 'Online')
                        : (!_user!.showLastSeen || _user!.lastSeen == null
                              ? ChatLabels.of(context).lastSeenHidden
                              : (isFa ? 'آفلاین' : 'Offline')),
                  ),
                  subtitle: _user!.lastSeen != null && !_user!.isOnline
                      ? Text(ChatLabels.of(context).lastSeen(_user!.lastSeen!))
                      : null,
                ),
                const Divider(),
                ListTile(
                  leading: Icon(
                    _isBlocked ? Icons.lock_open : Icons.block,
                    color: Colors.red,
                  ),
                  title: Text(
                    _isBlocked ? 'آنبلاک' : 'بلاک',
                    style: const TextStyle(color: Colors.red),
                  ),
                  onTap: _isBlocked ? _unblock : _block,
                ),
                if (_chatId != null) ...[
                  const Divider(height: 32),
                  Text(
                    isFa ? 'رسانه‌ها و فایل‌های اشتراکی' : 'Shared Media & Files',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  SharedMediaSection(
                    chatId: _chatId!,
                    api: ApiService(),
                    token: StorageService.getToken(),
                  ),
                ],
                // ListTile(
                //   leading: const Icon(Icons.block, color: Colors.red),
                //   title: Text(isFa ? 'بلاک کردن' : 'Block', style: const TextStyle(color: Colors.red)),
                //   onTap: _block,
                // ),
              ],
            ),
    );
  }
}
