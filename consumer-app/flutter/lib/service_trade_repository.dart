import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'repositories.dart';

class ServiceTradeRepository {
  final ConsumerApi api;
  ServiceTradeRepository(this.api);
  String page(String path, String? cursor) => Uri(
    path: path,
    queryParameters: {'limit': '20', 'cursor': ?cursor},
  ).toString();
  Future<ServiceTradeListEnvelope> mine([String? cursor]) async =>
      ServiceTradeListEnvelope.fromJson(
        await api.request(
          'GET',
          page('/consumer/service-trade-orders', cursor),
        ),
      );
  Future<ConsumerServiceTerms> terms(String service) async =>
      ConsumerServiceTermsEnvelope.fromJson(
        await api.request(
          'GET',
          '/consumer/booking-services/$service/trade-terms',
        ),
      ).data;
  Future<BookingSlotListEnvelope> slots(
    String service, [
    String? cursor,
  ]) async => BookingSlotListEnvelope.fromJson(
    await api.request(
      'GET',
      page('/consumer/booking-services/$service/slots', cursor),
    ),
  );
  Future<ServiceQuote> quote(
    ConsumerServiceTerms terms,
    BookingSlot slot,
    String key,
  ) async => ServiceQuoteEnvelope.fromJson(
    await api.request(
      'POST',
      '/consumer/service-trade-quotes',
      body: ServiceQuoteInput(terms_id: terms.id, slot_id: slot.id).toJson(),
      idempotencyKey: key,
    ),
  ).data;
  Future<ServiceTrade> reserve(ServiceQuote quote, String key) async =>
      ServiceTradeEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/service-trade-orders',
          body: CreateServiceTrade(
            quote_id: quote.id,
            accepted_terms_sha256: quote.terms_sha256,
          ).toJson(),
          idempotencyKey: key,
        ),
      ).data;
  Future<void> payment(
    ServiceTrade trade,
    String key, {
    bool requery = false,
  }) async {
    await api.request(
      'POST',
      '/consumer/service-trade-orders/${trade.id}/${requery ? 'payment-requery' : 'payment-attempts'}',
      body: requery
          ? <String, dynamic>{}
          : const ServiceAttemptInput(
              channel: 'SIMULATED_TEST',
              client_platform: kIsWeb ? 'WEB' : 'ANDROID',
            ).toJson(),
      idempotencyKey: key,
      version: trade.version,
    );
  }

  Future<void> cancel(ServiceTrade trade, String key) async {
    await api.request(
      'POST',
      '/consumer/service-trade-orders/${trade.id}/cancel',
      body: const ConsumerCancelInput(reason_code: 'CONSUMER_CANCELLED')
          .toJson(),
      idempotencyKey: key,
      version: trade.version,
    );
  }

  Future<ServiceTradeCredential> credential(ServiceTrade trade) async =>
      ServiceTradeCredentialEnvelope.fromJson(
        await api.request(
          'GET',
          '/consumer/service-trade-orders/${trade.id}/credential',
        ),
      ).data;
  Future<ServiceTradeFulfillmentEventListEnvelope> history(
    ServiceTrade trade, [
    String? cursor,
  ]) async => ServiceTradeFulfillmentEventListEnvelope.fromJson(
    await api.request(
      'GET',
      page('/consumer/service-trade-orders/${trade.id}/fulfillment', cursor),
    ),
  );
  Future<ServiceTradeDisputeListEnvelope> disputes(
    ServiceTrade trade, [
    String? cursor,
  ]) async => ServiceTradeDisputeListEnvelope.fromJson(
    await api.request(
      'GET',
      page('/consumer/service-trade-orders/${trade.id}/disputes', cursor),
    ),
  );
  Future<ServiceRefundListEnvelope> refunds(
    ServiceTrade trade, [
    String? cursor,
  ]) async => ServiceRefundListEnvelope.fromJson(
    await api.request(
      'GET',
      page('/consumer/service-trade-orders/${trade.id}/refunds', cursor),
    ),
  );
  Future<void> dispute(ServiceTrade trade, String reason, String key) async {
    await api.request(
      'POST',
      '/consumer/service-trade-orders/${trade.id}/disputes',
      body: ServiceTradeDisputeInput(
        reason_code: reason,
        evidence_refs: const [
          Evidence(kind: 'TEST_SCENARIO', reference: 'TEST_ONLY_CONSUMER_UI'),
        ],
      ).toJson(),
      idempotencyKey: key,
      version: trade.version,
    );
  }
}

final serviceTradeRepositoryProvider = Provider(
  (ref) => ServiceTradeRepository(ref.watch(consumerApiProvider)),
);
