import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/order_repository.dart';
import 'package:pawday_consumer/order_screen.dart';
import 'package:pawday_consumer/repositories.dart';

import 'checkout_test.dart'
    show client, envelope, failure, quoteFixture, address;
import 'navigation_test.dart' show GuestRepository;

Map<String, dynamic> summary() => {
  'id': 'order',
  'order_no': 'TEST私有订单',
  'quote_id': 'quote',
  'currency': 'CNY',
  'goods_amount_fen': 2000,
  'shipping_amount_fen': 500,
  'discount_amount_fen': 0,
  'payable_amount_fen': 2500,
  'policy_version_id': 'policy',
  'reservation_expires_at': DateTime.now()
      .add(const Duration(minutes: 15))
      .toUtc()
      .toIso8601String(),
  'status': 'PENDING_PAYMENT',
  'version': 0,
  'created_at': DateTime.now().toUtc().toIso8601String(),
};
Map<String, dynamic> orderFixture() => {
  ...summary(),
  'payment': {
    'id': 'payment',
    'payment_no': 'PTEST',
    'order_id': 'order',
    'amount_fen': 2500,
    'currency': 'CNY',
    'status': 'PENDING',
    'expires_at': summary()['reservation_expires_at'],
    'version': 0,
    'created_at': summary()['created_at'],
  },
  'address_snapshot': address,
  'pricing_snapshot': quoteFixture(),
  'suborders': [],
  'reservations': [],
  'cancellation': null,
};
Future<ProviderContainer> mount(WidgetTester tester, ConsumerApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        consumerApiProvider.overrideWithValue(api),
        consumerRepositoryProvider.overrideWithValue(GuestRepository(api)),
      ],
      child: const MaterialApp(home: OrdersScreen()),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(OrdersScreen)),
  );
  await container.read(authProvider.notifier).login('TEST', 'TEST');
  await tester.pumpAndSettle();
  return container;
}

void main() {
  test(
    'order wire uses only frozen quote and cancellation requires exact version',
    () async {
      final calls = <http.Request>[];
      final api = client((r) async {
        calls.add(r);
        return envelope(orderFixture());
      });
      final repo = OrderRepository(api);
      await repo.create('quote', 'order-stable-command');
      await repo.cancel(
        Order.fromJson(orderFixture()),
        'cancel-stable-command',
      );
      expect(jsonDecode(calls.first.body), {'quote_id': 'quote'});
      expect(calls.first.headers['Idempotency-Key'], 'order-stable-command');
      expect(calls.last.headers['If-Match'], '"0"');
      expect(jsonDecode(calls.last.body), {
        'reason_code': 'CONSUMER_CANCELLED',
      });
      api.dispose();
    },
  );
  testWidgets('late private order response is discarded after logout', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final api = client(
      (r) async => r.url.path.endsWith('/orders/order')
          ? pending.future
          : envelope([summary()]),
    );
    final container = await mount(tester, api);
    await tester.tap(find.byTooltip('刷新订单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TEST私有订单'));
    await tester.pump();
    await container.read(authProvider.notifier).logout();
    await tester.pump();
    pending.complete(envelope(orderFixture()));
    await tester.pumpAndSettle();
    expect(find.text('TEST私有订单'), findsNothing);
    expect(find.textContaining('付款期限'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
    'whole unpaid cancellation needs confirmation and retries the same key',
    (tester) async {
      final calls = <http.Request>[];
      final api = client((r) async {
        if (r.url.path.endsWith('/cancel')) {
          calls.add(r);
          return failure('PERSISTENCE_UNAVAILABLE');
        }
        return r.url.path.endsWith('/orders/order')
            ? envelope(orderFixture())
            : envelope([summary()]);
      });
      await mount(tester, api);
      await tester.tap(find.byTooltip('刷新订单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TEST私有订单'));
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.text('取消未付款整单'));
        await tester.pumpAndSettle();
        expect(calls.length, attempt);
        expect(find.textContaining('不能只取消其中一部分'), findsOneWidget);
        await tester.tap(find.text('确认取消'));
        await tester.pumpAndSettle();
      }
      expect(calls.length, 2);
      expect(
        calls[0].headers['Idempotency-Key'],
        calls[1].headers['Idempotency-Key'],
      );
      expect(calls.last.headers['If-Match'], '"0"');
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );
  testWidgets('order detail clears immediately on account change', (
    tester,
  ) async {
    final api = client(
      (r) async => r.url.path.endsWith('/orders/order')
          ? envelope(orderFixture())
          : envelope([summary()]),
    );
    final container = await mount(tester, api);
    await tester.tap(find.byTooltip('刷新订单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TEST私有订单'));
    await tester.pumpAndSettle();
    expect(find.textContaining('应付 ¥25.00'), findsOneWidget);
    await container.read(authProvider.notifier).logout();
    await tester.pumpAndSettle();
    expect(find.textContaining('应付 ¥25.00'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
