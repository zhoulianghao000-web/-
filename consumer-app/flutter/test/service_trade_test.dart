import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/repositories.dart';
import 'package:pawday_consumer/service_trade_screen.dart';

import 'api_test.dart' as fixture;
import 'pet_test.dart' as pet;
import 'service_booking_test.dart' as booking;

final shownTerms = <String, dynamic>{
  'id': 'terms',
  'store_id': 'store',
  'service_id': 'service',
  'service_title': 'TEST PAID SERVICE',
  'service_kind': 'GROOMING',
  'currency': 'CNY',
  'amount_fen': 101,
  'billing_unit': 'WHOLE_SLOT',
  'cancel_cutoff_minutes': 60,
  'consumer_late_cancel': 'MANUAL_REVIEW',
  'merchant_cancel': 'FULL_REFUND',
  'no_show': 'MANUAL_REVIEW',
  'version': 1,
  'terms_sha256': 'a' * 64,
  'simulated': true,
};
final quoted = <String, dynamic>{
  'id': 'quote',
  'store_id': 'store',
  'service_id': 'service',
  'slot_id': 'slot',
  'terms_id': 'terms',
  'terms_version': 1,
  'terms_sha256': 'a' * 64,
  'currency': 'CNY',
  'payable_fen': 101,
  'starts_at': booking.slot['starts_at'],
  'ends_at': booking.slot['ends_at'],
  'expires_at': '2030-10-20T00:30:00Z',
  'capacity_held': false,
  'simulated': true,
};
Map<String, dynamic> trade({String payment = 'PENDING', int version = 0}) => {
  'id': 'trade',
  'store_id': 'store',
  'service_id': 'service',
  'slot_id': 'slot',
  'terms_id': 'terms',
  'terms_sha256': 'a' * 64,
  'currency': 'CNY',
  'payable_fen': 101,
  'paid_fen': payment == 'SUCCEEDED' ? 101 : 0,
  'refunded_fen': 0,
  'refund_reserved_fen': 0,
  'commission_fen': null,
  'commission_reversed_fen': null,
  'merchant_net_fen': null,
  'order_state': payment == 'SUCCEEDED' ? 'CONFIRMED' : 'AWAITING_PAYMENT',
  'payment_state': payment,
  'capacity_state': payment == 'SUCCEEDED' ? 'CONFIRMED' : 'HELD',
  'fulfillment_state': 'NOT_STARTED',
  'settlement_state': payment == 'SUCCEEDED'
      ? 'WAITING_COMPLETION'
      : 'NOT_PAYABLE',
  'hold_expires_at': '2030-10-20T00:20:00Z',
  'starts_at': booking.slot['starts_at'],
  'receipt_id': payment == 'SUCCEEDED' ? 'receipt' : null,
  'confirmed_at': payment == 'SUCCEEDED' ? '2030-10-20T00:00:00Z' : null,
  'as_of': '2030-10-20T00:00:00Z',
  'settlement_buffer_ends_at': null,
  'open_dispute': false,
  'unresolved_collection_case': false,
  'version': version,
  'simulated': true,
};

class Identity extends pet.SignedIn {
  void clear() {
    state = const AuthState();
  }
}

Future<ProviderContainer> mount(
  WidgetTester t,
  ConsumerApi api, {
  String? service,
}) async {
  await api.accept(fixture.tokens);
  late ProviderContainer container;
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        consumerApiProvider.overrideWithValue(api),
        authProvider.overrideWith(Identity.new),
      ],
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return MaterialApp(home: ServiceTradeScreen(serviceId: service));
        },
      ),
    ),
  );
  await t.pumpAndSettle();
  return container;
}

