import 'package:url_launcher/url_launcher.dart';

/// Opens a coordinate in a map application, falling back to Google Maps in a
/// browser when the device does not have a handler for the `geo:` scheme.
///
/// This intentionally does not call [canLaunchUrl]. On Android 11 and newer
/// that method can return false because of package-visibility rules even when
/// the URL can be opened successfully. Calling [launchUrl] and checking its
/// result is both more reliable and keeps the app compatible with devices that
/// do not have Google Maps installed.
class ExternalMapService {
  const ExternalMapService._();

  static Uri googleMapsUri({required double latitude, required double longitude}) {
    return Uri.https(
      'www.google.com',
      '/maps/search/',
      <String, String>{
        'api': '1',
        'query': '$latitude,$longitude',
      },
    );
  }

  static Uri geoUri({required double latitude, required double longitude}) {
    final coordinate = '$latitude,$longitude';
    return Uri(
      scheme: 'geo',
      path: coordinate,
      queryParameters: <String, String>{'q': coordinate},
    );
  }

  static Future<bool> open({
    required double latitude,
    required double longitude,
  }) async {
    final urls = <Uri>[
      geoUri(latitude: latitude, longitude: longitude),
      googleMapsUri(latitude: latitude, longitude: longitude),
    ];

    for (final uri in urls) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {
        // Try the next URL. A missing maps application or an unavailable
        // platform plugin must not make the chat screen crash.
      }
    }
    return false;
  }
}
