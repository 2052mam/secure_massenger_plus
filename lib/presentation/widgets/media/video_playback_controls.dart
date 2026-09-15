import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/utils/media_utils.dart';
import '../../../data/services/media_playback_coordinator.dart';
import 'media_labels.dart';
import 'media_seek_bar.dart';

class VideoPlaybackControls extends StatefulWidget {
  final VideoPlayerController controller;
  final MediaPlaybackCoordinator? coordinator;
  final Object playbackOwner;
  final bool fullscreen;
  final VoidCallback onFullscreen;
  final VoidCallback onRetry;

  /// Telegram behaviour: pressing play on an inline video opens the player
  /// full screen instead of starting a tiny preview inside the bubble.
  final bool autoFullscreenOnPlay;

  /// Start playing as soon as these controls appear (used by the full screen
  /// route opened from an inline play press).
  final bool autoPlay;

  /// Called instead of [onFullscreen] when full screen was requested by
  /// pressing play, so the opened route can start playback immediately.
  final VoidCallback? onPlayFullscreen;

  /// Editor-muted videos: volume stays locked at 0 (sender's choice).
  final bool volumeLocked;

  const VideoPlaybackControls({
    super.key,
    required this.controller,
    required this.playbackOwner,
    required this.onFullscreen,
    required this.onRetry,
    this.coordinator,
    this.fullscreen = false,
    this.autoFullscreenOnPlay = false,
    this.autoPlay = false,
    this.onPlayFullscreen,
    this.volumeLocked = false,
  });

  @override
  State<VideoPlaybackControls> createState() => _VideoPlaybackControlsState();
}

