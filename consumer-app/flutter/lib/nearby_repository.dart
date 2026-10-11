import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'repositories.dart';
import 'pilot.dart';

class NearbyRepository {
  final ConsumerApi api;
  NearbyRepository(this.api);
  Future<NearbyResultListEnvelope> places({
    String? city,
    String? category,
    Coordinates? position,
    int offset = 0,
  }) async => NearbyResultListEnvelope.fromJson(
    await api.request(
      'GET',
      Uri(
        path: '/public/nearby/places',
        queryParameters: {
          'city': ?city,
          'category': ?category,
          'offset': '$offset',
          'limit': '20',
          if (position != null) ...{
            'longitude': position.longitude.toStringAsFixed(6),
            'latitude': position.latitude.toStringAsFixed(6),
            'coordinate_system': 'WGS84',
            'radius_m': '10000',
          },
        },
      ).toString(),
      anonymous: true,
    ),
  );
  Future<NearbyPlace> place(String id) async => NearbyPlaceEnvelope.fromJson(
    await api.request('GET', '/public/nearby/places/$id', anonymous: true),
  ).data;
  Future<NavigationIntent> navigation(String id) async =>
      NavigationIntentEnvelope.fromJson(
        await api.request(
          'POST',
          '/public/nearby/navigation-intents',
          anonymous: true,
          body: NavigationInput(place_id: id, mode: 'DESTINATION').toJson(),
        ),
      ).data;
}

final nearbyRepositoryProvider = Provider(
  (ref) => NearbyRepository(ref.watch(consumerApiProvider)),
);

class Coordinates {
  final double longitude, latitude;
  const Coordinates(this.longitude, this.latitude);
}

enum LocationIssue { denied, deniedForever, disabled, timeout, unavailable }

class LocationFailure implements Exception {
  final LocationIssue issue;
  const LocationFailure(this.issue);
}

abstract interface class GeolocationAccess {
  Future<bool> enabled();
  Future<LocationPermission> check();
  Future<LocationPermission> request();
  Future<Coordinates> current();
  Future<bool> settings();
}

class DeviceGeolocation implements GeolocationAccess {
  @override
  Future<bool> enabled() => Geolocator.isLocationServiceEnabled();
  @override
  Future<LocationPermission> check() => Geolocator.checkPermission();
  @override
  Future<LocationPermission> request() => Geolocator.requestPermission();
  @override
  Future<bool> settings() => Geolocator.openAppSettings();
  @override
  Future<Coordinates> current() async {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 12),
      ),
    );
    return Coordinates(p.longitude, p.latitude);
  }
}

class LocationProvider {
  final GeolocationAccess device;
  LocationProvider(this.device);
  Future<Coordinates> locate() async {
    try {
      if (!await device.enabled()) {
        throw const LocationFailure(LocationIssue.disabled);
      }
      var permission = await device.check();
      if (permission == LocationPermission.denied) {
        permission = await device.request();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const LocationFailure(LocationIssue.deniedForever);
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw const LocationFailure(LocationIssue.denied);
      }
      final p = await device.current().timeout(const Duration(seconds: 15));
      if (!p.longitude.isFinite ||
          !p.latitude.isFinite ||
          p.longitude.abs() > 180 ||
          p.latitude.abs() > 90) {
        throw const LocationFailure(LocationIssue.unavailable);
      }
      return Coordinates(
        double.parse(p.longitude.toStringAsFixed(6)),
        double.parse(p.latitude.toStringAsFixed(6)),
      );
    } on LocationFailure {
      rethrow;
    } on TimeoutException {
      throw const LocationFailure(LocationIssue.timeout);
    } catch (_) {
      throw const LocationFailure(LocationIssue.unavailable);
    }
  }

  Future<bool> settings() async {
    try {
      return await device.settings();
    } catch (_) {
      return false;
    }
  }
}

final locationProvider = Provider(
  (ref) =>
      LocationProvider(pilotMode ? PilotGeolocation() : DeviceGeolocation()),
);

typedef UriLauncher = Future<bool> Function(Uri uri);

class NavigationLauncher {
  final UriLauncher launch;
  NavigationLauncher(this.launch);
  static bool safe(Uri uri, String callNative) =>
      uri.scheme == 'https' &&
      uri.host == 'uri.amap.com' &&
      uri.userInfo.isEmpty &&
      !uri.hasPort &&
      uri.path == '/marker' &&
      uri.fragment.isEmpty &&
      uri.queryParameters['coordinate'] == 'wgs84' &&
      uri.queryParameters['src'] == 'pawday' &&
      uri.queryParameters['callnative'] == callNative &&
      uri.queryParametersAll.values.every((v) => v.length == 1) &&
      uri.queryParameters.keys.toSet().difference({
        'position',
        'name',
        'coordinate',
        'src',
        'callnative',
      }).isEmpty;
  Future<bool> open(NavigationIntent intent) async {
    if (pilotMode) return false;
    final first = Uri.tryParse(intent.launch_url),
        fallback = Uri.tryParse(intent.fallback_url);
    if (intent.provider != 'AMAP_URI' ||
        intent.coordinate_system != 'WGS84' ||
        intent.mode != 'DESTINATION' ||
        first == null ||
        fallback == null ||
        !safe(first, '1') ||
        !safe(fallback, '0') ||
        first.queryParameters['position'] !=
                '${intent.longitude.toStringAsFixed(6)},${intent.latitude.toStringAsFixed(6)}' &&
            first.queryParameters['position'] !=
                '${intent.longitude},${intent.latitude}' ||
        first.queryParameters['name'] != intent.destination_name ||
        first.queryParameters['position'] !=
            fallback.queryParameters['position'] ||
        first.queryParameters['name'] != fallback.queryParameters['name']) {
      return false;
    }
    try {
      if (await launch(first)) return true;
    } catch (_) {
      /* Browser fallback below. */
    }
    try {
      return await launch(fallback);
    } catch (_) {
      return false;
    }
  }
}

final navigationLauncherProvider = Provider(
  (ref) => NavigationLauncher(
    (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
  ),
);

/// Local scenarios; no platform channels, permissions, settings or geolocation.
class PilotGeolocation implements GeolocationAccess {
  String scenario;
  PilotGeolocation([this.scenario = 'ALLOWED']);
  @override
  Future<bool> enabled() async => scenario != 'DISABLED';
  @override
  Future<LocationPermission> check() async => scenario == 'DENIED'
      ? LocationPermission.denied
      : LocationPermission.whileInUse;
  @override
  Future<LocationPermission> request() => check();
  @override
  Future<Coordinates> current() async =>
      const Coordinates(106.551556, 29.563009);
  @override
  Future<bool> settings() async => false;
}
