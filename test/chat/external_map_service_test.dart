import 'package:flutter_test/flutter_test.dart';
import 'package:secure_messenger/data/services/external_map_service.dart';

void main() {
  test('builds a Google Maps URL with encoded coordinates', () {
    final uri = ExternalMapService.googleMapsUri(
      latitude: 35.6892,
      longitude: 51.389,
    );

    expect(uri.scheme, 'https');
    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/search/');
    expect(uri.queryParameters['api'], '1');
    expect(uri.queryParameters['query'], '35.6892,51.389');
  });

  test('builds a geo URL for native map-app selection', () {
    final uri = ExternalMapService.geoUri(
      latitude: -33.8688,
      longitude: 151.2093,
    );

    expect(uri.scheme, 'geo');
    expect(uri.path, '-33.8688,151.2093');
    expect(uri.queryParameters['q'], '-33.8688,151.2093');
  });
}
