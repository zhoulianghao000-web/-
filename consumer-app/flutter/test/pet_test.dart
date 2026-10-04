import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/pet_repository.dart';
import 'package:pawday_consumer/pet_screen.dart';
import 'package:pawday_consumer/repositories.dart';

import 'api_test.dart' as fixture;
import 'navigation_test.dart' show GuestRepository;

const catId = '10000000-0000-4000-8000-000000000001';
Map<String, dynamic> petJson({
  String id = 'pet',
  String name = '米粒',
  int version = 0,
}) => {
  'id': id,
  'name': name,
  'species_id': catId,
  'breed_id': null,
  'birth_date': null,
  'age_estimate_months': null,
  'sex': 'UNKNOWN',
  'neutered_status': 'UNKNOWN',
  'allergens': [],
  'avoidance_notes': [],
  'version': version,
  'life_stage_id': null,
  'life_stage_unknown': true,
};
http.Response page(List<Object?> values, {String? cursor, bool more = false}) =>
    http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'data': values,
          'page': {'next_cursor': cursor, 'has_more': more},
          'meta': fixture.meta,
        }),
      ),
      200,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );

class SignedIn extends AuthNotifier {
  @override
  AuthState build() => const AuthState(principal: fixture.principal);
}

class ScreenPets extends PetRepository {
  ScreenPets(super.api);
  List<Pet> values = [Pet.fromJson(petJson())];
  @override
  Future<List<Pet>> list() async => values;
  @override
  Future<List<Species>> taxonomy() async => [
    Species(
      id: catId,
      parent_id: null,
      name: '猫',
      category: 'CAT',
      life_stages: [],
    ),
  ];
  @override
  Future<List<Breed>> breeds(String id) async => [];
  @override
  Future<List<Allergen>> allergens() async => [];
  @override
  Future<void> delete(Pet pet, String key) async {
    values = [];
  }

  @override
  Future<Pet> save(
    Map<String, dynamic> body, {
    Pet? existing,
    required String key,
  }) async {
    final pet = Pet.fromJson({...petJson(id: 'new'), 'name': body['name']});
    values = [pet];
    return pet;
  }
}

void main() {
  test('generated DTO preserves unknown allergy and nullable birthday', () {
    final raw = petJson();
    raw['allergens'] = [
      {'allergen_id': 'a', 'status': 'UNKNOWN', 'source': 'OWNER_OBSERVATION'},
    ];
    final p = Pet.fromJson(raw);
    expect(p.life_stage_unknown, true);
    expect(p.birth_date, isNull);
    expect(p.allergens!.first.status, 'UNKNOWN');
  });
  test('public taxonomy allowed while admin and arbitrary public routes are denied', () async {
    final api = fixture.apiWith((_) async => page([]));
    final repo = PetRepository(api);
    expect(await repo.taxonomy(), isEmpty);
    expect(await repo.breeds(catId), isEmpty);
    await expectLater(
      api.request('GET', '/admin/pet-taxonomy'),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      api.request('GET', '/public/arbitrary'),
      throwsA(isA<ApiFailure>()),
    );
    api.dispose();
  }, skip: false);
  test('profile lists follow every server cursor', () async {
    final api = fixture.apiWith(
      (r) async => r.url.queryParameters['cursor'] == null
          ? page([petJson()], cursor: 'next', more: true)
          : page([petJson(id: 'pet2')]),
    );
    final pets = await PetRepository(api).list();
    expect(pets.map((p) => p.id), ['pet', 'pet2']);
    api.dispose();
  });
  test(
    'patch carries quoted version, stable command key and explicit null',
    () async {
      int requests = 0;
      final api = fixture.apiWith((r) async {
        requests++;
        expect(r.headers['If-Match'], '"4"');
        expect(r.headers['Idempotency-Key'], 'same-command-12345');
        expect((jsonDecode(r.body) as Map).containsKey('breed_id'), true);
        expect((jsonDecode(r.body) as Map)['breed_id'], isNull);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({'data': petJson(version: 5), 'meta': fixture.meta}),
          ),
          200,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      });
      final repo = PetRepository(api);
      final pet = Pet.fromJson(petJson(version: 4));
      await repo.save(
        {'name': '改名', 'breed_id': null},
        existing: pet,
        key: 'same-command-12345',
      );
      await repo.save(
        {'name': '改名', 'breed_id': null},
        existing: pet,
        key: 'same-command-12345',
      );
      expect(requests, 2);
      api.dispose();
    },
  );
  test(
    '409 is retained for user refresh instead of silent overwrite',
    () async {
      final api = fixture.apiWith(
        (_) async => fixture.fail(409, 'CONCURRENT_MODIFICATION'),
      );
      await expectLater(
        PetRepository(api).save(
          {'name': '改名'},
          existing: Pet.fromJson(petJson()),
          key: 'conflict-command',
        ),
        throwsA(
          isA<ApiFailure>().having((e) => e.versionConflict, 'conflict', true),
        ),
      );
      api.dispose();
    },
  );
  test(
    'logout prevents a late pet list from repopulating private state',
    () async {
      final response = Completer<http.Response>();
      final api = fixture.apiWith((_) => response.future);
      final container = ProviderContainer(
        overrides: [
          consumerApiProvider.overrideWithValue(api),
          consumerRepositoryProvider.overrideWithValue(GuestRepository(api)),
        ],
      );
      await container.read(authProvider.notifier).login('phone', 'code');
      final subscription = container.listen(petsProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      await container.read(authProvider.notifier).logout();
      response.complete(page([petJson()]));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(container.read(petsProvider).asData?.value, isEmpty);
      subscription.close();
      container.dispose();
      api.dispose();
    },
  );
  testWidgets(
    'server pets can be selected and deletion clears current context',
    (tester) async {
      final api = fixture.apiWith((_) async => fixture.ok({}));
      final repo = ScreenPets(api);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            consumerApiProvider.overrideWithValue(api),
            authProvider.overrideWith(SignedIn.new),
            petRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(home: PetsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('米粒'), findsOneWidget);
      await tester.tap(find.text('设为当前'));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(PetsScreen));
      final container = ProviderScope.containerOf(context);
      expect(container.read(currentPetProvider)?.id, 'pet');
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认删除'));
      await tester.pumpAndSettle();
      expect(container.read(currentPetProvider), isNull);
      expect(find.textContaining('添加第一只宠物'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );
  testWidgets('create form submits a pet and reloads owned list', (
    tester,
  ) async {
    final api = fixture.apiWith((_) async => fixture.ok({}));
    final repo = ScreenPets(api);
    repo.values = [];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          consumerApiProvider.overrideWithValue(api),
          authProvider.overrideWith(SignedIn.new),
          petRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: PetsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加宠物'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '小爪');
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('猫').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('小爪'), findsOneWidget);
    expect(find.text('年龄阶段：信息不足'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
