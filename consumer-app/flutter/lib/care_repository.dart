import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'repositories.dart';

class CareRepository {
  final ConsumerApi api;
  CareRepository(this.api);
  Future<PetFoodPlan?> food(String pet) async =>
      PetFoodPlanOptionalEnvelope.fromJson(
        await api.request('GET', '/consumer/pets/$pet/food'),
      ).data;
  Future<PetFoodPlan> start(
    String pet,
    PetFoodInput input,
    int version,
    String key,
  ) async => PetFoodPlanEnvelope.fromJson(
    await api.request(
      'PUT',
      '/consumer/pets/$pet/food',
      body: input.toJson(),
      version: version,
      idempotencyKey: key,
    ),
  ).data;
  Future<PetFoodPlan> calibrate(
    PetFoodPlan plan,
    int grams,
    String date,
    String key,
  ) async => PetFoodPlanEnvelope.fromJson(
    await api.request(
      'POST',
      '/consumer/pets/${plan.pet_id}/food/calibrations',
      body: PetFoodCalibration(remaining_g: grams, recorded_on: date).toJson(),
      version: plan.version,
      idempotencyKey: key,
    ),
  ).data;
  Future<PetFoodPlan> stop(PetFoodPlan plan, String key) async =>
      PetFoodPlanEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/pets/${plan.pet_id}/food/stop',
          version: plan.version,
          idempotencyKey: key,
        ),
      ).data;
  Future<FavoriteListEnvelope> favorites({String? cursor}) async =>
      FavoriteListEnvelope.fromJson(
        await api.request(
          'GET',
          Uri(
            path: '/consumer/favorites',
            queryParameters: {'cursor': ?cursor, 'limit': '30'},
          ).toString(),
        ),
      );
  Future<Favorite> favorite(String kind, String target, String key) async =>
      FavoriteEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/favorites',
          body: FavoriteInput(kind: kind, target_id: target).toJson(),
          idempotencyKey: key,
        ),
      ).data;
  Future<void> remove(String id, String key) async {
    await api.request('DELETE', '/consumer/favorites/$id', idempotencyKey: key);
  }
}

final careRepositoryProvider = Provider(
  (ref) => CareRepository(ref.watch(consumerApiProvider)),
);
final foodPlanProvider = FutureProvider.autoDispose
    .family<PetFoodPlan?, String>((ref, pet) async {
      final session = ref.watch(authProvider).principal?.session_id;
      if (session == null) throw const ApiFailure(401, 'UNAUTHENTICATED');
      final value = await ref.watch(careRepositoryProvider).food(pet);
      if (ref.read(authProvider).principal?.session_id != session) {
        throw const ApiFailure(401, 'SESSION_CHANGED');
      }
      return value;
    });
String careKey() => const Uuid().v4();
String careError(Object error) => error is ApiFailure
    ? switch (error.code) {
        'INVOICE_ALREADY_REQUESTED' => '该子订单已有申请，请到发票申请页查看。',
        'CONCURRENT_MODIFICATION' => '记录已更新，请刷新后重新填写。',
        'RESOURCE_NOT_FOUND' => '记录或商品已不可用，请刷新重试。',
        'VALIDATION_ERROR' => '请检查日期和克数；校准日期不能早于上次记录。',
        'UNAUTHENTICATED' || 'SESSION_CHANGED' => '请重新登录后继续。',
        _ => '暂时无法完成，请稍后重试。',
      }
    : '连接失败，请稍后重试。';
