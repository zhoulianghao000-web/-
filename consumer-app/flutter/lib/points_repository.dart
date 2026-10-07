import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'repositories.dart';

class PointsRepository {
  final ConsumerApi api;
  PointsRepository(this.api);
  Future<PointsOverview> overview() async => PointsOverviewEnvelope.fromJson(
    await api.request('GET', '/consumer/points'),
  ).data;
  Future<List<PointsLedgerEntry>> ledger({String? entryType}) async =>
      PointsLedgerEntryListEnvelope.fromJson(
        await api.request(
          'GET',
          entryType == null
              ? '/consumer/points/ledger'
              : '/consumer/points/ledger?entry_type=$entryType',
        ),
      ).data;
  Future<List<PointsReward>> rewards() async => PointsRewardListEnvelope.fromJson(
    await api.request('GET', '/consumer/points/rewards'),
  ).data;
  Future<List<PointsCheckin>> checkins() async => PointsCheckinListEnvelope.fromJson(
    await api.request('GET', '/consumer/points/checkins'),
  ).data;
  Future<PointsCheckin> checkin(String key) async => PointsCheckinEnvelope.fromJson(
    await api.request('POST', '/consumer/points/checkins', idempotencyKey: key),
  ).data;
  Future<PointsRedemption> redeem(String rewardId, String key) async =>
      PointsRedemptionEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/points/redemptions',
          body: PointsRedemptionInput(reward_id: rewardId).toJson(),
          idempotencyKey: key,
        ),
      ).data;
}

final pointsRepositoryProvider = Provider(
  (ref) => PointsRepository(ref.watch(consumerApiProvider)),
);
