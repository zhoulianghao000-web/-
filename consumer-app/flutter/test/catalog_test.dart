import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/catalog_repository.dart';
import 'package:pawday_consumer/catalog_screen.dart';
import 'package:pawday_consumer/repositories.dart';

void main() {
  ConsumerApi api(Future<http.Response> Function(http.Request) handler) =>
      ConsumerApi(
        base: Uri.parse('http://localhost/api/v1'),
        transport: MockClient(handler),
        vault: MemoryVault(),
      );
  http.Response empty() => http.Response(
    jsonEncode({
      'data': [],
      'page': {'next_cursor': null, 'has_more': false},
      'meta': {'request_id': 'test', 'correlation_id': 'test'},
    }),
    200,
  );
  test(
    'guest browse encodes filters without sending pet credentials',
    () async {
      final client = api((r) async {
        expect(r.url.path, '/api/v1/public/products');
        expect(r.url.queryParameters['q'], '品牌 & 标准');
        expect(r.url.queryParameters['pet_category'], 'CAT');
        expect(r.headers.containsKey('authorization'), false);
        return empty();
      });
      expect(
        (await CatalogRepository(
          client,
        ).browse(category: 'CAT', query: '品牌 & 标准')).data,
        isEmpty,
      );
      client.dispose();
    },
  );
  test('search unavailable propagates explicit error rather than invented products', () async {
    final client = api(
      (r) async => http.Response(
        jsonEncode({
          'error': {
            'code': 'SEARCH_UNAVAILABLE',
            'message': 'SEARCH_UNAVAILABLE',
            'retryable': true,
            'details': {},
          },
          'meta': {'request_id': 'test', 'correlation_id': 'test'},
        }),
        503,
      ),
    );
    await expectLater(
      CatalogRepository(client).browse(),
      throwsA(
        isA<ApiFailure>().having((e) => e.code, 'code', 'SEARCH_UNAVAILABLE'),
      ),
    );
    client.dispose();
  });
  test('comparison sends explicit SKU and pet references only', () async {
    final client = api((r) async {
      expect(r.method, 'POST');
      expect(r.url.path, '/api/v1/consumer/products/compare');
      expect(jsonDecode(r.body), {
        'sku_ids': ['a', 'b'],
        'pet_id': 'owned-pet',
      });
      return http.Response(
        jsonEncode({
          'data': {'items': []},
          'meta': {'request_id': 'test', 'correlation_id': 'test'},
        }),
        200,
      );
    });
    expect(
      (await CatalogRepository(client).compare(['a', 'b'], 'owned-pet')).items,
      isEmpty,
    );
    client.dispose();
  });
  testWidgets('guest catalog renders honest empty state and refresh', (
    tester,
  ) async {
    final client = api((r) async => empty());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [consumerApiProvider.overrideWithValue(client)],
        child: const MaterialApp(home: CatalogScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('本页暂无'), findsOneWidget);
    expect(find.text('查询 / 刷新'), findsOneWidget);
    expect(find.text('比较已选商品（0/4）'), findsOneWidget);
    await tester.tap(find.text('查询 / 刷新'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    client.dispose();
  });
  test('uncertainties use readable explanations', () {
    expect(uncertaintyLabel('PET_ALLERGIES_UNKNOWN'), contains('尚未完成评估'));
    expect(uncertaintyLabel('future'), contains('核对'));
  });
}
