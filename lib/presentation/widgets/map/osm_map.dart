import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A geographic point. Named [GeoPoint] (not LatLng) to avoid clashing with
/// map packages that may be added later.
class GeoPoint {
  final double latitude;
  final double longitude;
  const GeoPoint(this.latitude, this.longitude);

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
}

/// Web-Mercator helpers (the "slippy map" projection used by OpenStreetMap).
class MapProjection {
  static const tileSize = 256.0;

  static double lonToPixelX(double lon, int zoom) =>
      (lon + 180.0) / 360.0 * tileSize * (1 << zoom);

  static double latToPixelY(double lat, int zoom) {
    final clamped = lat.clamp(-85.05112878, 85.05112878);
    final rad = clamped * math.pi / 180.0;
    final y =
        (1.0 - math.log(math.tan(rad) + 1.0 / math.cos(rad)) / math.pi) / 2.0;
    return y * tileSize * (1 << zoom);
  }

  static double pixelXToLon(double x, int zoom) =>
      x / (tileSize * (1 << zoom)) * 360.0 - 180.0;

  static double pixelYToLat(double y, int zoom) {
    final n = math.pi - 2.0 * math.pi * y / (tileSize * (1 << zoom));
    return 180.0 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }
}

/// Imperative handle so a parent can recenter the map (e.g. "my location").
class OsmMapController extends ChangeNotifier {
  GeoPoint? _pendingCenter;
  double? _pendingZoom;

  GeoPoint? takeCenter() {
    final value = _pendingCenter;
    _pendingCenter = null;
    return value;
  }

  double? takeZoom() {
    final value = _pendingZoom;
    _pendingZoom = null;
    return value;
  }

  void move(GeoPoint center, {double? zoom}) {
    _pendingCenter = center;
    _pendingZoom = zoom;
    notifyListeners();
  }
}

/// A lightweight OpenStreetMap tile view: drag to pan, pinch/buttons to zoom,
/// long-press to drop a pin. Deliberately dependency-free (raster tiles only)
/// so the app gains a real map without a new plugin.
class OsmMap extends StatefulWidget {
  final GeoPoint initialCenter;
  final double initialZoom;
  final bool interactive;

  /// Fired continuously while the map moves (the centre is the "pin" for a
  /// Telegram-style picker).
  final ValueChanged<GeoPoint>? onCenterChanged;

  /// Fired when the user finishes a gesture — cheap place to do network work.
  final ValueChanged<GeoPoint>? onCenterSettled;
  final ValueChanged<GeoPoint>? onLongPress;
  final OsmMapController? controller;

  /// Extra pins drawn on the map (the centre pin is drawn by the parent).
  final List<GeoPoint> markers;
  final bool showZoomButtons;
  final bool showAttribution;

  const OsmMap({
    super.key,
    required this.initialCenter,
    this.initialZoom = 15,
    this.interactive = true,
    this.onCenterChanged,
    this.onCenterSettled,
    this.onLongPress,
    this.controller,
    this.markers = const [],
    this.showZoomButtons = true,
    this.showAttribution = true,
  });

  @override
  State<OsmMap> createState() => _OsmMapState();
}

class _OsmMapState extends State<OsmMap> {
  static const _minZoom = 2.0;
  static const _maxZoom = 18.0;

  late GeoPoint _center;
  late double _zoom;

