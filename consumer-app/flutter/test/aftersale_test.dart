import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/aftersale_card.dart';
import 'package:pawday_consumer/aftersale_repository.dart';
import 'package:pawday_consumer/repositories.dart';

import 'checkout_test.dart' show client, envelope;
import 'navigation_test.dart' show GuestRepository;

Map<String, dynamic> unpaid() => {
  'suborder_id': 'sub',
  'version': 1,
  'fulfillment_status': 'PAID_WAITING_FULFILLMENT',
  'items': [
    {
      'order_item_id': 'item',
      'quantity': 2,
      'cancelled_qty': 0,
      'shipped_qty': 0,
      'received_qty': 0,
    },
  ],
  'delivery_address': null,
  'shipments': [],
};
Map<String, dynamic> cancellation() => {
  'id': 'cancel',
  'order_id': 'order',
  'suborder_id': 'sub',
  'actor_type': 'CONSUMER',
  'actor_id': 'user',
  'reason_code': 'CONSUMER_CANCELLED',
  'status': 'COMPLETED',
  'version': 1,
  'created_at': '2026-10-05T00:00:00Z',
  'items': [
    {
      'id': 'cancel-item',
      'cancellation_id': 'cancel',
      'order_item_id': 'item',
      'quantity': 1,
      'item_payable_refund_fen': 1000,
      'shipping_refund_fen': 0,
      'allocation_snapshot': {},
      'refund_id': 'refund',
    },
  ],
  'refund': null,
  'refund_amount_fen': 1000,
};
Map<String, dynamic> afterSale({String status = 'WAITING_RETURN'}) => {
  'id': 'after',
  'suborder_id': 'sub',
  'order_id': 'order',
  'user_id': 'user',
  'merchant_id': 'merchant',
  'type': 'RETURN_REFUND',
  'reason_code': 'QUALITY_ISSUE',
  'reason_text': 'TEST 质量问题描述',
  'status': status,
  'return_carrier_code': null,
  'return_tracking_no': null,
  'version': 1,
  'created_at': '2026-10-05T00:00:00Z',
  'items': [
    {
      'id': 'after-item',
      'aftersale_id': 'after',
      'order_item_id': 'item',
      'quantity': 1,
      'item_payable_refund_fen': 1000,
      'refund_id': null,
    },
  ],
  'refund': null,
  'refund_amount_fen': 1000,
  'evidence': [],
  'decisions': [],
};
Future<http.Response> reply(http.Request r) async {
  final path = r.url.path;
  if (path.endsWith('/fulfillment')) return envelope(unpaid());
  if (path.endsWith('/cancellations')) {
    return envelope(r.method == 'POST' ? cancellation() : [cancellation()]);
  }
  if (path.endsWith('/aftersales')) {
    return envelope(r.method == 'POST' ? afterSale() : [afterSale()]);
  }
  return envelope(afterSale());
}

Future<ProviderContainer> mountCard(
  WidgetTester tester,
  ConsumerApi api,
) async {
  final container = ProviderContainer(
    overrides: [
      consumerApiProvider.overrideWithValue(api),
      consumerRepositoryProvider.overrideWithValue(GuestRepository(api)),
    ],
  );
  await container.read(authProvider.notifier).login('TEST', 'TEST');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: AfterSaleCard(suborderId: 'sub', onChanged: () {})),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

void main() {
  test('paid cancellation sends scoped items with stable command key', () async {
    late http.Request request;
    final api = client((r) async {
      request = r;
      return envelope(cancellation());
    });
    await AfterSaleRepository(api).cancelPaid(
      'sub',
      [const CancellationItemInput(order_item_id: 'item', quantity: 1)],
      'stable-cancel-command',
    );
    expect(request.url.path, '/api/v1/consumer/suborders/sub/cancellations');
    expect(jsonDecode(request.body), {
      'reason_code': 'CONSUMER_CANCELLED',
      'items': [
        {'order_item_id': 'item', 'quantity': 1},
      ],
    });
    expect(request.headers['Idempotency-Key'], 'stable-cancel-command');
    api.dispose();
  });
  test('return shipment carries version and validated payload', () async {
    late http.Request request;
    final api = client((r) async {
      request = r;
      return envelope(afterSale(status: 'RETURN_IN_TRANSIT'));
    });
    await AfterSaleRepository(api).shipReturn(
      AfterSale.fromJson(afterSale()),
      'SF',
      'RETURN123',
      'stable-return-command',
    );
    expect(request.url.path, '/api/v1/consumer/aftersales/after/return-shipment');
    expect(jsonDecode(request.body), {
      'carrier_code': 'SF',
      'tracking_no': 'RETURN123',
    });
    expect(request.headers['If-Match'], '"1"');
    expect(request.headers['Idempotency-Key'], 'stable-return-command');
    api.dispose();
  });
  testWidgets('logout discards late private after-sale data', (tester) async {
    final pending = Completer<http.Response>();
    final api = client((_) => pending.future);
    final container = await mountCard(tester, api);
    await container.read(authProvider.notifier).logout();
    pending.complete(envelope([afterSale()]));
    await tester.pumpAndSettle();
    expect(find.text('TEST 质量问题描述'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    api.dispose();
  });
  testWidgets('withdrawal requires explicit confirmation', (tester) async {
    int writes = 0;
    final api = client((r) async {
      if (r.method == 'POST') writes++;
      return reply(r);
    });
    final container = await mountCard(tester, api);
    await tester.tap(find.text('撤销申请'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.tap(find.text('暂不撤销'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    api.dispose();
  });
  testWidgets('paid cancellation dialog validates quantity before writing', (
    tester,
  ) async {
    int writes = 0;
    final api = client((r) async {
      if (r.method == 'POST') writes++;
      return reply(r);
    });
    final container = await mountCard(tester, api);
    await tester.tap(find.text('取消未发货商品（可取消 2 件）'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField).first, '3');
    await tester.tap(find.text('确认取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(writes, 0, reason: '超过可取消数量不能提交');
    await tester.enterText(find.byType(TextField).first, '1');
    await tester.tap(find.text('确认取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(writes, 1);
    expect(find.textContaining('已取消并退款'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    api.dispose();
  });
}
