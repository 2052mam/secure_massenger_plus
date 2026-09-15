import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/constants/api_constants.dart';
import '../../core/utils/media_utils.dart';
import '../models/message_model.dart';
import 'storage_service.dart';

/// Telegram-like global music/audio player.
///
/// - One shared [AudioPlayer] for the whole app (chat bubbles pause it).
/// - Queue of voice/audio/music messages with next/previous.
/// - Mini-player state stream for the collapsed bar + full player screen.
/// - Persists across navigation; polling chat lists never steal playback.
class MusicTrack {
  final MessageModel message;
  final String chatTitle;
  const MusicTrack({required this.message, this.chatTitle = ''});

  String get title {
    final m = message;
    if (m.audioTitle?.isNotEmpty == true) return m.audioTitle!;
    if (m.originalName?.isNotEmpty == true) return m.originalName!;
    if (m.content?.isNotEmpty == true && m.messageType == 'text') return m.content!;
    return m.messageType == 'voice' ? 'Voice message' : 'Audio';
  }

  String get artist {
    final m = message;
    if (m.audioArtist?.isNotEmpty == true) return m.audioArtist!;
    return chatTitle.isNotEmpty ? chatTitle : (m.sender?.displayName ?? '');
  }
}

class MusicPlayerState {
  final MusicTrack? current;
  final List<MusicTrack> queue;
  final int index;
  final bool playing;
  final bool loading;
  final Duration position;
  final Duration duration;
  final double speed;
  final int repeatMode; // 0 off, 1 all, 2 one
  final bool shuffle;

  const MusicPlayerState({
    this.current,
    this.queue = const [],
    this.index = 0,
    this.playing = false,
    this.loading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.repeatMode = 0,
    this.shuffle = false,
  });

  bool get hasTrack => current != null;
  bool get hasNext => queue.length > 1;
  bool get hasPrev => queue.length > 1;

  MusicPlayerState copyWith({
    MusicTrack? current,
    List<MusicTrack>? queue,
    int? index,
    bool? playing,
    bool? loading,
    Duration? position,
    Duration? duration,
    double? speed,
    int? repeatMode,
    bool? shuffle,
    bool clearCurrent = false,
  }) {
    return MusicPlayerState(
      current: clearCurrent ? null : (current ?? this.current),
      queue: queue ?? this.queue,
      index: index ?? this.index,
      playing: playing ?? this.playing,
      loading: loading ?? this.loading,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      repeatMode: repeatMode ?? this.repeatMode,
      shuffle: shuffle ?? this.shuffle,
    );
  }
}

class MusicPlayerService {
  static final MusicPlayerService _instance = MusicPlayerService._();
  factory MusicPlayerService() => _instance;
  MusicPlayerService._() {
    _player.positionStream.listen((p) {
      _state = _state.copyWith(position: p);
      _controller.add(_state);
    });
    _player.durationStream.listen((d) {
      _state = _state.copyWith(duration: d ?? Duration.zero);
      _controller.add(_state);
    });
    _player.playerStateStream.listen((s) {
      final completed = s.processingState == ProcessingState.completed;
      if (completed) {
        _onCompleted();
        return;
      }
      _state = _state.copyWith(
        playing: s.playing,
        loading: s.processingState == ProcessingState.loading ||
            s.processingState == ProcessingState.buffering,
      );
      _controller.add(_state);
    });
  }

  final AudioPlayer _player = AudioPlayer();
  final _controller = StreamController<MusicPlayerState>.broadcast();
  MusicPlayerState _state = const MusicPlayerState();
  final _order = <int>[];
  int _orderPos = 0;

  Stream<MusicPlayerState> get stream => _controller.stream;
  MusicPlayerState get state => _state;
  AudioPlayer get player => _player;

  String _urlFor(MessageModel m) {
    final url = resolveMediaUrl(m.mediaId, existingUrl: m.mediaUrl);
    return url;
  }

  Map<String, String>? _headers() {
    final token = StorageService.getToken();
    if (token == null || token.isEmpty) return null;
    return {'Authorization': 'Bearer $token'};
  }

