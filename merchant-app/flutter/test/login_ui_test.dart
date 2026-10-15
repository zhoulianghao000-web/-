import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawday_merchant/app.dart';
import 'package:pawday_merchant/merchant_repository.dart';
import 'package:pawday_merchant/session.dart';

import 'api_test.dart' as fixture;

void main() {
  for (final size in [const Size(360, 800), const Size(1024, 768)]) {
    testWidgets('merchant login is usable at $size and large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = fixture.api((r) => fixture.loginFixture(r));
      final session = MerchantSession(MerchantRepository(client));
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: LoginPage(session: session),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('商家账号'), findsOneWidget);
      expect(find.text('密码'), findsOneWidget);
      expect(find.textContaining('动态码'), findsNothing);
      expect(find.text('跳过'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('登录商家工作台'));
      await tester.tap(find.text('登录商家工作台'));
      await tester.pumpAndSettle();
      expect(find.text('请输入商家账号和密码。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
