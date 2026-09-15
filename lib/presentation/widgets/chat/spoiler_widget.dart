import 'dart:ui';
import 'package:flutter/material.dart';

class SpoilerWidget extends StatefulWidget {
  final Widget child;
  final bool isSpoiler;
  final String? label;
  final VoidCallback? onReveal;

  const SpoilerWidget({
    super.key,
    required this.child,
    required this.isSpoiler,
    this.label,
    this.onReveal,
  });

  @override
  State<SpoilerWidget> createState() => _SpoilerWidgetState();
}

class _SpoilerWidgetState extends State<SpoilerWidget> {
  bool _revealed = false;

  @override
  void didUpdateWidget(SpoilerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSpoiler != widget.isSpoiler && !widget.isSpoiler) {
      setState(() => _revealed = true);
    }
  }

  void _toggleReveal() {
    if (!_revealed) {
      setState(() => _revealed = true);
      widget.onReveal?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isSpoiler || _revealed) {
      return widget.child;
    }

    return GestureDetector(
      onTap: _toggleReveal,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Blurred background child
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: widget.child,
            ),
            // Overlay gradient & pattern
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            // Spoiler indicator tag & icon
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.remove_red_eye_outlined,
                    color: Colors.white,
                    size: 26,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.label ?? 'اسپویلر (لمس کنید)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Colors.black, blurRadius: 4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
