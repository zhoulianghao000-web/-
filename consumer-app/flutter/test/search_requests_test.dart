import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pawday_consumer/catalog_screen.dart';
import 'package:pawday_consumer/catalog_repository.dart';
import 'package:pawday_consumer/purchase_request_screen.dart';
import 'package:pawday_consumer/repositories.dart';
import 'package:pawday_consumer/reference_ui.dart';

import 'api_test.dart' as fixture;
import 'pet_test.dart' show SignedIn, page;

void main() {
  test(
    'facet repository reaches the allowed public endpoint and parses options',
    () async {
      final calls = <Uri>[];
      final api = fixture.apiWith((r) async {
        calls.add(r.url);
        return fixture.ok({
          'brands': [
            {'value': 'brand', 'label': 'TEST brand'},
          ],
          'food_types': [],
          'package_units': [],
          'life_stages': [],
          'allergens': [],
        });
      });
      addTearDown(api.dispose);
      final facets = await CatalogRepository(api).facets();
      expect(calls.single.path, '/api/v1/public/products/facets');
      expect(facets.brands.single.label, 'TEST brand');
    },
  );
  Future<void> mount(
    WidgetTester t,
    Widget child,
    Future<http.Response> Function(http.Request) network, {
    double scale = 1,
  }) async {
    final api = fixture.apiWith(network);
    addTearDown(api.dispose);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          consumerApiProvider.overrideWithValue(api),
          authProvider.overrideWith(SignedIn.new),
        ],
        child: MaterialApp(
          theme: PawdayDesign.theme,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: child),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  http.Response catalog(http.Request r) => r.url.path.endsWith('/facets')
      ? fixture.ok({
          'brands': [],
          'food_types': [],
          'package_units': [],
          'life_stages': [],
          'allergens': [],
        })
      : page([]);
  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  testWidgets(
    'invalid price interval prevents query; valid decimal becomes integer fen',
    (t) async {
      final queries = <http.Request>[];
      await mount(t, const CatalogScreen(), (r) async {
        if (!r.url.path.endsWith('/facets')) queries.add(r);
        return catalog(r);
      });
      await t.tap(find.text('筛选与排序'));
      await t.pumpAndSettle();
      await t.ensureVisible(field('最低商品价（元）'));
      await t.enterText(field('最低商品价（元）'), '12.34');
      await t.ensureVisible(field('最高商品价（元）'));
      await t.enterText(field('最高商品价（元）'), '10');
      final apply = find.text('查询 / 刷新');
      await t.ensureVisible(apply);
      await t.tap(apply);
      await t.pumpAndSettle();
      expect(queries, hasLength(1));
      expect(find.text('最低值不能大于最高值'), findsOneWidget);
      await t.ensureVisible(field('最高商品价（元）'));
      await t.enterText(field('最高商品价（元）'), '20.5');
      await t.ensureVisible(apply);
      await t.tap(apply);
      await t.pumpAndSettle();
      expect(queries.last.url.queryParameters['price_min_fen'], '1234');
      expect(queries.last.url.queryParameters['price_max_fen'], '2050');
      expect(find.text('没有找到符合条件的商品'), findsOneWidget);
    },
  );
  testWidgets(
    'purchase form validates title and prevents concurrent writes with original context',
    (t) async {
      final writes = <http.Request>[];
      final done = Completer<http.Response>();
      await mount(
        t,
        const PurchaseRequestForm(searchContext: {'price_max_fen': '2000'}),
        (r) {
          writes.add(r);
          return done.future;
        },
      );
      await t.tap(find.text('提交求购'));
      await t.pumpAndSettle();
      expect(find.text('请填写商品名称'), findsOneWidget);
      expect(writes, isEmpty);
      await t.enterText(find.byType(TextFormField).first, 'TEST 找粮');
      await t.tap(find.text('提交求购'));
      await t.pump();
      expect(writes, hasLength(1));
      expect(find.text('提交中…'), findsOneWidget);
      await t.tap(find.text('提交中…'), warnIfMissed: false);
      await t.pump();
      expect(writes, hasLength(1));
      final body = jsonDecode(writes.single.body) as Map<String, dynamic>;
      expect(body['search_context'], {'price_max_fen': '2000'});
      expect(writes.single.headers['Idempotency-Key'], isNotEmpty);
      done.complete(fixture.fail(503, 'PERSISTENCE_UNAVAILABLE'));
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'request withdraw sends expected version and terminal records hide action',
    (t) async {
      final writes = <http.Request>[];
      var cancelled = false;
      await mount(t, const PurchaseRequestsScreen(), (r) async {
        if (r.method == 'POST') {
          writes.add(r);
          cancelled = true;
          return fixture.ok({
            'id': 'request',
            'status': 'CANCELLED',
            'version': 4,
          });
        }
        return page([
          {
            'id': 'request',
            'title': 'TEST 求购',
            'description': 'TEST',
            'search_context': {'q': 'TEST'},
            'status': cancelled ? 'CANCELLED' : 'OPEN',
            'response': null,
            'version': cancelled ? 4 : 3,
            'created_at': '2026-10-12T00:00:00Z',
            'updated_at': '2026-10-12T00:00:00Z',
          },
        ]);
      });
      await t.ensureVisible(find.text('撤回求购'));
      await t.tap(find.text('撤回求购'));
      await t.pumpAndSettle();
      await t.tap(find.text('确认撤回'));
      await t.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(writes.single.headers['If-Match'], '"3"');
      expect(find.text('已撤回'), findsOneWidget);
      expect(find.text('撤回求购'), findsNothing);
    },
  );
  testWidgets(
    'expanded filters and purchase form fit narrow layout with large text',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await mount(
        t,
        const CatalogScreen(),
        (r) async => catalog(r),
        scale: 1.6,
      );
      await t.tap(find.text('筛选与排序'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await mount(
        t,
        const PurchaseRequestForm(searchContext: {'q': 'TEST'}),
        (r) async => fixture.ok(null),
        scale: 1.6,
      );
      await t.ensureVisible(find.text('提交求购'));
      expect(t.takeException(), isNull);
    },
  );
}
