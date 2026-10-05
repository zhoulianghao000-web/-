import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'repositories.dart';

class OrderRepository {
  final ConsumerApi api;
  OrderRepository(this.api);
  Future<Order> create(String quote, String key) async =>
      OrderEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/orders',
          body: OrderInput(quote_id: quote).toJson(),
          idempotencyKey: key,
        ),
      ).data;
  Future<OrderSummaryListEnvelope> list({
    String? cursor,
  }) async => OrderSummaryListEnvelope.fromJson(
    await api.request(
      'GET',
      '/consumer/orders${cursor == null ? '?limit=20' : '?limit=20&cursor=$cursor'}',
    ),
  );
  Future<Order> get(String id) async =>
      OrderEnvelope.fromJson(await api.request('GET', '/consumer/orders/$id'))
          .data;
  Future<Fulfillment> fulfillment(String sub) async =>
      FulfillmentEnvelope.fromJson(
        await api.request('GET', '/consumer/suborders/$sub/fulfillment'),
      ).data;
  Future<Tracking> tracking(String shipment) async => TrackingEnvelope.fromJson(
    await api.request('GET', '/consumer/shipments/$shipment/tracking'),
  ).data;
  Future<Fulfillment> receive(
    Fulfillment value,
    List<String> shipments,
    String key,
  ) async => FulfillmentEnvelope.fromJson(
    await api.request(
      'POST',
      '/consumer/suborders/${value.suborder_id}/confirm-receipt',
      body: ReceiptInput(shipment_ids: shipments).toJson(),
      version: value.version,
      idempotencyKey: key,
    ),
  ).data;
  Future<Order> cancel(Order order, String key) async => OrderEnvelope.fromJson(
    await api.request(
      'POST',
      '/consumer/orders/${order.id}/cancel',
      body: OrderCancelInput(reason_code: 'CONSUMER_CANCELLED').toJson(),
      version: order.version,
      idempotencyKey: key,
    ),
  ).data;
}

final orderRepositoryProvider = Provider(
  (ref) => OrderRepository(ref.watch(consumerApiProvider)),
);
