import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../data/services/media_playback_coordinator.dart';
import 'media_labels.dart';
import 'video_playback_controls.dart';

class VideoMessagePlayer extends StatefulWidget {
  final String url;
  final String? authToken;
  final bool isMine;
  final MediaPlaybackCoordinator? coordinator;
  final VideoPlayerController Function(Uri, Map<String, String>)?
  controllerFactory;

  /// Editor-muted videos play silently; the volume toggle stays locked off.
  final bool muted;

  const VideoMessagePlayer({
    super.key,
    required this.url,
    this.authToken,
    this.isMine = false,
    this.coordinator,
    this.controllerFactory,
    this.muted = false,
  });

  @override
  State<VideoMessagePlayer> createState() => _VideoMessagePlayerState();
}

class _VideoMessagePlayerState extends State<VideoMessagePlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _error = false;
  bool _ready = false;
  bool _fullscreen = false;
  MaterialPageRoute<void>? _fullscreenRoute;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_init());
  }

  @override
  void didUpdateWidget(covariant VideoMessagePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.authToken != widget.authToken) {
      unawaited(_init());
    }
  }

  Future<void> _init() async {
    final generation = ++_generation;
    final previous = _controller;
    _controller = null;
    widget.coordinator?.release(this);
    setState(() {
      _ready = false;
      _error = false;
    });
    if (previous != null) {
      try {
        // Retry can start while the full-screen pop animation is finishing.
        await _fullscreenRoute?.completed;
        await previous.dispose();
      } catch (_) {}
    }
    if (!mounted || generation != _generation) return;
    final headers = <String, String>{
      if (widget.authToken != null)
        'Authorization': 'Bearer ${widget.authToken}',
    };
    final controller =
        widget.controllerFactory?.call(Uri.parse(widget.url), headers) ??
        VideoPlayerController.networkUrl(
          Uri.parse(widget.url),
          httpHeaders: headers,
        );
    _controller = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 30));
      if (!mounted || generation != _generation) return;
      if (widget.muted) {
        try {
          await controller.setVolume(0);
        } catch (_) {}
      }
      setState(() => _ready = true);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = true);
    }
  }

  Future<void> _pause() async {
    try {
      await _controller?.pause();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_pause());
  }

  Future<void> _openFullscreen({bool autoplay = false}) async {
    final controller = _controller;
    if (_fullscreen || !_ready || controller == null) return;
    setState(() => _fullscreen = true);
    try {
      final route = MaterialPageRoute<void>(
        builder: (_) => _FullscreenVideo(
          controller: controller,
          coordinator: widget.coordinator,
          playbackOwner: this,
          autoplay: autoplay,
          onRetry: () {
            if (mounted) unawaited(_init());
          },
        ),
      );
      _fullscreenRoute = route;
      await Navigator.of(context).push(route);
      await route.completed;
    } finally {
      _fullscreenRoute = null;
      // Leaving the video stops it, exactly like closing a Telegram video.
      // A disposed player already paused and released its controller.
      if (mounted) {
        try {
          unawaited(controller.pause().catchError((Object _) {}));
        } catch (_) {}
        // The SAME controller retains playback position, speed and volume.
        setState(() => _fullscreen = false);
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    widget.coordinator?.release(this);
    final controller = _controller;
    final route = _fullscreenRoute;
    if (route != null && controller != null) {
      // Live deletion can remove this bubble while full screen still uses its
      // controller. Close that route, then dispose after its controls detach.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(controller.pause().catchError((Object _) {}));
        final navigator = route.navigator;
        if (navigator != null && navigator.mounted && route.isActive) {
          navigator.removeRoute(route);
        }
      });
      unawaited(
        route.completed
            .then((_) async {
              await controller.dispose();
            })
            .catchError((Object _) {}),
      );
    } else {
      unawaited(controller?.dispose().catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = MediaLabels.of(context);
    final controller = _controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = _ready && controller != null
            ? controller.value.aspectRatio
            : 16 / 9;
        final safeRatio = ratio.isFinite && ratio > 0 ? ratio : 16 / 9;
        // Preserve the source's aspect ratio inside the surface. A minimum
        // control height keeps landscape clips usable even on narrow phones.
        final height = (constraints.maxWidth / safeRatio)
            .clamp(190.0, 340.0)
            .toDouble();
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: double.infinity,
            height: height,
            child: ColoredBox(
              color: Colors.black,
              child: _fullscreen
                  ? Center(
                      child: Text(
                        labels.fullscreen,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )
                  : _error
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.videocam_off_outlined,
                            color: Colors.white70,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            labels.loadError,
                            style: const TextStyle(color: Colors.white),
                          ),
                          TextButton.icon(
                            onPressed: _init,
                            icon: const Icon(Icons.refresh),
                            label: Text(labels.retry),
                          ),
                        ],
                      ),
                    )
                  : !_ready || controller == null
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: AspectRatio(
                            aspectRatio: safeRatio,
                            child: VideoPlayer(controller),
                          ),
                        ),
                        VideoPlaybackControls(
                          controller: controller,
                          coordinator: widget.coordinator,
                          playbackOwner: this,
                          autoFullscreenOnPlay: true,
                          volumeLocked: widget.muted,
                          onFullscreen: _openFullscreen,
                          onPlayFullscreen: () =>
                              _openFullscreen(autoplay: true),
                          onRetry: _init,
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _FullscreenVideo extends StatefulWidget {
  final VideoPlayerController controller;
  final MediaPlaybackCoordinator? coordinator;
  final Object playbackOwner;
  final VoidCallback onRetry;
  final bool autoplay;

  const _FullscreenVideo({
    required this.controller,
    required this.playbackOwner,
    required this.onRetry,
    this.coordinator,
    this.autoplay = false,
    this.volumeLocked = false,
  });

  final bool volumeLocked;

  @override
  State<_FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<_FullscreenVideo>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(widget.controller.pause().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Exiting full screen stops the video instead of leaving it running
    // behind the chat, the way Telegram closes a video.
    try {
      unawaited(widget.controller.pause().catchError((Object _) {}));
    } catch (_) {}
    // Restore the app's portrait-only policy on every exit (including Back).
    unawaited(
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]),
    );
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: widget.controller.value.aspectRatio,
              child: VideoPlayer(widget.controller),
            ),
          ),
          VideoPlaybackControls(
            controller: widget.controller,
            coordinator: widget.coordinator,
            playbackOwner: widget.playbackOwner,
            fullscreen: true,
            autoPlay: widget.autoplay,
            volumeLocked: widget.volumeLocked,
            onFullscreen: () => Navigator.of(context).pop(),
            onRetry: () {
              Navigator.of(context).pop();
              widget.onRetry();
            },
          ),
        ],
      ),
    );
  }
}
