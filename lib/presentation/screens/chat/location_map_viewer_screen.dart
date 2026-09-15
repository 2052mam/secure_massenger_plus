import 'package:flutter/material.dart';

import '../../../data/models/message_model.dart';
import '../../../data/services/external_map_service.dart';
import '../../widgets/map/osm_map.dart';

/// Full-screen viewer for a location message.
///
/// A location preview in a chat is deliberately non-interactive so it does
/// not steal gestures from the message list. Tapping that preview opens this
/// route, where the map can be panned, pinch-zoomed, double-tap zoomed, and
/// opened in an external maps application, matching Telegram's interaction.
class LocationMapViewerScreen extends StatefulWidget {
  final MessageModel message;

  const LocationMapViewerScreen({super.key, required this.message});

  @override
  State<LocationMapViewerScreen> createState() => _LocationMapViewerScreenState();
}

class _LocationMapViewerScreenState extends State<LocationMapViewerScreen> {
  bool _openingExternalMap = false;

  MessageModel get _message => widget.message;

  GeoPoint get _point => GeoPoint(
        _message.latitude ?? 0,
        _message.longitude ?? 0,
      );

  Future<void> _openExternalMap() async {
    if (_openingExternalMap) return;
    setState(() => _openingExternalMap = true);

    final opened = await ExternalMapService.open(
      latitude: _point.latitude,
      longitude: _point.longitude,
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
    final point = _point;
    final isLive = _message.isLiveLocation;
    final title = _message.locationTitle?.trim();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Keep the bottom sheet outside the map's hit-test area so all map
          // gestures, including pinch zoom, work reliably on small screens.
          Positioned.fill(
            bottom: 152,
            child: OsmMap(
              key: ValueKey('location-viewer-map-${_message.id}'),
              initialCenter: point,
              initialZoom: 16,
              markers: [point],
              showZoomButtons: true,
              showAttribution: true,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(
                  children: [
                    _CircleButton(
                      tooltip: 'بستن',
                      icon: Icons.close,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          child: Text(
                            isLive ? 'موقعیت زنده' : 'موقعیت مکانی',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 50),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 12,
                      offset: Offset(0, -3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isLive ? Icons.share_location : Icons.location_on,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title?.isNotEmpty == true
                                    ? title!
                                    : (isLive ? 'لوکیشن زنده' : 'لوکیشن'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _openingExternalMap ? null : _openExternalMap,
                      icon: _openingExternalMap
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.open_in_new),
                      label: const Text('باز کردن در برنامه نقشه'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _CircleButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        color: Colors.white,
        icon: Icon(icon),
      ),
    );
  }
}
