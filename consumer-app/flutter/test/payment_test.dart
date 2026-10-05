import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/payment_repository.dart';
import 'package:pawday_consumer/payment_screen.dart';
import 'package:pawday_consumer/repositories.dart';

import 'checkout_test.dart' show client, envelope;
import 'navigation_test.dart' show GuestRepository;
import 'order_test.dart' show orderFixture;

Map<String, dynamic> payment() => {
  ...orderFixture()['payment'] as Map<String, dynamic>,
  'payment_no': 'TEST私有支付',
  'status': 'PROCESSING',
  'simulation': true,
  'successful_attempt_id': null,
  'successful_receipt_id': null,
  'paid_at': null,
  'final_channel': null,
  'cases': [],
  'attempts': [
    {
      'id': 'attempt',
      'payment_id': 'payment',
      'attempt_no': 'ATEST',
      'attempt_no_index': 1,
      'channel': 'WECHAT',
      'client_platform': 'ANDROID',
      'status': 'CHANNEL_PENDING',
      'version': 0,
      'created_at': '2026-10-05T00:00:00Z',
    },
  ],
};
Future<ProviderContainer> mountPayment(
  WidgetTester tester,
  ConsumerApi api,
) async {
  final container = ProviderContainer(
    overrides: [
      consumerApiProvider.overrideWithValue(api),
      consumerRepositoryProvider.overrideWithValue(GuestRepository(api)),
    ],
  );
  await container.read(authProvider.notifier).login('TEST', 'TEST');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: PaymentScreen(id: 'payment')),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

void main() {
  test(
    'attempt request sends channel and platform only with stable command key',
    () async {
      final requests = <http.Request>[];
      final api = client((r) async {
        requests.add(r);
        return envelope(payment());
      });
      await PaymentRepository(api)
          .attempt('payment', 'WECHAT', 'stable-payment-command');
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body.keys.toSet(), {'channel', 'client_platform'});
      expect(body['channel'], 'WECHAT');
      expect(
        requests.single.headers['Idempotency-Key'],
        'stable-payment-command',
      );
      api.dispose();
    },
  );
  testWidgets('logout discards a late private payment response', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final api = client((_) => response.future);
    final container = await mountPayment(tester, api);
    await container.read(authProvider.notifier).logout();
    response.complete(envelope(payment()));
    await tester.pumpAndSettle();
    expect(find.text('TEST私有支付'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    api.dispose();
  });
  testWidgets(
    'simulated success requires explicit confirmation before command',
    (tester) async {
      int writes = 0;
      final api = client((r) async {
        if (r.method == 'POST') writes++;
        return envelope(payment());
      });
      final container = await mountPayment(tester, api);
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, '模拟渠道成功');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(find.text('确认模拟渠道结果？'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '返回'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      api.dispose();
    },
  );
}
