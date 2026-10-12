import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/care_repository.dart';
import 'package:pawday_consumer/care_screen.dart';
import 'package:pawday_consumer/invoice_screen.dart';
import 'package:pawday_consumer/repositories.dart';
import 'package:pawday_consumer/reference_ui.dart';

import 'api_test.dart' as fixture;
import 'pet_test.dart' show SignedIn;

class PendingCare extends CareRepository {
  PendingCare(super.api);
  int saves = 0;
  PetFoodInput? input;
  final done = Completer<PetFoodPlan>();
  @override
  Future<PetFoodPlan> start(
    String pet,
    PetFoodInput value,
    int version,
    String key,
  ) {
    saves++;
    input = value;
    return done.future;
  }
}

void main() {
  Future<PendingCare> mount(
    WidgetTester t,
    Widget child, {
    double scale = 1,
  }) async {
    final client = fixture.apiWith((_) async => fixture.ok(null));
    addTearDown(client.dispose);
    final repo = PendingCare(client);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          consumerApiProvider.overrideWithValue(client),
          authProvider.overrideWith(SignedIn.new),
          careRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: PawdayDesign.theme,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: child),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    return repo;
  }

  testWidgets(
    'food form rejects blank name and zero daily amount without writing',
    (t) async {
      final repo = await mount(t, const FoodForm(petId: 'pet'));
      await t.tap(find.text('保存'));
      await t.pumpAndSettle();
      expect(find.text('请填写粮食名称'), findsOneWidget);
      expect(repo.saves, 0);
      final fields = find.byType(TextFormField);
      await t.enterText(fields.at(0), 'TEST 食粮');
      await t.enterText(fields.at(2), '0');
      await t.tap(find.text('保存'));
      await t.pumpAndSettle();
      expect(find.text('请输入 1–1000000 的整数'), findsOneWidget);
      expect(repo.saves, 0);
    },
  );
  testWidgets('pending food save disables duplicate submission', (t) async {
    final repo = await mount(t, const FoodForm(petId: 'pet'));
    await t.enterText(find.byType(TextFormField).first, 'TEST 食粮');
    await t.tap(find.text('保存'));
    await t.pump();
    expect(repo.saves, 1);
    expect(find.text('保存中…'), findsOneWidget);
    await t.tap(find.text('保存中…'), warnIfMissed: false);
    await t.pump();
    expect(repo.saves, 1);
    expect(repo.input!.daily_amount_g, 50);
  });
  testWidgets('food form fits narrow layout with large text', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await mount(t, const FoodForm(petId: 'pet'), scale: 1.6);
    expect(t.takeException(), isNull);
    await t.ensureVisible(find.text('保存'));
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'invoice validates email and never pretends to issue an invoice',
    (t) async {
      await mount(t, const InvoiceForm(orderId: 'order', subId: 'sub'));
      await t.tap(find.text('提交申请'));
      await t.pumpAndSettle();
      expect(find.text('请填写抬头'), findsOneWidget);
      expect(find.text('请填写有效邮箱'), findsOneWidget);
      expect(find.textContaining('不会开具真实税务发票'), findsOneWidget);
    },
  );
}
