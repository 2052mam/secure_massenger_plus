import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/utils/media_utils.dart';
import '../../../data/services/media_playback_coordinator.dart';
import '../../../data/services/media_download_service.dart';
import 'media_labels.dart';
import 'media_seek_bar.dart';

class VoiceMessagePlayer extends StatefulWidget {
  final String url;
  final String? token;
  final Color? foreground;
  final MediaPlaybackCoordinator? coordinator;

  /// Supplying a player also lets widget tests exercise the real controls
  /// without depending on platform codecs. This widget owns its lifetime.
  final AudioPlayer? player;

  const VoiceMessagePlayer({
    super.key,
    required this.url,
    this.token,
    this.foreground,
    this.coordinator,
    this.player,
  });

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer>
    with WidgetsBindingObserver {
  late final AudioPlayer _player;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  Duration? _dragPosition;
  bool _loading = false;
  bool _loaded = false;
  bool _playing = false;
  bool _completed = false;
  bool _buffering = false;
  bool _failed = false;
  bool _toggling = false;
  bool _downloading = false;
  double _speed = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player = widget.player ?? AudioPlayer(useProxyForRequestHeaders: false);
    _subscriptions.addAll([
      _player.positionStream.listen((position) {
        if (mounted) setState(() => _position = position);
      }),
      _player.durationStream.listen((duration) {
        if (mounted) setState(() => _duration = duration ?? Duration.zero);
      }),
      _player.bufferedPositionStream.listen((buffered) {
        if (mounted) setState(() => _buffered = buffered);
      }),
      _player.playerStateStream.listen((state) {
        if (!mounted) return;
        final completed = state.processingState == ProcessingState.completed;
        setState(() {
          _completed = completed;
          _playing = state.playing && !completed;
          _buffering = state.processingState == ProcessingState.buffering;
        });
        // just_audio keeps `playing` true at EOF. Pause explicitly so seeking
        // after completion doesn't unexpectedly start playback.
        if (completed && state.playing) unawaited(_pause());
      }),
      _player.playbackEventStream.listen(
        (_) {},
        onError: (Object error, StackTrace stack) {
          _showError();
        },
      ),
    ]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_pause());
  }

  Future<void> _pause() async {
    try {
      await _player.pause();
    } catch (_) {
      // Disposing or losing an audio route can race a pause request.
    }
  }

  void _showError() {
    if (!mounted) return;
    unawaited(_pause());
    setState(() {
      _failed = true;
      _loading = false;
      _playing = false;
      _loaded = false;
    });
  }

  Future<void> _toggle() async {
    if (_toggling || _loading) return;
    _toggling = true;
    try {
      if (_playing) {
        await _pause();
        return;
      }
      if (!_loaded) {
        setState(() {
          _loading = true;
          _failed = false;
        });
        if (widget.url.isEmpty) throw StateError('Missing audio URL');
        final duration = await _player
            .setUrl(
              widget.url,
              headers: widget.token == null
                  ? null
                  : {'Authorization': 'Bearer ${widget.token}'},
            )
            .timeout(const Duration(seconds: 30));
        if (!mounted) return;
        setState(() {
          _loaded = true;
          _loading = false;
          _duration = duration ?? Duration.zero;
        });
        await _player.setSpeed(_speed);
      }
      if (!mounted) return;
      if (_completed) await _player.seek(Duration.zero);
      final allowed = await widget.coordinator?.activate(this, _pause) ?? true;
      if (!mounted || !allowed || ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      if (WidgetsBinding.instance.lifecycleState != null &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      // play() resolves at EOF/pause, not when playback starts.
      unawaited(_player.play().catchError((Object error) => _showError()));
    } catch (_) {
      _showError();
    } finally {
      _toggling = false;
    }
  }

  Future<void> _seek(Duration position) async {
    if (!_loaded) return;
    try {
      final target = clampMediaPosition(position, _duration);
      await _player.seek(target);
      if (mounted) {
        setState(() {
          _position = target;
          _dragPosition = null;
          _completed = target >= _duration;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _dragPosition = null);
      _showError();
    }
  }

  Future<void> _setSpeed(double speed) async {
    try {
      await _player.setSpeed(speed);
      if (mounted) setState(() => _speed = speed);
    } catch (_) {
      _showError();
    }
  }

  Future<void> _downloadVoice() async {
    if (_downloading || widget.url.isEmpty) return;
    setState(() => _downloading = true);
    try {
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await MediaDownloadService.downloadMedia(
        mediaUrl: widget.url,
        fileName: fileName,
        token: widget.token,
      );
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ویس ذخیره شد ($fileName)')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در دانلود ویس: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.coordinator?.release(this);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = MediaLabels.of(context);
    final color = widget.foreground ?? Theme.of(context).colorScheme.primary;
    final position = clampMediaPosition(_dragPosition ?? _position, _duration);
    return SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: _loading
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    : IconButton.filledTonal(
                        tooltip: _failed
                            ? labels.retry
                            : _playing
                            ? labels.pause
                            : _completed
                            ? labels.replay
                            : labels.play,
                        onPressed: _toggle,
                        style: IconButton.styleFrom(
                          backgroundColor: color.withValues(alpha: 0.16),
                          foregroundColor: color,
                        ),
                        icon: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (_buffering && _playing)
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: color,
                                ),
                              ),
                            Icon(
                              _failed
                                  ? Icons.refresh
                                  : _playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _failed ? labels.loadError : labels.voice,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        '${formatMediaDuration(position)} / ${_duration > Duration.zero ? formatMediaDuration(_duration) : '—:—'}',
                        style: TextStyle(
                          color: color.withValues(alpha: 0.75),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'دانلود ویس',
                visualDensity: VisualDensity.compact,
                color: color,
                onPressed: _downloading ? null : _downloadVoice,
                icon: _downloading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    : const Icon(Icons.download_rounded, size: 20),
              ),
              PopupMenuButton<double>(
                tooltip: labels.speed,
                initialValue: _speed,
                onSelected: _setSpeed,
                itemBuilder: (_) => [
                  for (final speed in [1.0, 1.5, 2.0])
                    CheckedPopupMenuItem(
                      value: speed,
                      checked: _speed == speed,
                      child: Text(
                        '${speed == speed.roundToDouble() ? speed.toInt() : speed}×',
                      ),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 14,
                  ),
                  child: Text(
                    '${_speed == _speed.roundToDouble() ? _speed.toInt() : _speed}×',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                IconButton(
                  tooltip: labels.rewind,
                  visualDensity: VisualDensity.compact,
                  color: color,
                  onPressed: _loaded
                      ? () => _seek(_position - const Duration(seconds: 10))
                      : null,
                  icon: const Icon(Icons.replay_10_rounded, size: 21),
                ),
                Expanded(
                  child: MediaSeekBar(
                    position: position,
                    duration: _duration,
                    buffered: _buffered,
                    color: color,
                    onChangeStart: _loaded
                        ? (v) => setState(() => _dragPosition = v)
                        : null,
                    onChanged: _loaded
                        ? (v) => setState(() => _dragPosition = v)
                        : null,
                    onChangeEnd: _loaded ? _seek : null,
                  ),
                ),
                IconButton(
                  tooltip: labels.forward,
                  visualDensity: VisualDensity.compact,
                  color: color,
                  onPressed: _loaded
                      ? () => _seek(_position + const Duration(seconds: 10))
                      : null,
                  icon: const Icon(Icons.forward_10_rounded, size: 21),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
