import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'repositories.dart';

class MembershipRepository {
  final ConsumerApi api;
  MembershipRepository(this.api);
  Future<List<MembershipPlan>> plans() async => MembershipPlanListEnvelope.fromJson(
    await api.request('GET', '/consumer/membership/plans'),
  ).data;
  Future<MembershipStatus> current() async => MembershipStatusEnvelope.fromJson(
    await api.request('GET', '/consumer/membership'),
  ).data;
  Future<List<MembershipOrder>> orders() async => MembershipOrderListEnvelope.fromJson(
    await api.request('GET', '/consumer/membership/orders'),
  ).data;
  Future<MembershipOrderDetail> order(String id) async =>
      MembershipOrderDetailEnvelope.fromJson(
        await api.request('GET', '/consumer/membership/orders/$id'),
      ).data;
  Future<MembershipOrderDetail> purchase(String planCode, String key) async =>
      MembershipOrderDetailEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/membership/orders',
          body: MembershipPurchaseInput(plan_code: planCode).toJson(),
          idempotencyKey: key,
        ),
      ).data;
}

final membershipRepositoryProvider = Provider(
  (ref) => MembershipRepository(ref.watch(consumerApiProvider)),
);
