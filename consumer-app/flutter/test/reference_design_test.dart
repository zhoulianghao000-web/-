import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawday_consumer/repositories.dart';
import 'package:pawday_consumer/home_screen.dart';
import 'package:pawday_consumer/reference_ui.dart';

import 'api_test.dart' as fixtures;

void main() {
  testWidgets('hover button remains a single accessible native action', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: PawdayDesign.theme,
        home: Center(
          child: PawdayButton(
            onPressed: () => calls++,
            child: const Text('继续'),
          ),
        ),
      ),
    );
    final button = find.widgetWithText(FilledButton, '继续');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(button));
    await tester.pumpAndSettle();
    final movement = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).first,
    );
    expect(movement.transform!.storage[13], -2);
    await tester.tap(button);
    expect(calls, 1);
    await mouse.removePointer();
  });
  testWidgets(
    'disabled and reduced-motion buttons do not move or become enabled',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const Center(
              child: PawdayButton(onPressed: null, child: Text('不可提交')),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(FilledButton)));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<AnimatedContainer>(find.byType(AnimatedContainer).first)
            .transform!
            .storage[13],
        0,
      );
      await mouse.removePointer();
    },
  );
  testWidgets('plus turns on hover and opens explicit offer selection once', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ReferencePlus(label: '查看报价', onPressed: () => calls++),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(IconButton)));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
      .25,
    );
    await tester.tap(find.byTooltip('查看报价'));
    expect(calls, 1);
    await mouse.removePointer();
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'home at width $width keeps photos and honest empty catalog without overflow',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = fixtures.apiWith(
          (_) async => http.Response(
            jsonEncode({
              'data': [],
              'meta': fixtures.meta,
              'page': {'next_cursor': null, 'has_more': false},
            }),
            200,
            headers: {'Content-Type': 'application/json'},
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [consumerApiProvider.overrideWithValue(api)],
            child: MaterialApp(
              theme: PawdayDesign.theme,
              home: const HomeScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ReferenceProductCard), findsNothing);
        expect(find.byType(Image), findsAtLeastNWidgets(7));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        api.dispose();
      },
    );
  }
}
