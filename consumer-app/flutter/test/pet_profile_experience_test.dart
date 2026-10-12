import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/pet_repository.dart';
import 'package:pawday_consumer/pet_profile_ui.dart';
import 'package:pawday_consumer/pet_screen.dart';
import 'package:pawday_consumer/nearby_screen.dart';
import 'package:pawday_consumer/reference_ui.dart';
import 'package:pawday_consumer/repositories.dart';

import 'api_test.dart' as api;
import 'pet_test.dart' as fixture;

void main() {
  test(
    'birthday normalizes pasted human dates, rejects overflow and future dates',
    () {
      final now = DateTime(2026, 10, 12);
      for (final s in ['2026 01 02', '2026/1/2', '2026年1月2日', '2026-01-02']) {
        expect(normalizePetBirthday(s, today: now), '2026-01-02');
      }
      for (final s in [
        '2026-02-29',
        '2026-13-02',
        '2026-10-13',
        '01-02-2026',
        '',
        '1899-01-01',
      ]) {
        expect(normalizePetBirthday(s, today: now), isNull);
      }
      expect(normalizePetBirthday('2024-02-29', today: now), '2024-02-29');
    },
  );
  test(
    'age uses completed calendar months, distinguishes estimate and unknown',
    () {
      Pet pet(Map<String, dynamic> values) =>
          Pet.fromJson({...fixture.petJson(), ...values});
      final now = DateTime(2026, 10, 12);
      expect(
        petAgeLabel(pet({'birth_date': '2025-10-13'}), today: now),
        '11 个月',
      );
      expect(petAgeLabel(pet({'birth_date': '2025-10-12'}), today: now), '1 岁');
      expect(
        petAgeLabel(pet({'birth_date': '2026-10-01'}), today: now),
        '未满 1 个月',
      );
      expect(
        petAgeLabel(pet({'age_estimate_months': 15}), today: now),
        '约 1 岁 3 个月',
      );
      expect(petAgeLabel(pet({}), today: now), '年龄待补充');
    },
  );
  Future<fixture.ScreenPets> form(
    WidgetTester t, {
    Pet? pet,
    double scale = 1,
  }) async {
    final client = api.apiWith((_) async => api.ok({}));
    addTearDown(client.dispose);
    final repo = fixture.ScreenPets(client);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          consumerApiProvider.overrideWithValue(client),
          authProvider.overrideWith(fixture.SignedIn.new),
          petRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: PawdayDesign.theme,
          home: MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(scale),
              size: t.view.physicalSize,
            ),
            child: Scaffold(body: PetForm(existing: pet)),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    return repo;
  }

  Future<void> select(WidgetTester t, String label, String option) async {
    final f = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.decoration.labelText == label,
    );
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pumpAndSettle();
    await t.tap(find.text(option).last);
    await t.pumpAndSettle();
  }

  testWidgets('birthday paste submits ISO and clears an earlier age estimate', (
    t,
  ) async {
    final repo = await form(
      t,
      pet: Pet.fromJson({...fixture.petJson(), 'age_estimate_months': 15}),
    );
    await select(t, '年龄记录方式', '已知生日');
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == '生日',
    );
    await t.ensureVisible(field);
    await t.enterText(field, '2026 01 02');
    await t.tap(find.text('保存'));
    await t.pumpAndSettle();
    expect(repo.savedBody?['birth_date'], '2026-01-02');
    expect(repo.savedBody?['age_estimate_months'], isNull);
  });
  testWidgets('invalid birthday is stopped before any API mutation', (t) async {
    final repo = await form(t, pet: Pet.fromJson(fixture.petJson()));
    await select(t, '年龄记录方式', '已知生日');
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == '生日',
    );
    await t.ensureVisible(field);
    await t.enterText(field, '2026-02-31');
    await t.tap(find.text('保存'));
    await t.pumpAndSettle();
    expect(repo.savedBody, isNull);
    expect(find.textContaining('请选择有效生日'), findsOneWidget);
  });
  testWidgets(
    'searchable breed suggestions save owner labels, not invented taxonomy IDs',
    (t) async {
      final repo = await form(t, pet: Pet.fromJson(fixture.petJson()));
      await t.tap(find.text('搜索、选择或自行填写'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '搜索或填写名称',
        ),
        '布偶',
      );
      await t.pumpAndSettle();
      await t.tap(find.text('布偶猫'));
      await t.pumpAndSettle();
      await t.tap(find.text('保存'));
      await t.pumpAndSettle();
      expect(repo.savedBody?['custom_breed_name'], '布偶猫');
      expect(repo.savedBody?['breed_id'], isNull);
    },
  );
  testWidgets('small screen form has no overflow with enlarged text', (
    t,
  ) async {
    t.view.physicalSize = const Size(360, 780);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await form(t, pet: Pet.fromJson(fixture.petJson()), scale: 1.3);
    await select(t, '年龄记录方式', '估算年龄');
    await t.ensureVisible(find.text('03 · 过敏与忌口'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('保存'), findsOneWidget);
  });
  testWidgets(
    'nearby content is capped on large desktops and requests no location on entry',
    (t) async {
      t.view.physicalSize = const Size(1920, 1080);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final client = api.apiWith(
        (_) async => throw StateError('Entry must not query'),
      );
      addTearDown(client.dispose);
      await t.pumpWidget(
        ProviderScope(
          overrides: [consumerApiProvider.overrideWithValue(client)],
          child: MaterialApp(
            theme: PawdayDesign.theme,
            home: const NearbyScreen(),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.getSize(find.byType(TextField)).width, lessThan(700));
      expect(t.getTopLeft(find.byType(TextField)).dx, greaterThan(300));
      expect(find.text('先选择城市，开启附近探索'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