class _VideoPlaybackControlsState extends State<VideoPlaybackControls> {
  Timer? _hideTimer;
  Timer? _feedbackTimer;
  bool _visible = true;
  bool _wasPlaying = false;
  bool _failed = false;
  bool _toggling = false;
  Duration? _dragPosition;
  int? _skipFeedback;
  double _doubleTapX = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_playbackChanged);
    _playbackChanged();
    if (widget.autoPlay && !widget.controller.value.isPlaying) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_togglePlayback());
      });
    }
  }

  @override
  void didUpdateWidget(covariant VideoPlaybackControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_playbackChanged);
      widget.controller.addListener(_playbackChanged);
      _failed = false;
      _dragPosition = null;
      _playbackChanged();
    }
  }

  bool _atEnd(VideoPlayerValue value) =>
      value.isCompleted ||
      (value.duration > Duration.zero && value.position >= value.duration);

  void _playbackChanged() {
    final playing =
        widget.controller.value.isPlaying && !_atEnd(widget.controller.value);
    if (playing && !_wasPlaying) _scheduleHide();
    if (!playing && _wasPlaying) {
      _hideTimer?.cancel();
      if (mounted) setState(() => _visible = true);
    }
    _wasPlaying = playing;
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.controller.value.isPlaying || _dragPosition != null) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _toggleChrome() {
    setState(() => _visible = !_visible);
    if (_visible) _scheduleHide();
  }

  Future<void> _pause() async {
    try {
      await widget.controller.pause();
    } catch (_) {}
  }

  Future<void> _togglePlayback() async {
    if (_toggling) return;
    _toggling = true;
    try {
      final value = widget.controller.value;
      if (value.isPlaying && !_atEnd(value)) {
        await _pause();
      } else if (widget.autoFullscreenOnPlay && !widget.fullscreen) {
        // Playback itself starts in the full screen route.
        (widget.onPlayFullscreen ?? widget.onFullscreen)();
        return;
      } else {
        if (_atEnd(value)) await widget.controller.seekTo(Duration.zero);
        final allowed =
            await widget.coordinator?.activate(widget.playbackOwner, _pause) ??
            true;
        if (!mounted ||
            !allowed ||
            ModalRoute.of(context)?.isCurrent == false) {
          return;
        }
        final lifecycle = WidgetsBinding.instance.lifecycleState;
        if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
        await widget.controller.play();
      }
      _scheduleHide();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _toggling = false;
    }
  }

  Future<void> _seek(Duration position) async {
    try {
      await widget.controller.seekTo(
        clampMediaPosition(position, widget.controller.value.duration),
      );
      if (!mounted) return;
      setState(() => _dragPosition = null);
      _scheduleHide();
    } catch (_) {
      if (mounted)
        setState(() {
          _dragPosition = null;
          _failed = true;
        });
    }
  }

  void _skip(int seconds) {
    setState(() {
      _skipFeedback = seconds;
      _visible = true;
    });
    unawaited(
      _seek(widget.controller.value.position + Duration(seconds: seconds)),
    );
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 750), () {
      if (mounted) setState(() => _skipFeedback = null);
    });
  }

  Future<void> _speed(double speed) async {
    try {
      await widget.controller.setPlaybackSpeed(speed);
      _scheduleHide();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _volume() async {
    if (widget.volumeLocked) {
      try {
        await widget.controller.setVolume(0);
      } catch (_) {}
      return;
    }
    try {
      await widget.controller.setVolume(
        widget.controller.value.volume == 0 ? 1 : 0,
      );
      _scheduleHide();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_playbackChanged);
    _hideTimer?.cancel();
    _feedbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = MediaLabels.of(context);
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        if (_failed || value.hasError) {
          return ColoredBox(
            color: Colors.black87,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    labels.loadError,
                    style: const TextStyle(color: Colors.white),
                  ),
                  TextButton.icon(
                    onPressed: widget.onRetry,
                    icon: const Icon(Icons.refresh),
                    label: Text(labels.retry),
                  ),
                  if (widget.fullscreen)
                    TextButton(
                      onPressed: widget.onFullscreen,
                      child: Text(labels.close),
                    ),
                ],
              ),
            ),
          );
        }
        final atEnd = _atEnd(value);
        final playing = value.isPlaying && !atEnd;
        final visible = _visible || !playing || _dragPosition != null;
        final position = clampMediaPosition(
          _dragPosition ?? value.position,
          value.duration,
        );
        final buffered = value.buffered.fold<Duration>(
          Duration.zero,
          (end, range) => range.end > end ? range.end : end,
        );
        final speed = value.playbackSpeed;
        return Directionality(
          textDirection: TextDirection.ltr,
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleChrome,
              onDoubleTapDown: (details) =>
                  _doubleTapX = details.localPosition.dx,
              onDoubleTap: () =>
                  _skip(_doubleTapX < constraints.maxWidth / 2 ? -10 : 10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (value.isBuffering)
                    const Center(
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: CircularProgressIndicator(
                          color: Colors.white70,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  if (_skipFeedback != null)
                    Align(
                      alignment: _skipFeedback! < 0
                          ? const Alignment(-0.7, -0.25)
                          : const Alignment(0.7, -0.25),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            '${_skipFeedback! > 0 ? '+' : ''}$_skipFeedback s',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  IgnorePointer(
                    ignoring: !visible,
                    child: AnimatedOpacity(
                      opacity: visible ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black54,
                              Colors.transparent,
                              Colors.black87,
                            ],
                            stops: [0, 0.4, 1],
                          ),
                        ),
                        child: SafeArea(
                          top: widget.fullscreen,
                          bottom: widget.fullscreen,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Align(
                                alignment: Alignment.topCenter,
                                child: Row(
                                  children: [
                                    if (widget.fullscreen)
                                      IconButton(
                                        tooltip: labels.close,
                                        onPressed: widget.onFullscreen,
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                        ),
                                      )
                                    else
                                      const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        labels.video,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    PopupMenuButton<double>(
                                      tooltip: labels.speed,
                                      initialValue: speed,
                                      onOpened: () => _hideTimer?.cancel(),
                                      onCanceled: _scheduleHide,
                                      onSelected: _speed,
                                      itemBuilder: (_) => [
                                        for (final rate in [
                                          0.5,
                                          1.0,
                                          1.25,
                                          1.5,
                                          2.0,
                                        ])
                                          CheckedPopupMenuItem(
                                            value: rate,
                                            checked: rate == speed,
                                            child: Text('$rate×'),
                                          ),
                                      ],
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        child: Text(
                                          '${speed == speed.roundToDouble() ? speed.toInt() : speed}×',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Align(
                                alignment: const Alignment(0, -0.15),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: labels.rewind,
                                      onPressed: () => _skip(-10),
                                      iconSize: widget.fullscreen ? 32 : 25,
                                      icon: const Icon(
                                        Icons.replay_10_rounded,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      tooltip: playing
                                          ? labels.pause
                                          : atEnd
                                          ? labels.replay
                                          : labels.play,
                                      onPressed: _togglePlayback,
                                      iconSize: widget.fullscreen ? 64 : 40,
                                      icon: Icon(
                                        playing
                                            ? Icons.pause_rounded
                                            : atEnd
                                            ? Icons.replay_rounded
                                            : Icons.play_arrow_rounded,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      tooltip: labels.forward,
                                      onPressed: () => _skip(10),
                                      iconSize: widget.fullscreen ? 32 : 25,
                                      icon: const Icon(
                                        Icons.forward_10_rounded,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      height: 28,
                                      child: MediaSeekBar(
                                        position: position,
                                        duration: value.duration,
                                        buffered: buffered,
                                        color: Colors.white,
                                        onChangeStart: (v) {
                                          _hideTimer?.cancel();
                                          setState(() => _dragPosition = v);
                                        },
                                        onChanged: (v) =>
                                            setState(() => _dragPosition = v),
                                        onChangeEnd: _seek,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 12,
                                        right: 2,
                                        bottom: 2,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${formatMediaDuration(position)} / ${formatMediaDuration(value.duration)}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: value.volume == 0
                                                ? labels.unmute
                                                : labels.mute,
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: _volume,
                                            icon: Icon(
                                              value.volume == 0
                                                  ? Icons.volume_off_rounded
                                                  : Icons.volume_up_rounded,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: widget.fullscreen
                                                ? labels.exitFullscreen
                                                : labels.fullscreen,
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: widget.onFullscreen,
                                            icon: Icon(
                                              widget.fullscreen
                                                  ? Icons
                                                        .fullscreen_exit_rounded
                                                  : Icons.fullscreen_rounded,
                                              color: Colors.white,
                                              size: 24,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
