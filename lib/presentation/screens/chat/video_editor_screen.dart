import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Result of editing a video: the original file plus edit instructions.
/// Trimming is applied server-side (ffmpeg) at upload; [muted] is enforced
/// at playback by every client, so a muted video stays silent everywhere.
class EditedVideo {
  final File file;
  final int startMs;
  final int endMs; // -1 = until the end
  final bool muted;
  const EditedVideo({
    required this.file,
    this.startMs = 0,
    this.endMs = -1,
    this.muted = false,
  });

  bool get isTrimmed => startMs > 0 || endMs >= 0;
  bool get isEdited => isTrimmed || muted;
}

/// Telegram-like internal video editor: preview, trim start/end, mute toggle.
/// Returns an [EditedVideo] via Navigator.pop.
///
/// The previous version had no listener on the controller, so the UI never
/// reflected real playback state, and it issued a `seekTo` on every slider
/// tick which flooded the decoder. This version keeps a single source of
/// truth: the controller drives the UI, the UI drives the controller once per
/// gesture, and playback is confined to the selected trim window.
class VideoEditorScreen extends StatefulWidget {
  final File videoFile;
  const VideoEditorScreen({super.key, required this.videoFile});

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  /// A trim window shorter than this makes no sense (and breaks ffmpeg).
  static const _minTrimMs = 500;

  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;
  bool _muted = false;

  Duration _total = Duration.zero;
  Duration _start = Duration.zero;
  Duration _end = Duration.zero;
  Duration _position = Duration.zero;

