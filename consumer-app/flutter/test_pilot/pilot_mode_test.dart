import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/nearby_repository.dart';
import 'package:pawday_consumer/pilot.dart';

void main() {
  test('pilot build cannot launch an external destination', () async {
    expect(pilotMode, true);
    int calls = 0;
    final launcher = NavigationLauncher((uri) async {
      calls++;
      return true;
    });
    final intent = NavigationIntent(
      provider: 'AMAP_URI',
      place_id: 'TEST',
      destination_name: 'TEST',
      longitude: 106.551556,
      latitude: 29.563009,
      coordinate_system: 'WGS84',
      mode: 'DESTINATION',
      launch_url: 'https://uri.amap.com/marker',
      fallback_url: 'https://uri.amap.com/marker',
    );
    expect(await launcher.open(intent), false);
    expect(calls, 0);
  });
  test('pilot request explicitly marks its backend contract', () async {
    final api = ConsumerApi(
      base: Uri.parse('http://localhost/api/v1'),
      vault: MemoryVault(),
      transport: MockClient((r) async {
        expect(r.headers['X-Pawday-Pilot'], 'simulated-v1');
        return http.Response(
          jsonEncode({'data': {}, 'meta': {}}),
          200,
          headers: {'x-pawday-environment': 'SIMULATED_PILOT'},
        );
      }),
    );
    await api.request('GET', '/public/pet-taxonomy', anonymous: true);
    api.dispose();
  });
  test('pilot build rejects a response from an ordinary server', () async {
    final api = ConsumerApi(
      base: Uri.parse('http://localhost/api/v1'),
      vault: MemoryVault(),
      transport: MockClient((r) async => http.Response('{}', 200)),
    );
    await expectLater(
      api.request('GET', '/public/pet-taxonomy', anonymous: true),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.code,
          'code',
          'PILOT_ENVIRONMENT_MISMATCH',
        ),
      ),
    );
    api.dispose();
  });
}
