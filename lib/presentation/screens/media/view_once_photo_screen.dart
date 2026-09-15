import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../data/services/api_service.dart';
import '../../../data/services/screen_privacy_service.dart';
import '../../widgets/media/media_labels.dart';
import '../../widgets/media/photo_canvas.dart';

/// The server's single-use claim response for a view-once / timed photo.
class ViewOnceClaim {
  final DateTime viewedAt;
  final DateTime? viewExpiresAt;
  const ViewOnceClaim({required this.viewedAt, this.viewExpiresAt});
}

/// Download -> validate/decode -> atomically claim -> reveal.
/// No disk cache, no thumbnail, no forwarding, and no claim on a failed load.
///
/// Timed photos (Item 2) additionally auto-close [viewDuration] seconds after
/// the claim, with a Telegram-style countdown ring in the top bar.
class ViewOncePhotoScreen extends StatefulWidget {
  final Future<Uint8List> Function() loadPhoto;
  final Future<ViewOnceClaim> Function() consumePhoto;
  final ValueChanged<ViewOnceClaim> onViewed;

  /// Seconds the photo stays visible after opening. Null = classic
  /// view-once (visible until the screen is closed or backgrounded).
  final int? viewDuration;

  /// Server deadline if the photo was already consumed on another device.
  final DateTime? viewExpiresAt;

  const ViewOncePhotoScreen({
    super.key,
    required this.loadPhoto,
    required this.consumePhoto,
    required this.onViewed,
    this.viewDuration,
    this.viewExpiresAt,
  });

  @override
  State<ViewOncePhotoScreen> createState() => _ViewOncePhotoScreenState();
}

class _ViewOncePhotoScreenState extends State<ViewOncePhotoScreen>
    with WidgetsBindingObserver {
  ui.Image? _photo;
  bool _loading = true;
  bool _unavailable = false;
  bool _obscured = false;
  Future<void> Function()? _releasePrivacy;
  int _generation = 0;
  Timer? _countdownTimer;
  DateTime? _deadline;
  Duration _remaining = Duration.zero;

  bool get _timed => (widget.viewDuration ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Already consumed elsewhere with an unexpired deadline: resume its
    // countdown without re-claiming (the server would return 410).
    final deadline = widget.viewExpiresAt;
    if (deadline != null && deadline.isAfter(DateTime.now())) {
      _deadline = deadline;
    }
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    final generation = ++_generation;
    ui.Image? preparedImage;
    setState(() {
      _loading = true;
      _unavailable = false;
    });
    try {
      if (_releasePrivacy == null) {
        final release = await ScreenPrivacyService.acquire();
        if (!mounted || generation != _generation) {
          await release();
          return;
        }
        _releasePrivacy = release;
      }
      final bytes = await widget.loadPhoto();
      if (!mounted || generation != _generation) return;
      // Validate a real frame before claiming. Broken/truncated image bytes
      // must leave the photo unopened and retryable on the server.
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        preparedImage = frame.image;
      } finally {
        codec.dispose();
      }
      if (!mounted || _obscured || generation != _generation) return;
      final claim = await widget.consumePhoto();
      widget.onViewed(claim);
      if (!mounted || _obscured || generation != _generation) return;
      // The server deadline wins over local clock math.
      final serverDeadline =
          claim.viewExpiresAt ?? _deadline ?? _fallbackDeadline(claim);
      if (!mounted || _obscured || generation != _generation) return;
      setState(() {
        // Use the already decoded frame: revealing cannot trigger a second
        // decode/network request after the successful single-use claim.
        _photo = preparedImage;
        preparedImage = null;
        _loading = false;
      });
      if (_timed) _startCountdown(serverDeadline);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _unavailable =
            error is ApiException && [403, 404, 410].contains(error.statusCode);
      });
    } finally {
      // Also free prepared pixels on a lost claim, close, or stale retry.
      preparedImage?.dispose();
    }
  }

  DateTime? _fallbackDeadline(ViewOnceClaim claim) {
    final duration = widget.viewDuration;
    if (duration == null || duration <= 0) return null;
    return claim.viewedAt.add(Duration(seconds: duration));
  }

  void _startCountdown(DateTime? deadline) {
    _countdownTimer?.cancel();
    if (deadline == null) return;
    _deadline = deadline;
    _tick();
    _countdownTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _tick(),
    );
  }

  void _tick() {
    final deadline = _deadline;
    if (deadline == null || !mounted || _obscured) return;
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _countdownTimer?.cancel();
      _close();
      return;
    }
    setState(() => _remaining = remaining);
  }

  void _obscure() {
    ++_generation;
    _countdownTimer?.cancel();
    if (mounted) setState(() => _obscured = true);
  }

  void _close() {
    _obscure();
    Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted && !_obscured) {
      _obscure();
      // Cover synchronously before the app switcher snapshot / pop animation.
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    ++_generation;
    _countdownTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final photo = _photo;
    _photo = null;
    photo?.dispose();
    final release = _releasePrivacy;
    _releasePrivacy = null;
    if (release != null) unawaited(release().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = MediaLabels.of(context);
    final total = widget.viewDuration ?? 0;
    final progress = !_timed || total <= 0
        ? 1.0
        : (_remaining.inMilliseconds / (total * 1000)).clamp(0.0, 1.0);
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && !_obscured) _obscure();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (!_obscured && _photo != null)
              PhotoCanvas(decodedImage: _photo!)
            else if (!_obscured && _loading)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            else if (!_obscured)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _unavailable
                            ? Icons.timer_off_outlined
                            : Icons.broken_image_outlined,
                        color: Colors.white70,
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _unavailable ? labels.expired : labels.loadError,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                      if (!_unavailable)
                        TextButton(
                          onPressed: _prepare,
                          child: Text(labels.retry),
                        ),
                    ],
                  ),
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ColoredBox(
                color: Colors.black54,
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: labels.close,
                        onPressed: _close,
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                      if (_timed && !_obscured && _photo != null)
                        _CountdownBadge(
                          remaining: _remaining,
                          progress: progress,
                        )
                      else
                        const Icon(
                          Icons.timer_outlined,
                          color: Colors.white70,
                          size: 20,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _timed
                              ? 'عکس زمان‌دار (${widget.viewDuration} ثانیه)'
                              : labels.viewOnce,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ColoredBox(
                color: Colors.black54,
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.all(16),
                  child: Text(
                    _timed
                        ? 'این عکس ${_remaining.inSeconds + 1} ثانیه دیگر بسته می‌شود و دوباره باز نخواهد شد.'
                        : labels.disappears,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Telegram-style countdown ring with the remaining seconds in the middle.
class _CountdownBadge extends StatelessWidget {
  final Duration remaining;
  final double progress;
  const _CountdownBadge({required this.remaining, required this.progress});

  @override
  Widget build(BuildContext context) {
    final seconds = remaining.inSeconds + 1;
    return SizedBox(
      width: 34,
      height: 34,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 3,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
            ),
          ),
          Text(
            '$seconds',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
