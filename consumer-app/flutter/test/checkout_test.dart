import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/checkout_repository.dart';
import 'package:pawday_consumer/checkout_screen.dart';
import 'package:pawday_consumer/repositories.dart';

import 'navigation_test.dart' show GuestRepository;

final item = {
  'id': 'item',
  'cart_id': 'cart',
  'offer_id': 'offer',
  'pet_id': null,
  'quantity': 2,
  'active': true,
  'version': 0,
  'created_at': 'TEST',
  'availability': 'AVAILABLE',
  'name': 'TEST商品',
  'merchant_name': 'TEST商家',
  'sale_price_fen': 1000,
  'available_qty': 10,
};
final address = {
  'id': 'address',
  'recipient': 'TEST私有收件人',
  'phone': '13800000000',
  'province_code': '310000',
  'city_code': null,
  'district_code': null,
  'detail': 'TEST私有门牌',
  'status': 'ACTIVE',
  'version': 0,
  'created_at': 'TEST',
};
Map<String, dynamic> quoteFixture() => {
  'quote_id': 'quote',
  'status': 'ACTIVE',
  'version': 0,
  'expires_at': DateTime.now()
      .add(const Duration(seconds: 900))
      .toUtc()
      .toIso8601String(),
  'currency': 'CNY',
  'goods_amount_fen': 2000,
  'shipping_amount_fen': 500,
  'discount_amount_fen': 0,
  'payable_amount_fen': 2500,
  'pricing_rule_version': 'PRICING_V1_1',
  'algorithm_version': 'LARGEST_REMAINDER_V1',
  'address_snapshot': address,
  'membership_snapshot': {'used': false},
  'items': [
    {
      'sku_id': 'sku',
      'merchant_id': 'merchant',
      'cart_item_id': 'item',
      'cart_item_version': 0,
      'offer_id': 'offer',
      'offer_version': 1,
      'catalog_standard_version_id': 'standard',
      'quantity': 2,
      'unit_price_fen': 1000,
      'goods_amount_fen': 2000,
      'allocation_key': '000001',
      'name': 'TEST商品',
      'merchant_name': 'TEST商家',
      'payable_amount_fen': 2000,
      'discount_amount_fen': 0,
    },
  ],
  'merchant_groups': [
    {
      'merchant_id': 'merchant',
      'merchant_name': 'TEST商家',
      'goods_amount_fen': 2000,
      'goods_discount_fen': 0,
      'goods_payable_fen': 2000,
      'shipping_rule_id': 'shipping',
      'shipping_amount_fen': 500,
      'shipping_payable_fen': 500,
      'shipping_discount_fen': 0,
    },
  ],
  'discount_allocations': [],
};
http.Response envelope(Object data) => http.Response(
  jsonEncode({
    'data': data,
    if (data is List) 'page': {'next_cursor': null, 'has_more': false},
    'meta': {'request_id': 'TEST', 'correlation_id': 'TEST'},
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response failure(String code) => http.Response(
  jsonEncode({
    'error': {'code': code, 'message': code, 'retryable': true, 'details': {}},
    'meta': {'request_id': 'TEST', 'correlation_id': 'TEST'},
  }),
  503,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
ConsumerApi client(Future<http.Response> Function(http.Request) network) =>
    ConsumerApi(
      base: Uri.parse('http://localhost/api/v1'),
      transport: MockClient(network),
      vault: MemoryVault(),
    );
Future<http.Response> baseReply(http.Request r) async {
  if (r.url.path.endsWith('/cart')) {
    return envelope({
      'id': 'cart',
      'version': 0,
      'items': [item],
    });
  }
  if (r.url.path.endsWith('/addresses')) return envelope([address]);
  if (r.url.path.endsWith('/benefits')) {
    return envelope({'membership_eligible': false, 'coupons': []});
  }
  if (r.url.path.endsWith('/quotes')) return envelope(quoteFixture());
  return envelope(item);
}

Future<ProviderContainer> loggedIn(WidgetTester tester, ConsumerApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        consumerApiProvider.overrideWithValue(api),
        consumerRepositoryProvider.overrideWithValue(GuestRepository(api)),
      ],
      child: const MaterialApp(home: CartScreen()),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(CartScreen)),
  );
  await container.read(authProvider.notifier).login('TEST', 'TEST');
  await tester.pumpAndSettle();
  return container;
}

void main() {
  test(
    'cart quantity and quote carry explicit versions and stable command key',
    () async {
      final calls = <http.Request>[];
      final api = client((r) async {
        calls.add(r);
        return r.url.path.endsWith('/quotes')
            ? envelope(quoteFixture())
            : envelope(item);
      });
      final repo = CheckoutRepository(api);
      await repo.quantity(CartItem.fromJson(item), 3, 'stable-command-key');
      expect(calls.single.headers['If-Match'], '"0"');
      expect(calls.single.headers['Idempotency-Key'], 'stable-command-key');
      expect(jsonDecode(calls.single.body), {'quantity': 3});
      final quote = await repo.quote(['item'], 'address', 'quote-command-key');
      expect(quote.payable_amount_fen, 2500);
      expect(jsonDecode(calls.last.body), {
        'cart_item_ids': ['item'],
        'address_id': 'address',
        'coupon_ids': [],
        'use_membership': false,
      });
      api.dispose();
    },
  );
  test(
    'guest merge preserves explicit offer and can be fenced to one user',
    () {
      final c = ProviderContainer();
      c.read(guestCartProvider.notifier).add('offer');
      final intent = c.read(guestCartProvider);
      expect(intent.items.single.offer_id, 'offer');
      c.read(guestCartProvider.notifier).begin('user-a');
      expect(c.read(guestCartProvider).key, intent.key);
      c.read(guestCartProvider.notifier).begin('user-b');
      expect(c.read(guestCartProvider).items, isEmpty);
      c.dispose();
    },
  );
  testWidgets(
    'cart reads persisted items and frozen quote; new quote gets new key',
    (tester) async {
      final keys = <String>[];
      final api = client((r) async {
        if (r.url.path.endsWith('/quotes')) {
          keys.add(r.headers['Idempotency-Key']!);
        }
        return baseReply(r);
      });
      await loggedIn(tester, api);
      expect(find.text('TEST商品'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      final button = find.text('试算所选商品');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('应付 ¥25.00'), findsOneWidget);
      expect(find.textContaining('未锁定库存'), findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(keys.length, 2);
      expect(keys.first, isNot(keys.last));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      api.dispose();
    },
  );
  testWidgets('delayed cart response is discarded after logout', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final api = client(
      (r) async =>
          r.url.path.endsWith('/cart') ? response.future : baseReply(r),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          consumerApiProvider.overrideWithValue(api),
          consumerRepositoryProvider.overrideWithValue(GuestRepository(api)),
        ],
        child: const MaterialApp(home: CartScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(
      tester.element(find.byType(CartScreen)),
    );
    await c.read(authProvider.notifier).login('TEST', 'TEST');
    await tester.pump();
    await c.read(authProvider.notifier).logout();
    response.complete(
      envelope({
        'id': 'cart',
        'version': 0,
        'items': [item],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('TEST商品'), findsNothing);
    expect(find.text('请登录后查看购物车'), findsOneWidget);
    api.dispose();
  });
  testWidgets('open address dialog hides private data when session changes', (
    tester,
  ) async {
    final api = client(baseReply);
    final c = await loggedIn(tester, api);
    final edit = find.byTooltip('修改地址');
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'TEST私有收件人'), findsOneWidget);
    await c.read(authProvider.notifier).logout();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'TEST私有收件人'), findsNothing);
    expect(find.text('登录状态已变化'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    api.dispose();
  });
  testWidgets('failed guest merge retains intent and retry uses same key', (
    tester,
  ) async {
    final keys = <String>[];
    final api = client((r) async {
      if (r.url.path.endsWith('/merge-guest-intent')) {
        keys.add(r.headers['Idempotency-Key']!);
        if (keys.length == 1) return failure('PERSISTENCE_UNAVAILABLE');
        return envelope({
          'id': 'cart',
          'version': 1,
          'items': [item],
        });
      }
      return baseReply(r);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          consumerApiProvider.overrideWithValue(api),
          consumerRepositoryProvider.overrideWithValue(GuestRepository(api)),
        ],
        child: const MaterialApp(home: CartScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(
      tester.element(find.byType(CartScreen)),
    );
    c.read(guestCartProvider.notifier).add('offer');
    await c.read(authProvider.notifier).login('TEST', 'TEST');
    await tester.pumpAndSettle();
    expect(c.read(guestCartProvider).items, isNotEmpty);
    await tester.tap(find.byTooltip('刷新购物车'));
    await tester.pumpAndSettle();
    expect(keys.length, 2);
    expect(keys.first, keys.last);
    expect(c.read(guestCartProvider).items, isEmpty);
    api.dispose();
  });
}
