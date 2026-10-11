import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pawday_consumer/main.dart';
import 'package:pawday_consumer/repositories.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/nearby_repository.dart';
import 'package:pawday_consumer/pilot.dart';

void main() {
  testWidgets('pilot guest sees persistent label and login before catalog', (
    tester,
  ) async {
    final api = ConsumerApi(
      base: Uri.parse('http://localhost/api/v1'),
      vault: MemoryVault(),
      transport: MockClient((r) async => http.Response('{}', 500)),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [consumerApiProvider.overrideWithValue(api)],
        child: const PawdayApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(pilotLabel), findsOneWidget);
    expect(find.text('手机号登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });
  test(
    'private pilot public read refreshes and auth requests omit stale bearer',
    () async {
      int reads = 0, refreshes = 0;
      Map<String, dynamic> envelope(Object data) => {
        'data': data,
        'meta': {'request_id': 'r', 'correlation_id': 'r'},
      };
      Map<String, dynamic> tokens(String suffix) => {
        'access_token': 'access$suffix',
        'refresh_token': 'refresh$suffix',
        'expires_in': 900,
        'session_id': '00000000-0000-4000-8000-000000000001',
        'user_id': null,
      };
      final api = ConsumerApi(
        base: Uri.parse('http://localhost/api/v1'),
        vault: MemoryVault(),
        transport: MockClient((r) async {
          Object data = {};
          int status = 200;
          if (r.url.path.endsWith('/verify')) {
            expect(r.headers['Authorization'], isNull);
            data = tokens('1');
          } else if (r.url.path.endsWith('/refresh')) {
            expect(r.headers['Authorization'], isNull);
            refreshes++;
            data = tokens('2');
          } else if (r.url.path.endsWith('/me')) {
            data = {
              'id': '00000000-0000-4000-8000-000000000001',
              'realm': 'CONSUMER',
              'user_id': null,
              'merchant_id': null,
              'session_id': '00000000-0000-4000-8000-000000000001',
              'permissions': [],
            };
          } else {
            reads++;
            if (reads == 1) {
              expect(r.headers['Authorization'], 'Bearer access1');
              status = 401;
            } else {
              expect(r.headers['Authorization'], 'Bearer access2');
            }
          }
          return http.Response(
            jsonEncode(
              status == 200
                  ? envelope(data)
                  : {
                      'error': {
                        'code': 'TOKEN_EXPIRED',
                        'message': 'TOKEN_EXPIRED',
                        'retryable': false,
                        'details': {},
                      },
                      'meta': {'request_id': 'r', 'correlation_id': 'r'},
                    },
            ),
            status,
            headers: {'x-pawday-environment': 'SIMULATED_PILOT'},
          );
        }),
      );
      await api.login('+999000000001', '123456');
      await api.request('GET', '/public/pet-taxonomy', anonymous: true);
      expect(reads, 2);
      expect(refreshes, 1);
      api.dispose();
    },
  );
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
