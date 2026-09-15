import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../data/services/api_service.dart';
import '../../../data/services/screen_privacy_service.dart';
import '../../widgets/media/media_labels.dart';
import '../../widgets/media/photo_canvas.dart';

/// Download -> validate/decode -> atomically claim -> reveal.
/// No disk cache, no thumbnail, no forwarding, and no claim on a failed load.
/// If [ttlSeconds] is set (timed photo e.g. 10s), shows a countdown and
/// auto-closes after the ttl expires.
class ViewOncePhotoScreen extends StatefulWidget {
  final Future<Uint8List> Function() loadPhoto;
  final Future<DateTime> Function() consumePhoto;
  final ValueChanged<DateTime> onViewed;
  final int? ttlSeconds;

  const ViewOncePhotoScreen({
    super.key,
    required this.loadPhoto,
    required this.consumePhoto,
    required this.onViewed,
    this.ttlSeconds,
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
  Timer? _ttlTimer;
  int _remaining = 0;
  DateTime? _viewedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      final viewedAt = await widget.consumePhoto();
      widget.onViewed(viewedAt);
      if (!mounted || _obscured || generation != _generation) return;
      setState(() {
        // Use the already decoded frame: revealing cannot trigger a second
        // decode/network request after the successful single-use claim.
        _photo = preparedImage;
        preparedImage = null;
        _loading = false;
        _viewedAt = viewedAt;
        if (widget.ttlSeconds != null && widget.ttlSeconds! > 0) {
          _remaining = widget.ttlSeconds!;
        }
      });
      if (widget.ttlSeconds != null && widget.ttlSeconds! > 0) {
        _startTtlCountdown();
      }
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

  void _startTtlCountdown() {
    _ttlTimer?.cancel();
    _ttlTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _obscured) {
        t.cancel();
        return;
      }
      if (_remaining <= 1) {
        t.cancel();
        _obscure();
        if (mounted) Navigator.of(context).pop();
        return;
      }
      setState(() => _remaining--);
    });
  }

  void _obscure() {
    ++_generation;
    _ttlTimer?.cancel();
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
    _ttlTimer?.cancel();
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
                      const Icon(
                        Icons.timer_outlined,
                        color: Colors.white70,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          labels.viewOnce,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.ttlSeconds != null && widget.ttlSeconds! > 0 && _photo != null && !_obscured)
              Positioned(
                top: 80,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer, color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Text('$_remaining ثانیه', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                    widget.ttlSeconds != null && widget.ttlSeconds! > 0
                        ? 'این عکس پس از $_remaining ثانیه به‌طور خودکار بسته می‌شود'
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
