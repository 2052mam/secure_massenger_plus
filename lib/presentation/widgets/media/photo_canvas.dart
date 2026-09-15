import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'media_labels.dart';

/// The viewport is the whole route, NOT an inset Dialog or the chat bubble.
/// Pinch/pan and focal-point double-tap all use this same coordinate system.
class PhotoCanvas extends StatefulWidget {
  final ImageProvider? image;
  final ui.Image? decodedImage;
  final VoidCallback? onTap;
  final TransformationController? transformationController;

  const PhotoCanvas({
    super.key,
    this.image,
    this.decodedImage,
    this.onTap,
    this.transformationController,
  }) : assert((image == null) != (decodedImage == null));

  @override
  State<PhotoCanvas> createState() => _PhotoCanvasState();
}

class _PhotoCanvasState extends State<PhotoCanvas>
    with SingleTickerProviderStateMixin {
  late final TransformationController _transform;
  late final AnimationController _zoom;
  Animation<Matrix4>? _animation;
  Offset _doubleTapPosition = Offset.zero;
  int _retry = 0;

  @override
  void initState() {
    super.initState();
    _transform = widget.transformationController ?? TransformationController();
    _zoom =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          if (_animation != null) _transform.value = _animation!.value;
        });
  }

  void _doubleTap() {
    final Matrix4 target;
    if (_transform.value.getMaxScaleOnAxis() > 1.05) {
      target = Matrix4.identity();
    } else {
      const scale = 3.0;
      target = Matrix4.identity()
        ..setEntry(0, 0, scale)
        ..setEntry(1, 1, scale)
        ..setEntry(0, 3, -_doubleTapPosition.dx * (scale - 1))
        ..setEntry(1, 3, -_doubleTapPosition.dy * (scale - 1));
    }
    _animation = Matrix4Tween(
      begin: _transform.value.clone(),
      end: target,
    ).animate(CurvedAnimation(parent: _zoom, curve: Curves.easeOutCubic));
    _zoom.forward(from: 0);
  }

  Future<void> _retryImage() async {
    await widget.image?.evict();
    if (mounted) setState(() => _retry++);
  }

  @override
  void dispose() {
    _zoom.dispose();
    if (widget.transformationController == null) _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = MediaLabels.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: (details) => _doubleTapPosition = details.localPosition,
      onDoubleTap: _doubleTap,
      child: InteractiveViewer(
        key: const ValueKey('photo-viewport'),
        transformationController: _transform,
        minScale: 1,
        maxScale: 6,
        onInteractionStart: (_) => _zoom.stop(),
        child: SizedBox.expand(
          child: widget.decodedImage != null
              ? RawImage(
                  image: widget.decodedImage,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                )
              : Image(
                  key: ValueKey(_retry),
                  image: widget.image!,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            value: progress.expectedTotalBytes == null
                                ? null
                                : progress.cumulativeBytesLoaded /
                                      progress.expectedTotalBytes!,
                          ),
                        ),
                  errorBuilder: (_, __, ___) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white70,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          labels.loadError,
                          style: const TextStyle(color: Colors.white),
                        ),
                        TextButton(
                          onPressed: _retryImage,
                          child: Text(labels.retry),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