  bool _scrubbing = false;
  Timer? _seekDebounce;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.file(widget.videoFile);
    _controller = c;
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      final duration = c.value.duration;
      if (duration <= Duration.zero) {
        setState(() {
          _failed = true;
          _ready = false;
        });
        return;
      }
      c.addListener(_onControllerTick);
      await c.setLooping(false);
      setState(() {
        _ready = true;
        _total = duration;
        _start = Duration.zero;
        _end = duration;
        _position = Duration.zero;
      });
      await c.play();
    } catch (_) {
      if (mounted) {
        setState(() {
          _ready = false;
          _failed = true;
        });
      }
    }
  }

  /// Single place where playback state reaches the UI.
  void _onControllerTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized || !mounted) return;
    final pos = c.value.position;

    // Keep playback inside the trim window: loop back to the start.
    if (!_scrubbing && c.value.isPlaying) {
      if (pos >= _end) {
        c.seekTo(_start);
        return;
      }
      if (pos < _start - const Duration(milliseconds: 300)) {
        c.seekTo(_start);
        return;
      }
    }
    // Only rebuild when the visible playhead actually moved (~10 fps), so the
    // controller's high-frequency ticks cannot thrash the widget tree.
    if ((pos - _position).abs() >= const Duration(milliseconds: 100) ||
        pos == Duration.zero) {
      setState(() => _position = pos);
    }
  }

  @override
  void dispose() {
    _seekDebounce?.cancel();
    final c = _controller;
    _controller = null;
    c?.removeListener(_onControllerTick);
    c?.dispose();
    super.dispose();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _controller?.setVolume(_muted ? 0 : 1);
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      if (c.value.position >= _end || c.value.position < _start) {
        await c.seekTo(_start);
      }
      await c.play();
    }
    if (mounted) setState(() {});
  }

  /// Debounced seek: the decoder is only asked once the user pauses moving.
  void _seekDebounced(Duration to) {
    _seekDebounce?.cancel();
    _seekDebounce = Timer(const Duration(milliseconds: 60), () {
      _controller?.seekTo(to);
    });
  }

  void _onRangeChanged(RangeValues values) {
    final startMs = values.start.round();
    final endMs = values.end.round();
    // Guarantee a valid, non-inverted window.
    if (endMs - startMs < _minTrimMs) return;
    final movedStart = (startMs - _start.inMilliseconds).abs() >
        (endMs - _end.inMilliseconds).abs();
    setState(() {
      _scrubbing = true;
      _start = Duration(milliseconds: startMs);
      _end = Duration(milliseconds: endMs);
    });
    _seekDebounced(movedStart ? _start : _end);
  }

  Future<void> _onRangeChangeEnd(RangeValues values) async {
    setState(() => _scrubbing = false);
    final c = _controller;
    if (c == null) return;
    if (c.value.position < _start || c.value.position > _end) {
      await c.seekTo(_start);
    }
  }

  void _onPositionChanged(double ms) {
    setState(() {
      _scrubbing = true;
      _position = Duration(milliseconds: ms.round());
    });
    _seekDebounced(_position);
  }

  String _fmt(Duration d) {
    final safe = d.isNegative ? Duration.zero : d;
    final m = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _done() {
    final endMs = _end.inMilliseconds >= _total.inMilliseconds - 200
        ? -1
        : _end.inMilliseconds;
    Navigator.pop(
      context,
      EditedVideo(
        file: widget.videoFile,
        startMs: _start.inMilliseconds,
        endMs: endMs,
        muted: _muted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final playing = c?.value.isPlaying ?? false;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('ویرایش ویدیو'),
        actions: [
          IconButton(
            tooltip: _muted ? 'با صدا' : 'بی‌صدا',
            icon: Icon(_muted ? Icons.volume_off : Icons.volume_up,
                color: _muted ? Colors.amber : Colors.white),
            onPressed: _ready ? _toggleMute : null,
          ),
          IconButton(
            tooltip: 'تأیید',
            icon: const Icon(Icons.check, color: Colors.green),
            onPressed: _ready ? _done : null,
          ),
        ],
      ),
      body: _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.videocam_off_outlined,
                      color: Colors.white38, size: 48),
                  const SizedBox(height: 8),
                  const Text('این ویدیو قابل پیش‌نمایش نیست',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      EditedVideo(file: widget.videoFile),
                    ),
                    child: const Text('ارسال بدون ویرایش'),
                  ),
                ],
              ),
            )
          : !_ready || c == null
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white))
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: c.value.aspectRatio <= 0
                              ? 16 / 9
                              : c.value.aspectRatio,
                          child: GestureDetector(
                            onTap: _togglePlay,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                VideoPlayer(c),
                                AnimatedOpacity(
                                  opacity: playing ? 0 : 0.85,
                                  duration: const Duration(milliseconds: 180),
                                  child: const CircleAvatar(
                                    radius: 28,
                                    backgroundColor: Colors.black54,
                                    child: Icon(Icons.play_arrow,
                                        color: Colors.white, size: 36),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      color: Colors.grey.shade900,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('شروع: ${_fmt(_start)}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                              Text('پایان: ${_fmt(_end)}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                              Text('مدت: ${_fmt(_end - _start)}',
                                  style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Playhead
                          Row(children: [
                            IconButton(
                              icon: Icon(
                                playing
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_fill,
                                color: Colors.white,
                              ),
                              onPressed: _togglePlay,
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2,
                                  thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6),
                                ),
                                child: Slider(
                                  value: _position.inMilliseconds
                                      .clamp(0, _total.inMilliseconds)
                                      .toDouble(),
                                  min: 0,
                                  max: _total.inMilliseconds.toDouble(),
                                  onChanged: _onPositionChanged,
                                  onChangeEnd: (_) =>
                                      setState(() => _scrubbing = false),
                                ),
                              ),
                            ),
                            Text(_fmt(_position),
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 11)),
                          ]),
                          const SizedBox(height: 2),
                          Row(children: [
                            const Icon(Icons.content_cut,
                                color: Colors.white54, size: 16),
                            const SizedBox(width: 6),
                            const Text('برش',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 11)),
                            Expanded(
                              child: RangeSlider(
                                values: RangeValues(
                                  _start.inMilliseconds
                                      .clamp(0, _total.inMilliseconds)
                                      .toDouble(),
                                  _end.inMilliseconds
                                      .clamp(0, _total.inMilliseconds)
                                      .toDouble(),
                                ),
                                min: 0,
                                max: _total.inMilliseconds.toDouble(),
                                labels: RangeLabels(_fmt(_start), _fmt(_end)),
                                activeColor: Colors.greenAccent,
                                onChanged: _onRangeChanged,
                                onChangeEnd: _onRangeChangeEnd,
                              ),
                            ),
                          ]),
                          if (_muted)
                            const Row(children: [
                              Icon(Icons.volume_off,
                                  color: Colors.amber, size: 16),
                              SizedBox(width: 6),
                              Text('ویدیو بدون صدا ارسال می‌شود',
                                  style: TextStyle(
                                      color: Colors.amber, fontSize: 12)),
                            ]),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
