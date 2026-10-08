import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/nearby_repository.dart';
import 'package:pawday_consumer/nearby_screen.dart';
import 'package:pawday_consumer/repositories.dart';

class Device implements GeolocationAccess {
  bool on = true;
  LocationPermission permission = LocationPermission.denied,
      answer = LocationPermission.denied;
  int checks = 0, requests = 0, positions = 0;
  Object? failure;
  @override
  Future<bool> enabled() async => on;
  @override
  Future<LocationPermission> check() async {
    checks++;
    return permission;
  }

  @override
  Future<LocationPermission> request() async {
    requests++;
    return answer;
  }

  @override
  Future<Coordinates> current() async {
    positions++;
    if (failure != null) throw failure!;
    return const Coordinates(121.500000123, 31.200000123);
  }

  @override
  Future<bool> settings() async => true;
}

Map<String, dynamic> envelope(Object data) => {
  'data': data,
  'page': {'next_cursor': null, 'has_more': false},
  'meta': {
    'request_id': '00000000-0000-4000-8000-000000000001',
    'correlation_id': '00000000-0000-4000-8000-000000000001',
  },
};
ConsumerApi api(Future<http.Response> Function(http.Request) network) =>
    ConsumerApi(
      base: Uri.parse('http://localhost/api/v1'),
      transport: MockClient(network),
      vault: MemoryVault(),
    );
NavigationIntent intent({String host = 'uri.amap.com'}) {
  String url(String native) => Uri.https(host, '/marker', {
    'position': '121.500000,31.200000',
    'name': 'TEST & store',
    'coordinate': 'wgs84',
    'src': 'pawday',
    'callnative': native,
  }).toString();
  return NavigationIntent(
    provider: 'AMAP_URI',
    place_id: '00000000-0000-4000-8000-000000000001',
    destination_name: 'TEST & store',
    longitude: 121.5,
    latitude: 31.2,
    coordinate_system: 'WGS84',
    mode: 'DESTINATION',
    launch_url: url('1'),
    fallback_url: url('0'),
  );
}

