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

import 'navigation_test.dart' show GuestRepository;

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

  testWidgets('comparison clears captured fit when consumer logs out', (
    tester,
  ) async {
    const first = '20000000-0000-4000-8000-000000000001',
        second = '20000000-0000-4000-8000-000000000002';
    Map<String, dynamic> standard(String id) => {
      'id': id,
      'spu_id': id,
      'sku_code': 'TEST-$id',
      'weight_g': 500,
      'package_unit': 'BAG',
      'name': id == first ? '测试商品 A' : '测试商品 B',
      'pet_category': 'CAT',
      'category': 'DRY',
      'brand': 'TEST brand',
      'catalog_standard_version_id': id,
      'ingredients': ['TEST ingredient'],
      'nutrients': [],
      'allergens_known': false,
      'life_stage_ids': [],
      'source_refs': ['TEST source'],
      'source_updated_on': '2026-10-01',
      'published_at': '2026-10-01T00:00:00Z',
      'allergens': [],
    };
    Map<String, dynamic> offer(String id) => {
      'offer_id': id,
      'merchant_id': id,
      'merchant_name': 'TEST merchant',
      'store_id': null,
      'sale_price_fen': 1000,
      'member_price_fen': null,
      'fulfillment_sla': 'TEST delivery',
      'offer_version': 0,
      'available_qty': 1,
      'inventory_version': 0,
      'in_stock': true,
    };
    final client = api((r) async {
      Object data;
      if (r.method == 'POST') {
        data = {
          'items': [
            for (final id in [first, second])
              {
                'standard': standard(id),
                'offers': [offer(id)],
                'fit': {
                  'sku_id': id,
                  'pet_id': 'owned-pet',
                  'pet_version': 0,
                  'result': 'NOT_RECOMMENDED',
                  'display_label': '测试私有适配',
                  'hard_conflicts': [
                    {
                      'type': 'ALLERGEN_CONFLICT',
                      'allergen_id': id,
                      'message': '测试私有过敏结论',
                    },
                  ],
                  'uncertainties': [],
                  'catalog_standard_version_id': id,
                  'fit_rule_version': 'pawday-fit-1',
                  'life_stage_id': null,
                },
              },
          ],
        };
      } else {
        data = [
          for (final id in [first, second])
            {
              ...standard(id),
              'offers': [offer(id)],
            },
        ];
      }
      return http.Response(
        jsonEncode({
          'data': data,
          if (data is List) 'page': {'next_cursor': null, 'has_more': false},
          'meta': {'request_id': 'test', 'correlation_id': 'test'},
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          consumerApiProvider.overrideWithValue(client),
          consumerRepositoryProvider.overrideWithValue(GuestRepository(client)),
        ],
        child: const MaterialApp(home: CatalogScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CatalogScreen)),
    );
    await container.read(authProvider.notifier).login('TEST', 'TEST');
    const pet = PetContext(
      id: 'owned-pet',
      ownerUserId: 'user',
      name: 'TEST pet',
    );
    container.read(currentPetProvider.notifier).select(pet, [pet]);
    await tester.pumpAndSettle();
    expect(
      find.byType(Checkbox),
      findsNWidgets(2),
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((x) => x.data)
          .join(' | '),
    );
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();
    final compare = find.text('比较已选商品（2/4）');
    await tester.ensureVisible(compare);
    await tester.tap(compare);
    await tester.pumpAndSettle();
    expect(find.text('测试私有过敏结论'), findsNWidgets(2));
    await container.read(authProvider.notifier).logout();
    await tester.pumpAndSettle();
    expect(find.text('测试私有过敏结论'), findsNothing);
    expect(find.text('登录或宠物已变化'), findsOneWidget);
    client.dispose();
  });
}
