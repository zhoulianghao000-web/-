import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawday_consumer/main.dart';
import 'package:pawday_consumer/repositories.dart';
import 'package:pawday_consumer/router.dart';
import 'package:pawday_consumer/ai_screen.dart';

import '../test/api_test.dart' as fixtures;
import 'android_guest_test.dart' show GuestRepository;

void main() {
  testWidgets(
    'Android login header is high, has no duplicate close, and stays reachable with keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
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
      expect(find.byIcon(Icons.close), findsNothing);
      expect(tester.getRect(find.text('测试账号登录')).top, lessThan(140));
      expect(
        tester.getRect(find.byKey(const Key('skip-phone-login'))).top,
        lessThan(140),
      );
      expect(tester.getRect(find.byType(TextField).first).top, lessThan(400));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const Key('skip-phone-login'))).bottom,
        lessThan(140),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );
  testWidgets(
    'smart selection stays above tabs while scrolling and preserves AI login returnTo',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      await tester.tap(find.byKey(const Key('skip-phone-login')));
      await tester.pumpAndSettle();
      final entry = find.byKey(const Key('smart-selection-entry'));
      expect(find.text('智能选品'), findsOneWidget);
      expect(find.text('给每一天，加一点可爱'), findsNothing);
      final before = tester.getRect(entry);
      expect(
        before.bottom,
        lessThan(tester.getRect(find.byType(NavigationBar)).top),
      );
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -650),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(entry).top, closeTo(before.top, .1));
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PawdayApp)),
      );
      final router = container.read(routerProvider);
      expect(router.routeInformationProvider.value.uri.path, '/auth/login');
      expect(
        router.routeInformationProvider.value.uri.queryParameters['returnTo'],
        '/ai',
      );
      await container
          .read(authProvider.notifier)
          .login('+999000000019', '123456');
      router.go('/home');
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/ai');
      expect(find.byType(AiScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );
}
