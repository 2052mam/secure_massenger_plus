import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/media_utils.dart';
import '../../../data/models/user_photo_model.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/chat/chat_labels.dart';
import '../../widgets/media/photo_canvas.dart';

/// Full screen profile album, the way Telegram shows a person's photos:
/// swipe between them, with the owner able to add, promote or delete one.
class ProfilePhotosScreen extends ConsumerStatefulWidget {
  const ProfilePhotosScreen({
    super.key,
    this.userId,
    this.title,
    this.manage = false,
    this.initialUrl,
  });

  /// null means the signed in user's own album.
  final String? userId;
  final String? title;
  final bool manage;

  /// Shown immediately while the album loads (avoids an empty flash).
  final String? initialUrl;

  @override
  ConsumerState<ProfilePhotosScreen> createState() =>
      _ProfilePhotosScreenState();
}

class _ProfilePhotosScreenState extends ConsumerState<ProfilePhotosScreen> {
  final _controller = PageController();
  List<UserPhotoModel> _photos = [];
  bool _loading = true;
  bool _busy = false;
  int _index = 0;
  String? _error;

  bool get _isSelf => widget.userId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(authenticatedSessionProvider).api;
    try {
      final res = await api.get(
        _isSelf ? '/users/me/photos' : '/users/${widget.userId}/photos',
      );
      if (!mounted) return;
      setState(() {
        _photos = UserPhotoModel.listFrom(res);
        _loading = false;
        _error = null;
        if (_index >= _photos.length) _index = 0;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      imageQuality: 88,
    );
    if (picked == null || !mounted) return;
    await _run(() async {
      final api = ref.read(authenticatedSessionProvider).api;
      final upload = await api.uploadFile('/media/upload', File(picked.path));
      final url = upload['url'] as String?;
      if (url == null || url.isEmpty) throw StateError('upload failed');
      await api.post('/users/me/photos', {
        'photo_url': url,
        'media_id': upload['id'],
      });
      await ref.read(authNotifierProvider.notifier).checkSession();
    });
  }

  Future<void> _setMain(UserPhotoModel photo) => _run(() async {
    final api = ref.read(authenticatedSessionProvider).api;
    await api.post('/users/me/photos/${photo.id}/main', {});
    await ref.read(authNotifierProvider.notifier).checkSession();
  });

  Future<void> _delete(UserPhotoModel photo) => _run(() async {
    final api = ref.read(authenticatedSessionProvider).api;
    await api.post('/users/me/photos/${photo.id}/delete', {});
    await ref.read(authNotifierProvider.notifier).checkSession();
  });

  ImageProvider _provider(String url) {
    final token = ref.read(authenticatedSessionProvider).token;
    return CachedNetworkImageProvider(
      resolveMediaUrl(null, existingUrl: url) ?? url,
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final labels = ChatLabels.of(context);
    final urls = _photos.isEmpty && widget.initialUrl != null && _loading
        ? [widget.initialUrl!]
        : _photos.map((p) => p.photoUrl).toList();
    final canManage = widget.manage && _isSelf;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          urls.length > 1
              ? labels.photoCounter(_index + 1, urls.length)
              : (widget.title ?? labels.profilePhotos),
        ),
        actions: [
          if (canManage)
            IconButton(
              key: const ValueKey('add-profile-photo'),
              tooltip: labels.addPhoto,
              icon: const Icon(Icons.add_a_photo_outlined),
              onPressed: _busy ? null : _addPhoto,
            ),
          if (canManage && _photos.isNotEmpty)
            PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (value) {
                final safeIndex = _index < 0 || _index >= _photos.length
                    ? 0
                    : _index;
                final photo = _photos[safeIndex];
                if (value == 'main') _setMain(photo);
                if (value == 'delete') _delete(photo);
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'main', child: Text(labels.setMainPhoto)),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(labels.deletePhoto),
                ),
              ],
            ),
        ],
      ),
      body: Stack(
        children: [
          if (urls.isEmpty)
            Center(
              child: Text(
                _error ?? labels.noPhotos,
                style: const TextStyle(color: Colors.white70),
              ),
            )
          else
            PageView.builder(
              controller: _controller,
              itemCount: urls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) =>
                  PhotoCanvas(key: ValueKey(urls[i]), image: _provider(urls[i])),
            ),
          if (_busy || _loading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (urls.length > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < urls.length; i++)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _index ? Colors.white : Colors.white38,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
