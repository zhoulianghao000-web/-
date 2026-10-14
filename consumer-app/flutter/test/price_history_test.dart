import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/catalog_repository.dart';
import 'package:pawday_consumer/price_history.dart';

Map<String, dynamic> historyData(int days) => {
  'offer_id': '00000000-0000-4000-8000-000000000021',
  'sku_id': '00000000-0000-4000-8000-000000000022',
  'days': days,
  'timezone': 'Asia/Shanghai',
  'currency': 'CNY',
  'basis': 'DAILY_LAST_RECORDED_QUOTATION',
  'as_of': '2026-10-14T01:00:00Z',
  'from_date': DateTime.utc(
    2026,
    10,
    14,
  ).subtract(Duration(days: days - 1)).toIso8601String().split('T').first,
  'to_date': '2026-10-14',
  'observed_from': null,
  'current_sale_price_fen': 1000,
  'current_member_price_fen': null,
  'offer_version': 1,
  'observed_days': 0,
  'lowest_recorded_daily_sale_price_fen': null,
  'highest_recorded_daily_sale_price_fen': null,
  'points': List.generate(
    days,
    (i) => {
      'date': DateTime.utc(2026, 10, 14)
          .subtract(Duration(days: days - 1 - i))
          .toIso8601String()
          .split('T')
          .first,
      'sale_price_fen': null,
      'member_price_fen': null,
      'sale_status': null,
      'recorded_at': null,
    },
  ),
};
ConsumerApi client(Future<http.Response> Function(http.Request) handler) =>
    ConsumerApi(
      base: Uri.parse('http://localhost/api/v1'),
      transport: MockClient(handler),
      vault: MemoryVault(),
    );
http.Response success(int days) => http.Response(
  jsonEncode({
    'data': historyData(days),
    'meta': {'request_id': 'TEST', 'correlation_id': 'TEST'},
  }),
  200,
);
Future<void> open(
  WidgetTester tester,
  CatalogRepository repo, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const PriceHistoryDialog(
                  offerId: '00000000-0000-4000-8000-000000000021',
                  merchantName: '测试门店',
                ),
              ),
              child: const Text('打开记录'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开记录'));
  await tester.pump();
  await tester.pump();
}

class DeferredHistory extends CatalogRepository {
  DeferredHistory(super.api);
  final requests = <int, Completer<OfferPriceHistory>>{};
  @override
  Future<OfferPriceHistory> priceHistory(String offer, int days) =>
      (requests[days] = Completer<OfferPriceHistory>()).future;
}

void main() {
  test('public history requests have explicit range and do not fabricate missing prices', () async {
    final api = client((r) async {
      expect(
        r.url.path,
        '/api/v1/public/offers/00000000-0000-4000-8000-000000000021/price-history',
      );
      expect(r.url.queryParameters['days'], '90');
      expect(r.headers.containsKey('authorization'), false);
      return success(90);
    });
    final result = await CatalogRepository(api)
        .priceHistory('00000000-0000-4000-8000-000000000021', 90);
    expect(result.points, hasLength(90));
    expect(result.points.every((p) => p.sale_price_fen == null), true);
    api.dispose();
  });
  testWidgets(
    'unknown history and daily details fit narrow enlarged text without a fake chart',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = client((_) async => success(30));
      await open(tester, CatalogRepository(api), textScale: 1.6);
      await tester.pumpAndSettle();
      expect(find.textContaining('暂不足以形成趋势'), findsOneWidget);
      expect(find.byType(PriceHistoryChart), findsNothing);
      await tester.ensureVisible(find.text('查看逐日记录'));
      await tester.tap(find.text('查看逐日记录'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );
  testWidgets(
    'a late 30 day response cannot overwrite selected 90 day history',
    (tester) async {
      final api = client((_) async => success(30)),
          repo = DeferredHistory(client((_) async => success(30)));
      await open(tester, repo);
      await tester.tap(find.text('90 天'));
      await tester.pump();
      repo.requests[90]!.complete(OfferPriceHistory.fromJson(historyData(90)));
      await tester.pumpAndSettle();
      repo.requests[30]!.complete(OfferPriceHistory.fromJson(historyData(30)));
      await tester.pumpAndSettle();
      expect(find.textContaining('已记录 0 / 90 天'), findsOneWidget);
      expect(find.textContaining('已记录 0 / 30 天'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
      repo.api.dispose();
    },
  );
  testWidgets('failure has explicit retry without invented records', (
    tester,
  ) async {
    int calls = 0;
    final api = client(
      (_) async => ++calls == 1
          ? http.Response(
              jsonEncode({
                'error': {
                  'code': 'SERVICE_UNAVAILABLE',
                  'message': 'TEST_ONLY',
                },
                'meta': {'request_id': 'TEST', 'correlation_id': 'TEST'},
              }),
              503,
            )
          : success(30),
    );
    await open(tester, CatalogRepository(api));
    await tester.pumpAndSettle();
    expect(find.text('价格记录暂时无法加载，请重试。'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.textContaining('已记录 0 / 30 天'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
