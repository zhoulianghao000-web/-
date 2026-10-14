import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'repositories.dart';

class HouseholdRepository {
  final ConsumerApi api;
  HouseholdRepository(this.api);
  Future<List<HouseholdPet>> pets() async {
    final result = <HouseholdPet>[];
    String? cursor;
    do {
      final page = HouseholdPetsEnvelope.fromJson(
        await api.request(
          'GET',
          '/consumer/household/pets${cursor == null ? '' : '?cursor=${Uri.encodeQueryComponent(cursor)}'}',
        ),
      );
      result.addAll(page.data);
      cursor = page.page.has_more ? page.page.next_cursor : null;
      if (page.page.has_more && cursor == null) {
        throw const ApiFailure(0, 'INVALID_PAGINATION');
      }
    } while (cursor != null);
    return result;
  }

  Future<HouseholdOverview> overview(String pet) async =>
      HouseholdOverviewEnvelope.fromJson(
        await api.request('GET', '/consumer/household/pets/$pet'),
      ).data;
  Future<Map<String, dynamic>> command(
    String path,
    String key, {
    Map<String, dynamic>? body,
    int? version,
  }) async =>
      (await api.request(
            'POST',
            '/consumer/household$path',
            body: body,
            idempotencyKey: key,
            version: version,
          ))['data']
          as Map<String, dynamic>;
}

final householdRepositoryProvider = Provider(
  (ref) => HouseholdRepository(ref.watch(consumerApiProvider)),
);
