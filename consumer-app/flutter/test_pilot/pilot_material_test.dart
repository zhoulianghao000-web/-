import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/repositories.dart';
import 'package:pawday_consumer/nearby_screen.dart';

void main() {
  const sku = '00000000-0000-4000-8000-000000000001';
  Tokens tokens(String access) => Tokens(
    access_token: access,
    refresh_token: 'r',
    expires_in: 900,
    session_id: sku,
    user_id: null,
  );
  ConsumerApi client(Future<http.Response> Function(http.Request) handler) =>
      ConsumerApi(
        base: Uri.parse('http://localhost/api/v1'),
        vault: MemoryVault(),
        transport: MockClient(handler),
      );
  test('product image carries bearer and environment contract', () async {
    final api = client((r) async {
      expect(r.url.path, '/api/v1/consumer/pilot/skus/$sku/media');
      expect(r.headers['Authorization'], 'Bearer image-access');
      expect(r.headers['X-Pawday-Pilot'], 'simulated-v1');
      return http.Response.bytes(
        [137, 80, 78, 71],
        200,
        headers: {
          'content-type': 'image/png',
          'x-pawday-environment': 'SIMULATED_PILOT',
        },
      );
    });
    await api.accept(tokens('image-access'));
    expect(await api.pilotProductMedia(sku), [137, 80, 78, 71]);
    api.dispose();
  });
  test('guest is rejected before transport', () async {
    int calls = 0;
    final api = client((r) async {
      calls++;
      return http.Response('', 500);
    });
    await expectLater(
      api.pilotProductMedia(sku),
      throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'AUTH_REQUIRED')),
    );
    expect(calls, 0);
    api.dispose();
  });
  test('late image bytes are discarded on logout', () async {
    final pending = Completer<http.Response>();
    final api = client((r) => pending.future);
    await api.accept(tokens('old'));
    final assertion = expectLater(
      api.pilotProductMedia(sku),
      throwsA(
        isA<ApiFailure>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await api.clear();
    pending.complete(
      http.Response.bytes(
        [1, 2],
        200,
        headers: {
          'content-type': 'image/png',
          'x-pawday-environment': 'SIMULATED_PILOT',
        },
      ),
    );
    await assertion;
    api.dispose();
  });
  test('successful PNG from ordinary backend is refused', () async {
    final api = client(
      (r) async =>
          http.Response.bytes([1], 200, headers: {'content-type': 'image/png'}),
    );
    await api.accept(tokens('a'));
    await expectLater(
      api.pilotProductMedia(sku),
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
  testWidgets('preset navigation failure does not call API', (tester) async {
    int calls = 0;
    final api = client((r) async {
      calls++;
      return http.Response(
        '{}',
        503,
        headers: {'x-pawday-environment': 'SIMULATED_PILOT'},
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [consumerApiProvider.overrideWithValue(api)],
        child: const MaterialApp(home: NearbyScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final before = calls;
    await tester.ensureVisible(find.text('测试场景工具'));
    await tester.tap(find.text('测试场景工具'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('模拟导航失败'));
    await tester.tap(find.text('模拟导航失败'));
    await tester.pumpAndSettle();
    expect(find.textContaining('预设导航失败'), findsOneWidget);
    expect(calls, before);
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });
}
