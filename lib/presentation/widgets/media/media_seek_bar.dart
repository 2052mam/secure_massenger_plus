import 'package:flutter/material.dart';

import '../../../core/utils/media_utils.dart';
import 'media_labels.dart';

/// The drag preview is owned by the caller, so stream updates never pull the
/// thumb away from the user's finger. Transport direction stays LTR in Persian.
class MediaSeekBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final Color color;
  final ValueChanged<Duration>? onChangeStart;
  final ValueChanged<Duration>? onChanged;
  final ValueChanged<Duration>? onChangeEnd;

  const MediaSeekBar({
    super.key,
    required this.position,
    required this.duration,
    this.buffered = Duration.zero,
    required this.color,
    this.onChangeStart,
    this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds.toDouble();
    final enabled = total > 0 && onChanged != null;
    Duration value(double milliseconds) =>
        Duration(milliseconds: milliseconds.round());
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          activeTrackColor: color,
          inactiveTrackColor: color.withValues(alpha: 0.18),
          secondaryActiveTrackColor: color.withValues(alpha: 0.3),
          thumbColor: color,
          overlayColor: color.withValues(alpha: 0.12),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        ),
        child: Slider(
          min: 0,
          max: total > 0 ? total : 1,
          value: clampMediaPosition(
            position,
            duration,
          ).inMilliseconds.toDouble(),
          secondaryTrackValue: clampMediaPosition(
            buffered,
            duration,
          ).inMilliseconds.toDouble(),
          semanticFormatterCallback: (v) =>
              '${MediaLabels.of(context).seek}: ${formatMediaDuration(value(v))}',
          onChangeStart: enabled && onChangeStart != null
              ? (v) => onChangeStart!(value(v))
              : null,
          onChanged: enabled ? (v) => onChanged!(value(v)) : null,
          onChangeEnd: enabled && onChangeEnd != null
              ? (v) => onChangeEnd!(value(v))
              : null,
        ),
      ),
    );
  }
}