  Future<void> playQueue(List<MusicTrack> tracks, {int startIndex = 0, String? token}) async {
    if (tracks.isEmpty) return;
    _buildOrder(tracks.length, startIndex);
    _state = _state.copyWith(queue: tracks, index: startIndex);
    await _playAt(startIndex, token: token);
  }

  void _buildOrder(int len, int start) {
    _order.clear();
    if (_state.shuffle && len > 1) {
      _order.add(start);
      final rest = List<int>.generate(len, (i) => i)..remove(start)..shuffle();
      _order.addAll(rest);
      _orderPos = 0;
    } else {
      _order.addAll(List<int>.generate(len, (i) => i));
      _orderPos = start;
    }
  }

  Future<void> _playAt(int index, {String? token}) async {
    final queue = _state.queue;
    if (index < 0 || index >= queue.length) return;
    final track = queue[index];
    _state = _state.copyWith(current: track, index: index, loading: true, position: Duration.zero, duration: Duration.zero);
    _controller.add(_state);
    try {
      final url = _urlFor(track.message);
      final headers = token != null && token.isNotEmpty
          ? {'Authorization': 'Bearer $token'}
          : _headers();
      await _player.setUrl(url, headers: headers);
      await _player.setSpeed(_state.speed);
      await _player.play();
    } catch (_) {
      _state = _state.copyWith(loading: false, playing: false);
      _controller.add(_state);
    }
  }

  Future<void> toggle() async {
    if (_state.current == null) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> pause() async {
    if (_player.playing) await _player.pause();
  }

  Future<void> next() async {
    if (_state.queue.length < 2) return;
    if (_state.shuffle) {
      _orderPos = (_orderPos + 1) % _order.length;
      await _playAt(_order[_orderPos]);
    } else {
      await _playAt((_state.index + 1) % _state.queue.length);
    }
  }

  Future<void> previous() async {
    if (_state.queue.length < 2) return;
    if (_positionMoreThan3s) {
      await seek(Duration.zero);
      return;
    }
    if (_state.shuffle) {
      _orderPos = (_orderPos - 1 + _order.length) % _order.length;
      await _playAt(_order[_orderPos]);
    } else {
      final i = _state.index - 1;
      await _playAt(i < 0 ? _state.queue.length - 1 : i);
    }
  }

  bool get _positionMoreThan3s => _state.position.inSeconds > 3;

  Future<void> seek(Duration position) async {
    await _player.seek(clampMediaPosition(position, _state.duration));
  }

  Future<void> seekForward([int seconds = 10]) async {
    await seek(_state.position + Duration(seconds: seconds));
  }

  Future<void> seekBackward([int seconds = 10]) async {
    await seek(_state.position - Duration(seconds: seconds));
  }

  Future<void> cycleSpeed() async {
    const speeds = [1.0, 1.5, 2.0, 0.5];
    final i = speeds.indexOf(_state.speed);
    final next = speeds[(i + 1) % speeds.length];
    _state = _state.copyWith(speed: next);
    _controller.add(_state);
    await _player.setSpeed(next);
  }

  void cycleRepeat() {
    _state = _state.copyWith(repeatMode: (_state.repeatMode + 1) % 3);
    _controller.add(_state);
  }

  void toggleShuffle() {
    final on = !_state.shuffle;
    _state = _state.copyWith(shuffle: on);
    _buildOrder(_state.queue.length, _state.index);
    _controller.add(_state);
  }

  Future<void> _onCompleted() async {
    if (_state.repeatMode == 2) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }
    if (_state.queue.length > 1 && (_state.repeatMode == 1 || _state.index < _state.queue.length - 1 || _state.shuffle)) {
      await next();
      return;
    }
    if (_state.repeatMode == 1 && _state.queue.length == 1) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }
    _state = _state.copyWith(playing: false, position: Duration.zero);
    _controller.add(_state);
  }

  Future<void> close() async {
    await _player.stop();
    _state = _state.copyWith(clearCurrent: true, queue: const [], index: 0, playing: false, loading: false, position: Duration.zero, duration: Duration.zero);
    _controller.add(_state);
  }

  /// Called by chat bubbles so voice notes and music never overlap.
  Future<void> pauseForExternal() => pause();

  void dispose() {
    _player.dispose();
    _controller.close();
  }
}