void main() {
  test('location denial never requests a position', () async {
    final d = Device();
    await expectLater(
      LocationProvider(d).locate(),
      throwsA(
        isA<LocationFailure>().having(
          (e) => e.issue,
          'issue',
          LocationIssue.denied,
        ),
      ),
    );
    expect(d.positions, 0);
    expect(d.requests, 1);
  });
  test('permanent denial never opens permission dialog again', () async {
    final d = Device()..permission = LocationPermission.deniedForever;
    await expectLater(
      LocationProvider(d).locate(),
      throwsA(
        isA<LocationFailure>().having(
          (e) => e.issue,
          'issue',
          LocationIssue.deniedForever,
        ),
      ),
    );
    expect(d.requests, 0);
    expect(d.positions, 0);
  });
  test('disabled services do not ask permission', () async {
    final d = Device()..on = false;
    await expectLater(
      LocationProvider(d).locate(),
      throwsA(
        isA<LocationFailure>().having(
          (e) => e.issue,
          'issue',
          LocationIssue.disabled,
        ),
      ),
    );
    expect(d.checks, 0);
  });
  test(
    'grant uses one foreground position and normalizes GPS precision',
    () async {
      final d = Device()..answer = LocationPermission.whileInUse;
      final p = await LocationProvider(d).locate();
      expect(p.longitude, 121.5);
      expect(p.latitude, 31.2);
      expect(d.positions, 1);
    },
  );
  test('position timeout has explicit recoverable state', () async {
    final d = Device()
      ..permission = LocationPermission.whileInUse
      ..failure = TimeoutException('TEST');
    await expectLater(
      LocationProvider(d).locate(),
      throwsA(
        isA<LocationFailure>().having(
          (e) => e.issue,
          'issue',
          LocationIssue.timeout,
        ),
      ),
    );
  });
  test('device failure has explicit unavailable state', () async {
    final d = Device()
      ..permission = LocationPermission.whileInUse
      ..failure = StateError('TEST');
    await expectLater(
      LocationProvider(d).locate(),
      throwsA(
        isA<LocationFailure>().having(
          (e) => e.issue,
          'issue',
          LocationIssue.unavailable,
        ),
      ),
    );
  });
  test('navigation hands off only destination without user origin', () async {
    final calls = <Uri>[];
    expect(
      await NavigationLauncher((u) async {
        calls.add(u);
        return true;
      }).open(intent()),
      true,
    );
    expect(calls.single.queryParameters['position'], '121.500000,31.200000');
    expect(calls.single.queryParameters.containsKey('from'), false);
  });
  test('native handoff exception uses browser fallback', () async {
    final calls = <Uri>[];
    final opened = await NavigationLauncher((u) async {
      calls.add(u);
      if (calls.length == 1) throw StateError('TEST');
      return true;
    }).open(intent());
    expect(opened, true);
    expect(calls.last.queryParameters['callnative'], '0');
  });
  test('both launch failures remain visible to caller', () async {
    expect(await NavigationLauncher((_) async => false).open(intent()), false);
  });
  test('host substitution is rejected without launching', () async {
    int calls = 0;
    expect(
      await NavigationLauncher((_) async {
        calls++;
        return true;
      }).open(intent(host: 'evil.test')),
      false,
    );
    expect(calls, 0);
  });
  test(
    'guest nearby queries are anonymous and do not persist location',
    () async {
      final calls = <http.Request>[];
      final c = api((r) async {
        calls.add(r);
        return http.Response(jsonEncode(envelope([])), 200);
      });
      await NearbyRepository(c).places(city: '上海');
      await NearbyRepository(c)
          .places(position: const Coordinates(121.5, 31.2));
      expect(calls.every((r) => !r.headers.containsKey('Authorization')), true);
      expect(calls.last.url.queryParameters['coordinate_system'], 'WGS84');
      expect(calls.first.url.queryParameters.containsKey('longitude'), false);
      expect(await c.vault.read('consumer.session'), null);
      c.dispose();
    },
  );
  testWidgets('nearby opens without permission prompt or API call', (
    tester,
  ) async {
    final d = Device();
    int calls = 0;
    final c = api((_) async {
      calls++;
      return http.Response(jsonEncode(envelope([])), 200);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          consumerApiProvider.overrideWithValue(c),
          locationProvider.overrideWithValue(LocationProvider(d)),
        ],
        child: const MaterialApp(home: NearbyScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(d.checks, 0);
    expect(calls, 0);
    expect(find.text('使用本次位置'), findsOneWidget);
    c.dispose();
  });
  testWidgets('denied location retains city browsing', (tester) async {
    final d = Device();
    final c = api((_) async => http.Response(jsonEncode(envelope([])), 200));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          consumerApiProvider.overrideWithValue(c),
          locationProvider.overrideWithValue(LocationProvider(d)),
        ],
        child: const MaterialApp(home: NearbyScreen()),
      ),
    );
    await tester.tap(find.text('使用本次位置'));
    await tester.pumpAndSettle();
    expect(find.textContaining('未授权位置'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '上海');
    await tester.tap(find.text('按城市浏览'));
    await tester.pumpAndSettle();
    expect(find.textContaining('该范围暂无'), findsOneWidget);
    expect(d.positions, 0);
    c.dispose();
  });
  testWidgets('late city response cannot replace changed city', (tester) async {
    final done = Completer<http.Response>();
    final c = api((_) => done.future);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [consumerApiProvider.overrideWithValue(c)],
        child: const MaterialApp(home: NearbyScreen()),
      ),
    );
    await tester.enterText(find.byType(TextField), '上海');
    await tester.tap(find.text('按城市浏览'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '北京');
    done.complete(http.Response(jsonEncode(envelope([])), 200));
    await tester.pumpAndSettle();
    expect(find.textContaining('该范围暂无'), findsNothing);
    expect(find.text('北京'), findsWidgets);
    c.dispose();
  });
}
