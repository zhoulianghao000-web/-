import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/order_repository.dart';
import 'package:pawday_consumer/fulfillment_card.dart';
import 'package:pawday_consumer/repositories.dart';

import 'checkout_test.dart' show client, envelope;
import 'navigation_test.dart' show GuestRepository;

Map<String, dynamic> fulfillment() => {
  'suborder_id': 'sub',
  'version': 2,
  'fulfillment_status': 'SHIPPED_WAITING_RECEIPT',
  'items': [
    {
      'order_item_id': 'item',
      'quantity': 1,
      'cancelled_qty': 0,
      'shipped_qty': 1,
      'received_qty': 0,
    },
  ],
  'delivery_address': null,
  'shipments': [
    {
      'id': 'shipment',
      'suborder_id': 'sub',
      'carrier_code': 'SF',
      'tracking_no': 'PRIVATE PARCEL',
      'created_at': '2026-10-05T00:00:00Z',
      'confirmed_at': null,
      'items': [
        {'order_item_id': 'item', 'quantity': 1},
      ],
    },
  ],
};
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
        home: Scaffold(
          body: FulfillmentCard(suborderId: 'sub', onChanged: () {}),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

void main() {
  test(
    'receipt sends only selected parcel with version and stable command key',
    () async {
      late http.Request request;
      final api = client((r) async {
        request = r;
        return envelope(fulfillment());
      });
      await OrderRepository(api).receive(Fulfillment.fromJson(fulfillment()), [
        'shipment',
      ], 'stable-receipt-command');
      expect(jsonDecode(request.body), {
        'shipment_ids': ['shipment'],
      });
      expect(request.headers['If-Match'], '"2"');
      expect(request.headers['Idempotency-Key'], 'stable-receipt-command');
      api.dispose();
    },
  );
  testWidgets('logout discards late private shipment', (tester) async {
    final pending = Completer<http.Response>();
    final api = client((_) => pending.future);
    final container = await mountCard(tester, api);
    await container.read(authProvider.notifier).logout();
    pending.complete(envelope(fulfillment()));
    await tester.pumpAndSettle();
    expect(find.text('SF · PRIVATE PARCEL'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    api.dispose();
  });
  testWidgets('parcel receipt requires explicit confirmation', (tester) async {
    int writes = 0;
    final api = client((r) async {
      if (r.method == 'POST') writes++;
      return envelope(fulfillment());
    });
    final container = await mountCard(tester, api);
    await tester.tap(find.text('确认这个包裹收货'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.tap(find.text('暂不确认'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    api.dispose();
  });
}
