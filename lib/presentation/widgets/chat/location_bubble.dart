import 'package:flutter/material.dart';

import '../../../data/models/message_model.dart';
import '../../../data/services/external_map_service.dart';
import '../../screens/chat/location_map_viewer_screen.dart';
import '../map/osm_map.dart';

/// Telegram-like location bubble: a static preview that opens an interactive
/// full-screen map when tapped. The separate action also lets a user launch a
/// maps application directly without first opening the viewer.
///
/// Live locations show remaining time and update via polling.
class LocationBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMine;

  const LocationBubble({super.key, required this.message, this.isMine = false});

  @override
  State<LocationBubble> createState() => _LocationBubbleState();
}

class _LocationBubbleState extends State<LocationBubble> {
  bool _openingExternalMap = false;

  MessageModel get _message => widget.message;
  double? get _lat => _message.latitude;
  double? get _lng => _message.longitude;

  GeoPoint get _point => GeoPoint(_lat ?? 0, _lng ?? 0);

  Future<void> _openViewer() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LocationMapViewerScreen(message: _message),
      ),
    );
  }

  Future<void> _openExternalMap() async {
    if (_openingExternalMap) return;
    setState(() => _openingExternalMap = true);

    final opened = await ExternalMapService.open(
      latitude: _lat ?? 0,
      longitude: _lng ?? 0,
    );

    if (!mounted) return;
    setState(() => _openingExternalMap = false);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هیچ برنامه‌ای برای باز کردن نقشه پیدا نشد')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = widget.isMine ? Colors.white : theme.colorScheme.onSurface;
    final live = _message.isLiveLocation;
    final active = _message.isLiveActive;
    final point = _point;

    return Semantics(
      button: true,
      label: 'نمایش موقعیت مکانی روی نقشه',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openViewer,
        child: Container(
          width: 240,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: (widget.isMine ? Colors.white : Colors.black)
                .withValues(alpha: 0.08),
            border: Border.all(color: fg.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: SizedBox(
                  height: 140,
                  width: 240,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        // The inline map is intentionally not interactive. It
                        // leaves the message list scrollable; the full-screen
                        // viewer owns all pan and zoom gestures.
                        child: OsmMap(
                          key: ValueKey(
                            'map-${_message.id}-${point.latitude}-${point.longitude}',
                          ),
                          initialCenter: point,
                          initialZoom: 15,
                          interactive: false,
                          showZoomButtons: false,
                          showAttribution: false,
                        ),
                      ),
                      Positioned.fill(
                        child: Center(
                          child: Transform.translate(
                            offset: const Offset(0, -10),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (live)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: active ? Colors.green : Colors.grey,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  active
                                      ? Icons.live_tv
                                      : Icons.timer_off_outlined,
                                  size: 12,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  active ? 'زنده' : 'پایان یافته',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 16, color: fg),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _message.locationTitle?.isNotEmpty == true
                                ? _message.locationTitle!
                                : (live ? 'لوکیشن زنده' : 'لوکیشن'),
                            style: TextStyle(
                              color: fg,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(_lat ?? 0).toStringAsFixed(5)}, ${(_lng ?? 0).toStringAsFixed(5)}',
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                      textDirection: TextDirection.ltr,
                    ),
                    if (live && active && _message.liveUntil != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'تا ${_two(_message.liveUntil!.hour)}:${_two(_message.liveUntil!.minute)} فعال است',
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _openingExternalMap ? null : _openExternalMap,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          alignment: Alignment.centerLeft,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: _openingExternalMap
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                Icons.open_in_new,
                                size: 13,
                                color: theme.colorScheme.primary,
                              ),
                        label: Text(
                          'باز کردن در نقشه',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}
