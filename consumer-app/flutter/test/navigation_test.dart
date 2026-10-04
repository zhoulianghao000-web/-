import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/main.dart';
import 'package:pawday_consumer/repositories.dart';
import 'package:pawday_consumer/router.dart';

import 'api_test.dart' as fixtures;

class GuestRepository extends ConsumerRepository {
  GuestRepository(super.api);
  @override
  Future<Principal?> restore() async => null;
  @override
  Future<Principal> login(String phone, String code) async =>
      fixtures.principal;
  @override
  Future<void> logout() async {}
  @override
  Future<void> requestCode(String phone) async {}
}

void main() {
  testWidgets('five tabs render and protected pet tab returns to login', (
    tester,
  ) async {
    final api = fixtures.apiWith((_) async => fixtures.ok({}));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          consumerApiProvider.overrideWithValue(api),
          consumerRepositoryProvider.overrideWithValue(GuestRepository(api)),
        ],
        child: const PawdayApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('每一天，认真照顾。'), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, '分类'));
    await tester.pumpAndSettle();
    expect(find.text('发现适合它的好物'), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, '附近'));
    await tester.pumpAndSettle();
    expect(find.text('发现身边的友好'), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, '我的'));
    await tester.pumpAndSettle();
    expect(find.text('欢迎来到爪日'), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, '宠物'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    final context = tester.element(find.byType(PawdayApp));
    final container = ProviderScope.containerOf(context);
    expect(
      container
          .read(routerProvider)
          .routeInformationProvider
          .value
          .uri
          .queryParameters['returnTo'],
      '/pets',
    );
    await tester.enterText(find.byType(TextField).first, '13800000000');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(find.text('我的宠物'), findsOneWidget);
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/pets',
    );
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  test('current pet rejects foreign ownership and clears on logout', () async {
    final api = fixtures.apiWith((_) async => fixtures.ok({}));
    final container = ProviderContainer(
      overrides: [
        consumerApiProvider.overrideWithValue(api),
        consumerRepositoryProvider.overrideWithValue(GuestRepository(api)),
      ],
    );
    final subscription = container.listen(currentPetProvider, (_, _) {});
    await container.read(authProvider.notifier).login('phone', 'code');
    const owned = PetContext(id: 'pet', ownerUserId: 'user', name: '米粒');
    const foreign = PetContext(
      id: 'other',
      ownerUserId: 'foreign',
      name: '陌生宠物',
    );
    expect(
      () => container.read(currentPetProvider.notifier).select(foreign, [
        foreign,
      ]),
      throwsA(isA<ApiFailure>()),
    );
    container.read(currentPetProvider.notifier).select(owned, [owned]);
    expect(container.read(currentPetProvider)?.id, 'pet');
    await container.read(authProvider.notifier).logout();
    expect(container.read(currentPetProvider), isNull);
    subscription.close();
    container.dispose();
    api.dispose();
  });
}
