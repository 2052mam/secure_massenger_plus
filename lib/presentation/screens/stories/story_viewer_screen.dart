import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../core/utils/media_utils.dart';
import '../../../data/models/story_model.dart';
import '../../providers/auth_provider.dart';

/// Telegram-like full-screen story viewer with progress bars, tap zones,
/// views count and delete-for-owner.
class StoryViewerScreen extends ConsumerStatefulWidget {
  final List<StoryGroup> groups;
  final int initialGroupIndex;
  const StoryViewerScreen({super.key, required this.groups, this.initialGroupIndex = 0});

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen> {
  late int _groupIndex;
  int _storyIndex = 0;
  double _progress = 0;
  Timer? _timer;
  VideoPlayerController? _video;
  bool _paused = false;

  /// Only groups that actually have stories are navigable; an empty list is
  /// handled in [build] so these getters are never reached with bad indices.
  StoryGroup get _group =>
      widget.groups[_groupIndex.clamp(0, widget.groups.length - 1)];
  StoryModel get _story =>
      _group.stories[_storyIndex.clamp(0, _group.stories.length - 1)];

  bool get _isEmpty =>
      widget.groups.isEmpty || widget.groups.every((g) => g.stories.isEmpty);

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.groups.isEmpty
        ? 0
        : widget.initialGroupIndex.clamp(0, widget.groups.length - 1);
    if (!_isEmpty) {
      // A group with no stories would break the progress row.
      if (_group.stories.isEmpty) {
        _groupIndex = widget.groups.indexWhere((g) => g.stories.isNotEmpty);
      }
      _openCurrent();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _video?.dispose();
    super.dispose();
  }

  void _openCurrent() {
    _timer?.cancel();
    _video?.dispose();
    _video = null;
    _progress = 0;
    _markSeen();
    final story = _story;
    if (story.storyType == 'video' && story.mediaId != null) {
      final session = ref.read(authenticatedSessionProvider);
      final url = resolveMediaUrl(story.mediaId, existingUrl: story.mediaUrl);
      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: session.token != null ? {'Authorization': 'Bearer ${session.token}'} : {},
      );
      _video = ctrl;
      ctrl.initialize().then((_) {
        if (!mounted) return;
        ctrl.play();
        setState(() {});
        _startProgress(ctrl.value.duration.inMilliseconds / 1000.0);
      }).catchError((_) {
        if (mounted) _startProgress(5);
      });
    } else {
      _startProgress(5);
    }
    if (mounted) setState(() {});
  }

  void _startProgress(double seconds) {
    _timer?.cancel();
    const step = Duration(milliseconds: 50);
    final total = (seconds * 1000 / step.inMilliseconds).ceil().clamp(1, 100000);
    var tick = 0;
    _timer = Timer.periodic(step, (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_paused) return;
      tick++;
      setState(() => _progress = (tick / total).clamp(0.0, 1.0));
      if (tick >= total) {
        t.cancel();
        _next();
      }
    });
  }

  Future<void> _markSeen() async {
    try {
      final api = ref.read(authenticatedSessionProvider).api;
      await api.post('/stories/${_story.id}/view', {});
    } catch (_) {}
  }

  void _next() {
    if (_storyIndex + 1 < _group.stories.length) {
      setState(() => _storyIndex++);
      _openCurrent();
    } else if (_groupIndex + 1 < widget.groups.length) {
      setState(() {
        _groupIndex++;
        _storyIndex = 0;
      });
      _openCurrent();
    } else {
      if (mounted) Navigator.pop(context);
    }
  }

  void _prev() {
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
      _openCurrent();
    } else if (_groupIndex > 0) {
      setState(() {
        _groupIndex--;
        _storyIndex = widget.groups[_groupIndex].stories.length - 1;
      });
      _openCurrent();
    } else {
      _openCurrent();
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف استوری'),
        content: const Text('این استوری حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('خیر')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final api = ref.read(authenticatedSessionProvider).api;
      await api.post('/stories/${_story.id}/delete', {});
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    final myId = ref.watch(authNotifierProvider).valueOrNull?.id;
    final story = _story;
    final author = story.author ?? _group.user;
    final isMine = author.id == myId;
    final session = ref.watch(authenticatedSessionProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onLongPressStart: (_) => setState(() => _paused = true),
          onLongPressEnd: (_) => setState(() => _paused = false),
          child: Stack(
            children: [
              // Content
              Positioned.fill(
                child: _buildContent(story, session.token),
              ),
              // Tap zones
              Positioned.fill(
                child: Row(children: [
                  Expanded(child: GestureDetector(onTap: _prev, child: Container(color: Colors.transparent))),
                  Expanded(child: GestureDetector(onTap: _next, child: Container(color: Colors.transparent))),
                ]),
              ),
              // Top: progress + header
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: List.generate(_group.stories.length, (i) {
                          double value = 0;
                          if (i < _storyIndex) {
                            value = 1;
                          } else if (i == _storyIndex) {
                            value = _progress;
                          }
                          return Expanded(
                            child: Container(
                              height: 3,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              child: LinearProgressIndicator(
                                value: value,
                                backgroundColor: Colors.white30,
                                valueColor: const AlwaysStoppedAnimation(Colors.white),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        CircleAvatar(
                          radius: 18,
                          child: Text(author.displayName.isNotEmpty ? author.displayName[0] : '?'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(author.displayName,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                              Text(
                                _timeAgo(story.createdAt),
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        if (isMine)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.white),
                            onPressed: _delete,
                          ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
              // Bottom: caption + views
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (story.content?.isNotEmpty == true)
                        Text(story.content!,
                            style: const TextStyle(color: Colors.white, fontSize: 15)),
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.visibility_outlined, size: 16, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text('${story.viewsCount} بازدید',
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(StoryModel story, String? token) {
    if (story.storyType == 'text') {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E3A8A), Color(0xFF7C3AED)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(story.content ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, height: 1.5)),
          ),
        ),
      );
    }
    final url = resolveMediaUrl(story.mediaId, existingUrl: story.mediaUrl);
    if (story.storyType == 'video') {
      final ctrl = _video;
      if (ctrl != null && ctrl.value.isInitialized) {
        // A zero/NaN aspect ratio from a broken stream would throw during
        // layout, which is exactly the kind of frame error to avoid here.
        final ratio = ctrl.value.aspectRatio;
        return Center(
          child: AspectRatio(
            aspectRatio: (ratio.isFinite && ratio > 0) ? ratio : 9 / 16,
            child: VideoPlayer(ctrl),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return Center(
      child: CachedNetworkImage(
        imageUrl: url,
        httpHeaders: token == null ? null : {'Authorization': 'Bearer $token'},
        fit: BoxFit.contain,
        placeholder: (_, __) => const CircularProgressIndicator(color: Colors.white),
        errorWidget: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'لحظاتی پیش';
    if (diff.inMinutes < 60) return '${diff.inMinutes} دقیقه پیش';
    if (diff.inHours < 24) return '${diff.inHours} ساعت پیش';
    return '${diff.inDays} روز پیش';
  }
}
