import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'repositories.dart';

class AfterSaleRepository {
  final ConsumerApi api;
  AfterSaleRepository(this.api);
  Future<Cancellation> cancelPaid(
    String suborder,
    List<CancellationItemInput> items,
    String key,
  ) async => CancellationEnvelope.fromJson(
    await api.request(
      'POST',
      '/consumer/suborders/$suborder/cancellations',
      body: CancellationInput(
        reason_code: 'CONSUMER_CANCELLED',
        items: items,
      ).toJson(),
      idempotencyKey: key,
    ),
  ).data;
  Future<CancellationListEnvelope> cancellations(String suborder) async =>
      CancellationListEnvelope.fromJson(
        await api.request('GET', '/consumer/suborders/$suborder/cancellations'),
      );
  Future<Cancellation> getCancellation(String id) async =>
      CancellationEnvelope.fromJson(
        await api.request('GET', '/consumer/cancellations/$id'),
      ).data;
  Future<AfterSale> apply(String suborder, AfterSaleInput input, String key) async =>
      AfterSaleEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/suborders/$suborder/aftersales',
          body: input.toJson(),
          idempotencyKey: key,
        ),
      ).data;
  Future<AfterSaleListEnvelope> aftersales(String suborder) async =>
      AfterSaleListEnvelope.fromJson(
        await api.request('GET', '/consumer/suborders/$suborder/aftersales'),
      );
  Future<AfterSale> getAftersale(String id) async => AfterSaleEnvelope.fromJson(
    await api.request('GET', '/consumer/aftersales/$id'),
  ).data;
  Future<AfterSale> cancelAftersale(AfterSale value, String key) async =>
      AfterSaleEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/aftersales/${value.id}/cancel',
          body: const EmptyInput().toJson(),
          version: value.version,
          idempotencyKey: key,
        ),
      ).data;
  Future<AfterSale> shipReturn(
    AfterSale value,
    String carrier,
    String tracking,
    String key,
  ) async => AfterSaleEnvelope.fromJson(
    await api.request(
      'POST',
      '/consumer/aftersales/${value.id}/return-shipment',
      body: ReturnShipmentInput(
        carrier_code: carrier,
        tracking_no: tracking,
      ).toJson(),
      version: value.version,
      idempotencyKey: key,
    ),
  ).data;
  Future<AfterSale> escalate(AfterSale value, String reason, String key) async =>
      AfterSaleEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/aftersales/${value.id}/escalate',
          body: AfterSaleReasonInput(reason: reason).toJson(),
          version: value.version,
          idempotencyKey: key,
        ),
      ).data;
}

final afterSaleRepositoryProvider = Provider(
  (ref) => AfterSaleRepository(ref.watch(consumerApiProvider)),
);