  double _gestureStartZoom = 15;
  Offset _lastFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    _center = widget.initialCenter;
    _zoom = widget.initialZoom.clamp(_minZoom, _maxZoom);
    widget.controller?.addListener(_applyControllerRequest);
  }

  @override
  void didUpdateWidget(covariant OsmMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_applyControllerRequest);
      widget.controller?.addListener(_applyControllerRequest);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_applyControllerRequest);
    super.dispose();
  }

  void _applyControllerRequest() {
    final center = widget.controller?.takeCenter();
    final zoom = widget.controller?.takeZoom();
    if (!mounted || (center == null && zoom == null)) return;
    setState(() {
      if (center != null) _center = center;
      if (zoom != null) _zoom = zoom.clamp(_minZoom, _maxZoom);
    });
    widget.onCenterChanged?.call(_center);
    widget.onCenterSettled?.call(_center);
  }

  int get _tileZoom => _zoom.round().clamp(_minZoom.toInt(), _maxZoom.toInt());

  /// Fractional part of the zoom, applied as a scale on the tile layer so
  /// pinching stays smooth between integer tile levels.
  double get _tileScale => math.pow(2, _zoom - _tileZoom).toDouble();

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartZoom = _zoom;
    _lastFocal = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size size) {
    // Pan: convert the screen delta into world pixels at the current zoom.
    final delta = details.localFocalPoint - _lastFocal;
    _lastFocal = details.localFocalPoint;

    final zoomLevel = _tileZoom;
    final scale = _tileScale;
    var px = MapProjection.lonToPixelX(_center.longitude, zoomLevel) -
        delta.dx / scale;
    var py = MapProjection.latToPixelY(_center.latitude, zoomLevel) -
        delta.dy / scale;

    final worldSize = MapProjection.tileSize * (1 << zoomLevel);
    px = px % worldSize;
    py = py.clamp(0.0, worldSize);

    var next = GeoPoint(
      MapProjection.pixelYToLat(py, zoomLevel),
      MapProjection.pixelXToLon(px, zoomLevel),
    );

    var nextZoom = _zoom;
    if (details.scale != 1.0 && details.pointerCount > 1) {
      nextZoom = (_gestureStartZoom + math.log(details.scale) / math.ln2)
          .clamp(_minZoom, _maxZoom);
    }

    if (next == _center && nextZoom == _zoom) return;
    setState(() {
      _center = next;
      _zoom = nextZoom;
    });
    widget.onCenterChanged?.call(_center);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    setState(() => _zoom = _zoom.clamp(_minZoom, _maxZoom));
    widget.onCenterSettled?.call(_center);
  }

  void _zoomBy(double amount) {
    setState(() => _zoom = (_zoom + amount).clamp(_minZoom, _maxZoom));
    widget.onCenterSettled?.call(_center);
  }

  GeoPoint _pointFor(Offset local, Size size) {
    final zoomLevel = _tileZoom;
    final scale = _tileScale;
    final centerPx = Offset(
      MapProjection.lonToPixelX(_center.longitude, zoomLevel),
      MapProjection.latToPixelY(_center.latitude, zoomLevel),
    );
    final dx = (local.dx - size.width / 2) / scale;
    final dy = (local.dy - size.height / 2) / scale;
    return GeoPoint(
      MapProjection.pixelYToLat(centerPx.dy + dy, zoomLevel),
      MapProjection.pixelXToLon(centerPx.dx + dx, zoomLevel),
    );
  }

  Offset _screenOffsetFor(GeoPoint point, Size size) {
    final zoomLevel = _tileZoom;
    final scale = _tileScale;
    final centerPx = Offset(
      MapProjection.lonToPixelX(_center.longitude, zoomLevel),
      MapProjection.latToPixelY(_center.latitude, zoomLevel),
    );
    final pointPx = Offset(
      MapProjection.lonToPixelX(point.longitude, zoomLevel),
      MapProjection.latToPixelY(point.latitude, zoomLevel),
    );
    return Offset(
      size.width / 2 + (pointPx.dx - centerPx.dx) * scale,
      size.height / 2 + (pointPx.dy - centerPx.dy) * scale,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(
            constraints.maxWidth.isFinite ? constraints.maxWidth : 320,
            constraints.maxHeight.isFinite ? constraints.maxHeight : 220,
          );
          final content = Stack(
            fit: StackFit.expand,
            children: [
              Container(color: const Color(0xFFE8E3DC)),
              _buildTileLayer(size),
              for (final marker in widget.markers)
                _buildMarker(marker, size),
              if (widget.showAttribution)
                Positioned(
                  right: 4,
                  bottom: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      child: Text(
                        '© OpenStreetMap',
                        style: TextStyle(fontSize: 8, color: Colors.black87),
                      ),
                    ),
                  ),
                ),
              if (widget.interactive && widget.showZoomButtons)
                Positioned(
                  right: 8,
                  bottom: 20,
                  child: Column(
                    children: [
                      _zoomButton(Icons.add, () => _zoomBy(1)),
                      const SizedBox(height: 6),
                      _zoomButton(Icons.remove, () => _zoomBy(-1)),
                    ],
                  ),
                ),
            ],
          );

          if (!widget.interactive) return content;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: (d) => _onScaleUpdate(d, size),
            onScaleEnd: _onScaleEnd,
            onDoubleTap: () => _zoomBy(1),
            onLongPressStart: widget.onLongPress == null
                ? null
                : (d) {
                    final point = _pointFor(d.localPosition, size);
                    setState(() => _center = point);
                    widget.onCenterChanged?.call(point);
                    widget.onLongPress!.call(point);
                  },
            child: content,
          );
        },
      ),
    );
  }

  Widget _zoomButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: Colors.black87),
        ),
      ),
    );
  }

  Widget _buildMarker(GeoPoint point, Size size) {
    final offset = _screenOffsetFor(point, size);
    return Positioned(
      left: offset.dx - 14,
      top: offset.dy - 28,
      child: const Icon(Icons.location_on, color: Colors.red, size: 28),
    );
  }

  Widget _buildTileLayer(Size size) {
    final zoomLevel = _tileZoom;
    final scale = _tileScale;
    final worldTiles = 1 << zoomLevel;

    // Work in the unscaled tile space, then scale the whole layer once.
    final layerWidth = size.width / scale;
    final layerHeight = size.height / scale;
    final centerPx = Offset(
      MapProjection.lonToPixelX(_center.longitude, zoomLevel),
      MapProjection.latToPixelY(_center.latitude, zoomLevel),
    );
    final left = centerPx.dx - layerWidth / 2;
    final top = centerPx.dy - layerHeight / 2;

    final firstX = (left / MapProjection.tileSize).floor();
    final lastX = ((left + layerWidth) / MapProjection.tileSize).floor();
    final firstY = (top / MapProjection.tileSize).floor();
    final lastY = ((top + layerHeight) / MapProjection.tileSize).floor();

    final tiles = <Widget>[];
    for (var ty = firstY; ty <= lastY; ty++) {
      if (ty < 0 || ty >= worldTiles) continue;
      for (var tx = firstX; tx <= lastX; tx++) {
        final wrappedX = ((tx % worldTiles) + worldTiles) % worldTiles;
        tiles.add(Positioned(
          left: tx * MapProjection.tileSize - left,
          top: ty * MapProjection.tileSize - top,
          width: MapProjection.tileSize,
          height: MapProjection.tileSize,
          child: _MapTile(x: wrappedX, y: ty, z: zoomLevel),
        ));
      }
    }

    // When the fractional zoom makes `scale` < 1 the unscaled layer is LARGER
    // than the viewport. A plain Center would clamp it to the incoming
    // constraints and leave uncovered edges, so the box is allowed to
    // overflow explicitly (the parent ClipRect trims it).
    return OverflowBox(
      minWidth: 0,
      minHeight: 0,
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      alignment: Alignment.center,
      child: SizedBox(
        width: layerWidth,
        height: layerHeight,
        child: Transform.scale(
          scale: scale,
          child: Stack(children: tiles),
        ),
      ),
    );
  }
}

class _MapTile extends StatelessWidget {
  final int x;
  final int y;
  final int z;
  const _MapTile({required this.x, required this.y, required this.z});

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: 'https://tile.openstreetmap.org/$z/$x/$y.png',
      // OpenStreetMap's tile policy requires an identifying User-Agent.
      httpHeaders: const {'User-Agent': 'SecureMessenger/1.0 (Flutter app)'},
      fit: BoxFit.fill,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (_, __) => const ColoredBox(color: Color(0xFFE8E3DC)),
      errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFFE8E3DC)),
    );
  }
}
