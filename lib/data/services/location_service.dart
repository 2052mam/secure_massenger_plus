import 'package:geolocator/geolocator.dart';

/// Outcome of a location request, so the UI can react precisely instead of
/// showing one generic error.
enum LocationFailure {
  /// The device's location toggle (GPS) is off.
  serviceDisabled,

  /// The user denied the runtime prompt this time.
  denied,

  /// The user selected "Don't ask again" / denied permanently — only the
  /// system settings page can restore it.
  deniedForever,

  /// Timed out or the platform returned an error.
  unavailable,
}

class LocationResult {
  final Position? position;
  final LocationFailure? failure;
  const LocationResult._({this.position, this.failure});

  factory LocationResult.success(Position position) =>
      LocationResult._(position: position);
  factory LocationResult.failed(LocationFailure failure) =>
      LocationResult._(failure: failure);

  bool get isSuccess => position != null;
}

/// Centralised location access.
///
/// The permission prompt only ever appears if ACCESS_FINE_LOCATION /
/// ACCESS_COARSE_LOCATION are declared in AndroidManifest.xml — they are.
/// This service additionally makes sure the request is actually *issued*
/// (the old code skipped it when the status was `deniedForever`, so the user
/// could never recover) and exposes the settings escape hatches.
class LocationService {
  const LocationService._();

  static Future<bool> isServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  /// Ask for permission, prompting the OS dialog when possible.
  static Future<LocationFailure?> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationFailure.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // This is the call that shows the system dialog.
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationFailure.deniedForever;
    }
    if (permission == LocationPermission.denied) {
      return LocationFailure.denied;
    }
    return null;
  }

  /// Best-effort current position. Returns the last known fix immediately if
  /// a fresh one cannot be acquired in time, so the map never hangs.
  static Future<LocationResult> current({
    Duration timeout = const Duration(seconds: 15),
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    final failure = await ensurePermission();
    if (failure != null) return LocationResult.failed(failure);
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          timeLimit: timeout,
        ),
      );
      return LocationResult.success(position);
    } catch (_) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return LocationResult.success(last);
      } catch (_) {}
      return LocationResult.failed(LocationFailure.unavailable);
    }
  }

  /// Position stream used by live-location sharing.
  static Stream<Position> watch({int distanceFilterMeters = 10}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
      ),
    );
  }

  static Future<void> openAppSettings() => Geolocator.openAppSettings();

  static Future<void> openLocationSettings() =>
      Geolocator.openLocationSettings();

  static String messageFor(LocationFailure failure, {required bool isFa}) {
    switch (failure) {
      case LocationFailure.serviceDisabled:
        return isFa
            ? 'موقعیت‌یاب (GPS) دستگاه خاموش است. آن را روشن کنید.'
            : 'Device location (GPS) is turned off. Please enable it.';
      case LocationFailure.denied:
        return isFa
            ? 'دسترسی به موقعیت مکانی داده نشد.'
            : 'Location permission was not granted.';
      case LocationFailure.deniedForever:
        return isFa
            ? 'دسترسی به موقعیت مکانی برای همیشه رد شده است. از تنظیمات برنامه آن را فعال کنید.'
            : 'Location permission is permanently denied. Enable it from app settings.';
      case LocationFailure.unavailable:
        return isFa
            ? 'دریافت موقعیت مکانی ممکن نشد. دوباره تلاش کنید.'
            : 'Could not get your location. Please try again.';
    }
  }
}
