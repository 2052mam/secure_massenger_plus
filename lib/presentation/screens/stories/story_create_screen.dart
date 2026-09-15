import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../providers/auth_provider.dart';
import '../chat/photo_editor_screen.dart';
import '../chat/video_editor_screen.dart';

/// Create a story: text, photo or video (24h expiry, like Telegram).
///
/// Layout notes: the preview is wrapped in an [AspectRatio] inside a bounded
/// box instead of a fixed-height [Stack], which is what produced the
/// RenderFlex/"frame" errors when a tall image or the keyboard shrank the
/// available space.
class StoryCreateScreen extends ConsumerStatefulWidget {
  const StoryCreateScreen({super.key});
  @override
  ConsumerState<StoryCreateScreen> createState() => _StoryCreateScreenState();
}

class _StoryCreateScreenState extends ConsumerState<StoryCreateScreen> {
  final _textCtrl = TextEditingController();
  File? _file;
  bool _isVideo = false;
  bool _sending = false;
  bool _picking = false;
  String? _error;
  VideoPlayerController? _videoCtrl;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    // Keeps the publish button's enabled state in sync with the text field.
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _textCtrl.removeListener(_onTextChanged);
    _textCtrl.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source, {required bool video}) async {
    if (_picking || _sending) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picker = ImagePicker();
      final picked = video
          ? await picker.pickVideo(
              source: source, maxDuration: const Duration(seconds: 60))
          : await picker.pickImage(
              source: source, maxWidth: 1920, imageQuality: 88);
      if (picked == null || !mounted) return;

      File file = File(picked.path);
      // Same internal editor as chats, so stories get crop/draw/trim too.
      if (video) {
        final edited = await Navigator.of(context).push<EditedVideo>(
          MaterialPageRoute(builder: (_) => VideoEditorScreen(videoFile: file)),
        );
        if (edited == null || !mounted) return;
        file = edited.file;
      } else {
        final edited = await Navigator.of(context).push<File>(
          MaterialPageRoute(builder: (_) => PhotoEditorScreen(imageFile: file)),
        );
        if (edited == null || !mounted) return;
        file = edited;
      }

      await _videoCtrl?.dispose();
      _videoCtrl = null;
      if (video) {
        final ctrl = VideoPlayerController.file(file);
        try {
          await ctrl.initialize();
          await ctrl.setLooping(true);
          await ctrl.play();
          _videoCtrl = ctrl;
        } catch (_) {
          await ctrl.dispose();
        }
      }
      if (!mounted) return;
      setState(() {
        _file = file;
        _isVideo = video;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'انتخاب رسانه ناموفق بود');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _clearMedia() async {
    await _videoCtrl?.dispose();
    _videoCtrl = null;
    if (mounted) {
      setState(() {
        _file = null;
        _isVideo = false;
      });
    }
  }

  bool get _canPublish =>
      !_sending && (_file != null || _textCtrl.text.trim().isNotEmpty);

  Future<void> _publish() async {
    if (_sending) return;
    final text = _textCtrl.text.trim();
    if (_file == null && text.isEmpty) {
      setState(() => _error = 'متن یا عکس/ویدیو برای استوری لازم است');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final api = ref.read(authenticatedSessionProvider).api;
      String? mediaId;
      String storyType = 'text';
      if (_file != null) {
        final upload = await api.uploadFile('/media/upload', _file!);
        mediaId = upload['id'] as String?;
        storyType = _isVideo ? 'video' : 'image';
      }
      await api.post('/stories/', {
        'story_type': storyType,
        'content': text.isEmpty ? null : text,
        'media_id': mediaId,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('استوری جدید'),
        actions: [
          if (_file != null)
            IconButton(
              tooltip: 'حذف رسانه',
              icon: const Icon(Icons.delete_outline),
              onPressed: _sending ? null : _clearMedia,
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: ConstrainedBox(
                // Guarantees a bounded, non-negative height for the column so
                // no child can be laid out into an infinite/!=finite box.
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_file != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: AspectRatio(
                          aspectRatio: _isVideo &&
                                  _videoCtrl != null &&
                                  _videoCtrl!.value.isInitialized &&
                                  _videoCtrl!.value.aspectRatio > 0
                              ? _videoCtrl!.value.aspectRatio
                              : 3 / 4,
                          child: Container(
                            color: Colors.black12,
                            child: _isVideo
                                ? (_videoCtrl != null &&
                                        _videoCtrl!.value.isInitialized
                                    ? VideoPlayer(_videoCtrl!)
                                    : const Center(
                                        child: Icon(Icons.videocam,
                                            size: 48, color: Colors.grey)))
                                : Image.file(_file!, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: theme.dividerColor,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.auto_stories_outlined,
                                size: 40, color: theme.hintColor),
                            const SizedBox(height: 8),
                            Text(
                              'یک عکس یا ویدیو انتخاب کنید یا فقط متن بنویسید',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: theme.hintColor, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _picking
                                ? null
                                : () => _pick(ImageSource.gallery, video: false),
                            icon: const Icon(Icons.photo_library_outlined, size: 18),
                            label: const Text('عکس از گالری'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _picking
                                ? null
                                : () => _pick(ImageSource.camera, video: false),
                            icon: const Icon(Icons.camera_alt_outlined, size: 18),
                            label: const Text('دوربین'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _picking
                                ? null
                                : () => _pick(ImageSource.gallery, video: true),
                            icon: const Icon(Icons.videocam_outlined, size: 18),
                            label: const Text('ویدیو'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _textCtrl,
                      maxLines: 4,
                      minLines: 2,
                      maxLength: 1000,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        labelText: 'متن استوری',
                        hintText: 'چیزی بنویسید...',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _canPublish ? _publish : null,
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(_sending
                          ? 'در حال انتشار...'
                          : 'انتشار استوری (۲۴ ساعته)'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
