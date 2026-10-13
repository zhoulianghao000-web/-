import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/main.dart';
import 'package:pawday_consumer/pilot.dart';
import 'package:pawday_consumer/repositories.dart';
import 'package:pawday_consumer/router.dart';

import '../test/api_test.dart' as fixtures;

class GuestRepository extends ConsumerRepository {
  int loginCalls = 0, smsCalls = 0;
  Completer<void>? sms;
  GuestRepository(super.api);
  @override
  Future<Principal?> restore() async => null;
  @override
  Future<Principal> login(String phone, String code) async {
    loginCalls++;
    return fixtures.principal;
  }

  @override
  Future<void> requestCode(String phone) async {
    smsCalls++;
    await sms?.future;
  }
}

void main() {
  testWidgets(
    'Android skip opens guest home without SMS, tokens or private reads; protected routes still require login',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var reads = 0;
      final api = fixtures.apiWith((_) async {
        reads++;
        return fixtures.ok({});
      });
      final repository = GuestRepository(api);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            consumerApiProvider.overrideWithValue(api),
            consumerRepositoryProvider.overrideWithValue(repository),
          ],
          child: const PawdayApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(androidGuestSkipAvailable, isTrue);
      final skip = find.byKey(const Key('skip-phone-login'));
      final rect = tester.getRect(skip);
      expect(rect.width, greaterThanOrEqualTo(44));
      expect(rect.height, greaterThanOrEqualTo(44));
      expect(
        rect.center.dx,
        greaterThan(
          tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
        ),
      );
      await tester.tap(skip);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PawdayApp)),
      );
      final router = container.read(routerProvider);
      expect(router.routeInformationProvider.value.uri.path, '/home');
      expect(find.textContaining('每一天，认真照顾。'), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      expect(container.read(authProvider).principal, isNull);
      expect(container.read(authProvider).guestBrowsing, isTrue);
      expect(api.authenticated, isFalse);
      expect(repository.loginCalls, 0);
      expect(repository.smsCalls, 0);
      expect(reads, 0);
      for (final path in ['/categories', '/nearby', '/me']) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, path);
      }
      expect(reads, 0);
      for (final path in [
        '/pets',
        '/cart',
        '/orders',
        '/payments',
        '/sessions',
        '/purchase-requests',
        '/invoices',
        '/ai',
      ]) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/auth/login');
        expect(
          router.routeInformationProvider.value.uri.queryParameters['returnTo'],
          path,
        );
        await tester.tap(skip);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/home');
      }
      router.go('/pets');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '+999000000019');
      await tester.enterText(find.byType(TextField).last, '123456');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();
      expect(repository.loginCalls, 1);
      expect(container.read(authProvider).principal, fixtures.principal);
      expect(container.read(authProvider).guestBrowsing, isFalse);
      expect(router.routeInformationProvider.value.uri.path, '/pets');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );

  testWidgets('guest selection is memory only and a new app starts at login', (
    tester,
  ) async {
    final api = fixtures.apiWith((_) async => fixtures.ok({}));
    Widget app() => ProviderScope(
      overrides: [
        consumerApiProvider.overrideWithValue(api),
        consumerRepositoryProvider.overrideWithValue(GuestRepository(api)),
      ],
      child: const PawdayApp(),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skip-phone-login')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('手机号登录'), findsOneWidget);
    expect(find.byKey(const Key('skip-phone-login')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });

  testWidgets('iOS keeps its existing login boundary', (tester) async {
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
    expect(androidGuestSkipAvailable, isFalse);
    expect(find.byKey(const Key('skip-phone-login')), findsNothing);
    expect(find.text('手机号登录'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('skip is disabled while a login request is in flight', (
    tester,
  ) async {
    final api = fixtures.apiWith((_) async => fixtures.ok({}));
    final repository = GuestRepository(api)..sms = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          consumerApiProvider.overrideWithValue(api),
          consumerRepositoryProvider.overrideWithValue(repository),
        ],
        child: const PawdayApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '+999000000019');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(TextButton, '发送验证码'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '发送验证码'));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('skip-phone-login')))
          .onPressed,
      isNull,
    );
    repository.sms!.complete();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('skip-phone-login')))
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