Future<void> tap(WidgetTester t, String text) async {
  final finder = find.text(text);
  await t.ensureVisible(finder);
  await t.tap(finder);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'requires displayed terms consent and renders persisted order after reserve',
    (t) async {
      var reserved = false, reads = 0, submits = 0;
      final writes = <Map<String, dynamic>>[];
      final api = fixture.apiWith((r) async {
        final path = r.url.path;
        if (path.endsWith('/trade-terms')) return fixture.ok(shownTerms);
        if (path.endsWith('/slots')) return booking.page([booking.slot]);
        if (path.endsWith('/service-trade-quotes')) return fixture.ok(quoted);
        if (path.endsWith('/service-trade-orders') && r.method == 'POST') {
          submits++;
          writes.add(jsonDecode(r.body) as Map<String, dynamic>);
          reserved = true;
          return fixture.ok(trade(payment: 'SUCCEEDED'));
        }
        if (path.endsWith('/service-trade-orders')) {
          reads++;
          return booking.page(reserved ? [trade()] : []);
        }
        return fixture.fail(404, 'RESOURCE_NOT_FOUND');
      });
      addTearDown(api.dispose);
      await mount(t, api, service: 'service');
      await tap(t, '获取服务报价');
      final confirm = find.widgetWithText(FilledButton, '确认条款并预占名额');
      expect(t.widget<FilledButton>(confirm).onPressed, isNull);
      expect(submits, 0);
      await tap(t, '我已阅读并确认上方服务、价格及取消条款');
      await tap(t, '确认条款并预占名额');
      expect(submits, 1);
      expect(writes.single, {
        'quote_id': 'quote',
        'accepted_terms_sha256': 'a' * 64,
      });
      expect(reads, greaterThan(1));
      expect(find.textContaining('付款：待确认'), findsOneWidget);
      expect(find.textContaining('付款：已成功'), findsNothing);
      expect(find.textContaining('佣金'), findsNothing);
      expect(find.textContaining('商家净'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'double submit sends one payment and unknown result is never called successful',
    (t) async {
      var payment = 'PENDING', attempts = 0;
      final response = Completer<http.Response>();
      final bodies = <Map<String, dynamic>>[];
      final api = fixture.apiWith((r) async {
        if (r.url.path.endsWith('/payment-attempts')) {
          attempts++;
          bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          return response.future;
        }
        return booking.page([trade(payment: payment)]);
      });
      addTearDown(api.dispose);
      await mount(t, api);
      final button = find.text('发起模拟付款');
      await t.ensureVisible(button);
      await t.tap(button);
      await t.tap(button, warnIfMissed: false);
      await t.pump();
      expect(attempts, 1);
      expect(bodies.single, {
        'channel': 'SIMULATED_TEST',
        'client_platform': 'ANDROID',
      });
      payment = 'UNKNOWN';
      response.complete(
        fixture.ok({'ignored': 'command response is not payment evidence'}),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('付款：结果未知'), findsOneWidget);
      expect(find.textContaining('付款：已成功'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'unavailable terms clear old quote and availability while owned order remains readable',
    (t) async {
      var unavailable = false;
      final api = fixture.apiWith((r) async {
        if (r.url.path.endsWith('/trade-terms')) {
          return unavailable
              ? fixture.fail(404, 'SERVICE_TERMS_UNAVAILABLE')
              : fixture.ok(shownTerms);
        }
        if (r.url.path.endsWith('/slots')) return booking.page([booking.slot]);
        if (r.url.path.endsWith('/service-trade-quotes')) {
          return fixture.ok(quoted);
        }
        return booking.page([trade()]);
      });
      addTearDown(api.dispose);
      await mount(t, api, service: 'service');
      await tap(t, '获取服务报价');
      expect(find.text('确认条款并预占名额'), findsOneWidget);
      unavailable = true;
      await tap(t, '刷新服务交易');
      expect(find.text('确认条款并预占名额'), findsNothing);
      expect(find.text('获取服务报价'), findsNothing);
      expect(find.text('交易编号 trade'), findsOneWidget);
      expect(find.textContaining('暂时没有已审核'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'logout clears credentials and late quote cannot repopulate the next account',
    (t) async {
      final delayed = Completer<http.Response>();
      var quoteRequested = false;
      final api = fixture.apiWith((r) async {
        if (r.url.path.endsWith('/trade-terms')) return fixture.ok(shownTerms);
        if (r.url.path.endsWith('/slots')) return booking.page([booking.slot]);
        if (r.url.path.endsWith('/service-trade-quotes')) {
          quoteRequested = true;
          return delayed.future;
        }
        if (r.url.path.endsWith('/credential')) {
          return fixture.ok({
            'trade_id': 'trade',
            'credential': 'b' * 64,
            'valid_from': '2030-10-20T00:30:00Z',
            'expires_at': '2030-10-20T02:00:00Z',
            'simulated': true,
          });
        }
        return booking.page([trade(payment: 'SUCCEEDED')]);
      });
      addTearDown(api.dispose);
      final container = await mount(t, api, service: 'service');
      await tap(t, '查看到店凭证');
      expect(find.textContaining('到店凭证 ${'b' * 64}'), findsOneWidget);
      final getQuote = find.text('获取服务报价');
      await t.ensureVisible(getQuote);
      await t.tap(getQuote);
      await t.pump();
      expect(quoteRequested, isTrue);
      (container.read(authProvider.notifier) as Identity).clear();
      await t.pump();
      delayed.complete(fixture.ok(quoted));
      await t.pumpAndSettle();
      expect(find.textContaining('到店凭证 ${'b' * 64}'), findsNothing);
      expect(find.text('确认条款并预占名额'), findsNothing);
      expect(find.text('交易编号 trade'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
}
