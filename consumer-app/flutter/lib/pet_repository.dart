import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'repositories.dart';

class PetRepository {
  final ConsumerApi api;
  PetRepository(this.api);
  Future<List<Species>> taxonomy() async => SpeciesListEnvelope.fromJson(
    await api.request(
      'GET',
      ApiRoutes.get_public_pet_taxonomy,
      anonymous: true,
    ),
  ).data;
  Future<List<Breed>> breeds(String id) async => BreedListEnvelope.fromJson(
    await api.request('GET', '/public/pet-species/$id/breeds', anonymous: true),
  ).data;
  Future<List<Allergen>> allergens() async => AllergenListEnvelope.fromJson(
    await api.request('GET', ApiRoutes.get_public_allergens, anonymous: true),
  ).data;
  Future<List<Pet>> list() async {
    final result = <Pet>[];
    String? cursor;
    do {
      final page = PetListEnvelope.fromJson(
        await api.request(
          'GET',
          '${ApiRoutes.get_consumer_pets}${cursor == null ? '' : '?cursor=${Uri.encodeQueryComponent(cursor)}'}',
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

  Future<Pet> save(
    Map<String, dynamic> body, {
    Pet? existing,
    required String key,
  }) async => PetEnvelope.fromJson(
    await api.request(
      existing == null ? 'POST' : 'PATCH',
      existing == null
          ? ApiRoutes.post_consumer_pets
          : '/consumer/pets/${existing.id}',
      body: body,
      idempotencyKey: key,
      version: existing?.version,
    ),
  ).data;
  Future<void> delete(Pet pet, String key) async {
    await api.request(
      'DELETE',
      '/consumer/pets/${pet.id}',
      idempotencyKey: key,
      version: pet.version,
    );
  }

  Future<List<Weight>> weights(Pet pet) async {
    final result = <Weight>[];
    String? cursor;
    do {
      final page = WeightListEnvelope.fromJson(
        await api.request(
          'GET',
          '/consumer/pets/${pet.id}/weight-records${cursor == null ? '' : '?cursor=${Uri.encodeQueryComponent(cursor)}'}',
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

  Future<void> recordWeight(Pet pet, int grams, String date, String key) async {
    await api.request(
      'POST',
      '/consumer/pets/${pet.id}/weight-records',
      version: pet.version,
      idempotencyKey: key,
      body: WeightRequest(
        weight_g: grams,
        recorded_on: date,
        source: 'OWNER_OBSERVATION',
      ).toJson(),
    );
  }
}

final petRepositoryProvider = Provider(
  (ref) => PetRepository(ref.watch(consumerApiProvider)),
);
final taxonomyProvider = FutureProvider(
  (ref) => ref.watch(petRepositoryProvider).taxonomy(),
);
final allergenDictionaryProvider = FutureProvider(
  (ref) => ref.watch(petRepositoryProvider).allergens(),
);
final breedsProvider = FutureProvider.family<List<Breed>, String>(
  (ref, id) => ref.watch(petRepositoryProvider).breeds(id),
);
final petsProvider = FutureProvider<List<Pet>>((ref) async {
  final owner = ref.watch(authProvider).principal?.user_id;
  if (owner == null) return [];
  final pets = await ref.watch(petRepositoryProvider).list();
  if (ref.read(authProvider).principal?.user_id != owner) {
    throw const ApiFailure(401, 'SESSION_CHANGED');
  }
  return pets;
});
final weightsProvider = FutureProvider.family<List<Weight>, Pet>((
  ref,
  pet,
) async {
  final owner = ref.watch(authProvider).principal?.user_id;
  if (owner == null) return [];
  final result = await ref.watch(petRepositoryProvider).weights(pet);
  if (ref.read(authProvider).principal?.user_id != owner) {
    throw const ApiFailure(401, 'SESSION_CHANGED');
  }
  return result;
});
String newPetCommandKey() => const Uuid().v4();
