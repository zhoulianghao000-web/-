import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'repositories.dart';

class PaymentRepository {
  final ConsumerApi api;
  PaymentRepository(this.api);
  Future<PaymentDetail> get(String id) async => PaymentDetailEnvelope.fromJson(
    await api.request('GET', '/consumer/payments/$id'),
  ).data;
  Future<PaymentDetail> attempt(String id, String channel, String key) async =>
      PaymentDetailEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/payments/$id/attempts',
          body: PaymentAttemptInput(
            channel: channel,
            client_platform: kIsWeb
                ? 'WEB'
                : defaultTargetPlatform == TargetPlatform.iOS
                ? 'IOS'
                : 'ANDROID',
          ).toJson(),
          idempotencyKey: key,
        ),
      ).data;
  Future<PaymentDetail> requery(String id) async =>
      PaymentDetailEnvelope.fromJson(
        await api.request('POST', '/consumer/payments/$id/requery'),
      ).data;
  Future<PaymentDetail> close(String id) async =>
      PaymentDetailEnvelope.fromJson(
        await api.request('POST', '/consumer/payments/$id/close-attempt'),
      ).data;
  Future<PaymentDetail> simulate(
    String id,
    String attempt,
    String outcome,
  ) async => PaymentDetailEnvelope.fromJson(
    await api.request(
      'POST',
      '/consumer/payments/$id/simulation',
      body: SimulationInput(attempt_id: attempt, outcome: outcome).toJson(),
    ),
  ).data;
}

final paymentRepositoryProvider = Provider(
  (ref) => PaymentRepository(ref.watch(consumerApiProvider)),
);
