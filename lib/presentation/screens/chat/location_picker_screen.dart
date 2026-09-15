import 'package:flutter/material.dart';

import '../../../data/services/location_service.dart';
import '../../widgets/map/osm_map.dart';

/// Telegram-like location picker: a real draggable map with a centre pin.
/// Drag the map (or long-press) to place the pin, tap the crosshair to jump to
/// your GPS position, then send it as a static or live location.
///
/// Returns `{latitude, longitude, title, is_live, live_minutes}` via
/// `Navigator.pop`.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  // Tehran — a sane starting view before the GPS fix arrives.
  static const _fallbackCenter = GeoPoint(35.6892, 51.3890);

  final _controller = OsmMapController();
  final _titleCtrl = TextEditingController();

  GeoPoint _pin = _fallbackCenter;
  bool _locating = true;
  bool _hasFix = false;
  GeoPoint? _myLocation;
  String? _error;
  bool _pinMoving = false;

  @override
  void initState() {
    super.initState();
    // Ask on open, exactly like Telegram: the system dialog appears here.
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate(initial: true));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _locate({bool initial = false}) async {
    if (!initial && _locating) return;
    setState(() {
      _locating = true;
      _error = null;
    });
    final result = await LocationService.current();
    if (!mounted) return;
    if (result.isSuccess) {
      final point = GeoPoint(result.position!.latitude, result.position!.longitude);
      setState(() {
        _myLocation = point;
        _pin = point;
        _hasFix = true;
        _locating = false;
      });
      _controller.move(point, zoom: 16);
    } else {
      setState(() {
        _locating = false;
        _error = LocationService.messageFor(result.failure!, isFa: true);
      });
      if (result.failure == LocationFailure.deniedForever) {
        _promptSettings(appSettings: true);
      } else if (result.failure == LocationFailure.serviceDisabled) {
        _promptSettings(appSettings: false);
      }
    }
  }

  Future<void> _promptSettings({required bool appSettings}) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('دسترسی موقعیت مکانی'),
        content: Text(
          appSettings
              ? 'دسترسی موقعیت مکانی رد شده است. برای ارسال لوکیشن، آن را از تنظیمات برنامه فعال کنید.'
              : 'موقعیت‌یاب دستگاه خاموش است. برای ارسال لوکیشن آن را روشن کنید.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('بعداً'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('باز کردن تنظیمات'),
          ),
        ],
      ),
    );
    if (open != true) return;
    if (appSettings) {
      await LocationService.openAppSettings();
    } else {
      await LocationService.openLocationSettings();
    }
  }

  void _submit({required bool live, int minutes = 15}) {
    Navigator.pop(context, {
      'latitude': _pin.latitude,
      'longitude': _pin.longitude,
      'title': _titleCtrl.text.trim(),
      'is_live': live,
      'live_minutes': minutes,
    });
  }

  Future<void> _chooseLiveDuration() async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'تا چه مدت موقعیت شما به‌اشتراک گذاشته شود؟',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('۱۵ دقیقه'),
              onTap: () => Navigator.pop(ctx, 15),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('۱ ساعت'),
              onTap: () => Navigator.pop(ctx, 60),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('۸ ساعت'),
              onTap: () => Navigator.pop(ctx, 480),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (minutes != null && mounted) _submit(live: true, minutes: minutes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ارسال موقعیت مکانی'),
        actions: [
          IconButton(
            tooltip: 'عنوان مکان',
            icon: const Icon(Icons.edit_location_alt_outlined),
            onPressed: _editTitle,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: OsmMap(
                    controller: _controller,
                    initialCenter: _pin,
                    initialZoom: 15,
                    // Show where the user actually is once the pin has been
                    // dragged somewhere else.
                    markers: (_myLocation != null && _myLocation != _pin)
                        ? [_myLocation!]
                        : const [],
                    onCenterChanged: (p) {
                      if (!_pinMoving) setState(() => _pinMoving = true);
                      _pin = p;
                    },
                    onCenterSettled: (p) =>
                        setState(() { _pin = p; _pinMoving = false; }),
                    onLongPress: (p) => setState(() => _pin = p),
                  ),
                ),
                // Centre pin — the map moves under it, Telegram-style.
                IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      offset: Offset(0, _pinMoving ? -20 : -14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_on,
                              size: 44, color: Colors.red),
                          Container(
                            width: 8,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 88,
                  child: FloatingActionButton.small(
                    heroTag: 'locate-me',
                    onPressed: _locating ? null : _locate,
                    child: _locating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_hasFix
                            ? Icons.my_location
                            : Icons.location_searching),
                  ),
                ),
                if (_error != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: Material(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            const Icon(Icons.location_off,
                                color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                    color: Colors.red, fontSize: 12),
                              ),
                            ),
                            TextButton(
                              onPressed: _locate,
                              child: const Text('تلاش مجدد'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Material(
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.place_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _titleCtrl.text.trim().isEmpty
                                    ? 'مکان انتخاب‌شده'
                                    : _titleCtrl.text.trim(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _pin.toString(),
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.hintColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _submit(live: false),
                            icon: const Icon(Icons.send_rounded, size: 18),
                            label: const Text('ارسال این موقعیت'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _hasFix ? _chooseLiveDuration : null,
                            icon: const Icon(Icons.share_location, size: 18),
                            label: const Text('موقعیت زنده'),
                          ),
                        ),
                      ],
                    ),
                    if (!_hasFix)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'برای ارسال «موقعیت زنده» ابتدا موقعیت فعلی خود را دریافت کنید.',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
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

  Future<void> _editTitle() async {
    final ctrl = TextEditingController(text: _titleCtrl.text);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('عنوان مکان'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'مثلاً: کافه، منزل، محل قرار...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('تأیید'),
          ),
        ],
      ),
    );
    if (value != null && mounted) setState(() => _titleCtrl.text = value);
  }
}
