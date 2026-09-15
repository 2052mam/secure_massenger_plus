import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../core/utils/media_utils.dart';

class VideoNotePlayer extends StatefulWidget {
  final String url;
  final String? authToken;
  final double size;

  const VideoNotePlayer({super.key, required this.url, this.authToken, this.size = 220});

  @override
  State<VideoNotePlayer> createState() => _VideoNotePlayerState();
}

class _VideoNotePlayerState extends State<VideoNotePlayer> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final uri = Uri.parse(widget.url);
      final headers = widget.authToken != null ? {'Authorization': 'Bearer ${widget.authToken}'} : <String, String>{};
      _controller = VideoPlayerController.networkUrl(uri, httpHeaders: headers);
      await _controller!.initialize();
      _controller!.setLooping(true);
      setState(() => _initialized = true);
    } catch (_) {
      setState(() => _initialized = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_controller == null || !_initialized) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      setState(() => _isPlaying = false);
    } else {
      _controller!.play();
      setState(() => _isPlaying = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_initialized && _controller != null)
              SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                ),
              )
            else
              const Icon(Icons.videocam, color: Colors.white70, size: 48),
            if (!_isPlaying)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
              ),
            Positioned(
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam, size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(_controller != null && _initialized ? formatMediaDuration(_controller!.value.duration) : '0:00', style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
