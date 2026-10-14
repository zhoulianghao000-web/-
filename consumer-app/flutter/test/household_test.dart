import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/household_repository.dart';
import 'package:pawday_consumer/household_screen.dart';
import 'package:pawday_consumer/repositories.dart';
import 'package:pawday_consumer/reference_ui.dart';

import 'api_test.dart' as fixture;
import 'pet_test.dart' as pet;

HouseholdPet profile(String role) => HouseholdPet.fromJson({
  ...pet.petJson(id: '00000000-0000-4000-8000-000000000001'),
  'custom_breed_name': null,
  'share_role': role,
});
HouseholdOverview detail(String role) => HouseholdOverview(
  pet: profile(role),
  members: [],
  invites: [],
  tasks: [
    const HouseholdTask(
      id: 'task',
      title: 'TEST 喂食',
      due_on: '2026-10-14',
      status: 'OPEN',
      created_by: 'owner',
      completed_by: null,
      version: 7,
      created_at: '2026-10-14T00:00:00Z',
      ended_at: null,
    ),
  ],
  entries: [],
);

class HouseholdFixture extends HouseholdRepository {
  HouseholdFixture(super.api, {this.role = 'OWNER'});
  final String role;
  bool fail = false, revoked = false;
  int reads = 0, writes = 0;
  int? sentVersion;
  Completer<HouseholdOverview>? delayed;
  @override
  Future<List<HouseholdPet>> pets() async {
    reads++;
    if (fail) throw const ApiFailure(503, 'TEMPORARILY_UNAVAILABLE');
    return revoked ? [] : [profile(role)];
  }

  @override
  Future<HouseholdOverview> overview(String pet) async =>
      delayed == null ? detail(role) : await delayed!.future;
  @override
  Future<Map<String, dynamic>> command(
    String path,
    String key, {
    Map<String, dynamic>? body,
    int? version,
  }) async {
    writes++;
    sentVersion = version;
    revoked = true;
    throw const ApiFailure(404, 'RESOURCE_NOT_FOUND');
  }
}

class SwitchIdentity extends pet.SignedIn {
  void clear() {
    state = const AuthState();
  }
}

void main() {
  Future<ProviderContainer> mount(
    WidgetTester t,
    HouseholdFixture repo, {
    double scale = 1,
  }) async {
    late ProviderContainer container;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          consumerApiProvider.overrideWithValue(repo.api),
          authProvider.overrideWith(SwitchIdentity.new),
          householdRepositoryProvider.overrideWithValue(repo),
        ],
        child: Builder(
          builder: (ctx) {
            container = ProviderScope.containerOf(ctx);
            return MaterialApp(
              theme: PawdayDesign.theme,
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: const HouseholdScreen(),
              ),
            );
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    return container;
  }

  HouseholdFixture repo(String role) {
    final api = fixture.apiWith((_) async => fixture.ok(null));
    addTearDown(api.dispose);
    return HouseholdFixture(api, role: role);
  }

  testWidgets(
    'viewer sees shared care but no write or owner invitation controls',
    (t) async {
      await mount(t, repo('VIEWER'));
      expect(find.text('TEST 喂食'), findsOneWidget);
      expect(find.text('新增照顾任务'), findsNothing);
      expect(find.text('邀请成员'), findsNothing);
      expect(find.text('标记完成'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'narrow enlarged layout fits and does not disclose commerce or media controls',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await mount(t, repo('OWNER'), scale: 1.6);
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('新增照顾任务'));
      expect(t.takeException(), isNull);
      expect(find.text('编辑档案'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'failure retries and revoke clears current pet after an old task command',
    (t) async {
      final r = repo('CAREGIVER')..fail = true;
      await mount(t, r);
      expect(find.text('重试'), findsOneWidget);
      r.fail = false;
      await t.tap(find.text('重试'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('标记完成'));
      await t.tap(find.text('标记完成'));
      await t.pumpAndSettle();
      await t.tap(find.text('确认'));
      await t.pumpAndSettle();
      expect(r.sentVersion, 7);
      expect(r.writes, 1);
      expect(find.text('TEST 喂食'), findsNothing);
      expect(find.text('共享权限或宠物已不可用，请重新选择。'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('logout fences a late shared profile response', (t) async {
    final r = repo('VIEWER');
    final container = await mount(t, r);
    r.delayed = Completer<HouseholdOverview>();
    await t.tap(find.byTooltip('刷新家庭照顾'));
    await t.pump();
    (container.read(authProvider.notifier) as SwitchIdentity).clear();
    await t.pump();
    r.delayed!.complete(detail('VIEWER'));
    await t.pumpAndSettle();
    expect(find.text('TEST 喂食'), findsNothing);
    expect(find.text('家庭照顾当前宠物'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  test('household error copy distinguishes invitation expiry and conflict', () {
    expect(
      householdError(const ApiFailure(404, 'INVITE_UNAVAILABLE')),
      contains('过期'),
    );
    expect(
      householdError(const ApiFailure(409, 'CONCURRENT_MODIFICATION')),
      contains('刷新'),
    );
  });
}
