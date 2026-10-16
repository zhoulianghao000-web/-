import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/reference_ui.dart';
import 'package:pawday_consumer/repositories.dart';
import 'package:pawday_consumer/service_booking_repository.dart';
import 'package:pawday_consumer/service_booking_screen.dart';

import 'api_test.dart' as fixture;
import 'pet_test.dart' as pet;

final service = {
  'id': 'service',
  'store_id': 'store',
  'title': 'TEST wash',
  'kind': 'GROOMING',
  'status': 'ACTIVE',
  'version': 0,
  'created_at': '2026-10-01T00:00:00Z',
  'simulated': true,
};
final slot = {
  'id': 'slot',
  'service_id': 'service',
  'starts_at': '2030-10-20T01:00:00Z',
  'ends_at': '2030-10-20T02:00:00Z',
  'capacity': 1,
  'remaining': 1,
  'created_at': '2026-10-01T00:00:00Z',
  'simulated': true,
};
final booking = {
  'id': 'booking',
  'slot_id': 'slot',
  'service_id': 'service',
  'store_id': 'store',
  'service_title': 'TEST wash',
  'policy': 'SIMULATION_NO_CHARGE_V1',
  'amount_fen': 0,
  'status': 'BOOKED',
  'version': 4,
  'created_at': '2026-10-01T00:00:00Z',
  'cancelled_at': null,
  'starts_at': '2030-10-20T01:00:00Z',
  'ends_at': '2030-10-20T02:00:00Z',
  'simulated': true,
};
http.Response page(Object data) => http.Response(
  jsonEncode({
    'data': data,
    'page': {'has_more': false, 'next_cursor': null},
    'meta': fixture.meta,
  }),
  200,
);

class SwitchIdentity extends pet.SignedIn {
  void clear() {
    state = const AuthState();
  }
}

void main() {
  testWidgets('paused services clear previously displayed availability', (
    t,
  ) async {
    var paused = false;
    final api = fixture.apiWith((r) async {
      if (r.url.path.endsWith('booking-services')) {
        return page(paused ? [] : [service]);
      }
      if (r.url.path.endsWith('slots')) return page([slot]);
      return page([]);
    });
    addTearDown(api.dispose);
    await api.accept(fixture.tokens);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          consumerApiProvider.overrideWithValue(api),
          authProvider.overrideWith(SwitchIdentity.new),
        ],
        child: MaterialApp(home: const ServiceBookingScreen(storeId: 'store')),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('确认模拟预约'), findsOneWidget);
    paused = true;
    await t.tap(find.text('刷新服务与预约'));
    await t.pumpAndSettle();
    expect(find.text('确认模拟预约'), findsNothing);
    expect(find.text('TEST wash'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  Future<ProviderContainer> mount(WidgetTester t, ConsumerApi api) async {
    late ProviderContainer container;
    await api.accept(fixture.tokens);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          consumerApiProvider.overrideWithValue(api),
          authProvider.overrideWith(SwitchIdentity.new),
          serviceBookingRepositoryProvider.overrideWithValue(
            ServiceBookingRepository(api),
          ),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              theme: PawdayDesign.theme,
              home: const ServiceBookingScreen(storeId: 'store'),
            );
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    return container;
  }

  testWidgets(
    'failed reservation retry retains the key and explicitly displays simulation',
    (t) async {
      final writes = <http.Request>[];
      final api = fixture.apiWith((r) async {
        if (r.method == 'POST') {
          writes.add(r);
          return fixture.fail(503, 'PERSISTENCE_UNAVAILABLE');
        }
        if (r.url.path.endsWith('booking-services')) return page([service]);
        if (r.url.path.endsWith('slots')) return page([slot]);
        return page([]);
      });
      addTearDown(api.dispose);
      await mount(t, api);
      expect(find.textContaining('仅模拟预约'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await t.ensureVisible(find.text('确认模拟预约'));
        await t.tap(find.text('确认模拟预约'));
        await t.pumpAndSettle();
      }
      expect(writes.length, 2);
      expect(
        writes.first.headers['Idempotency-Key'],
        writes.last.headers['Idempotency-Key'],
      );
      expect(jsonDecode(writes.first.body), {'slot_id': 'slot'});
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'cancellation uses current version and logout clears private bookings',
    (t) async {
      final writes = <http.Request>[];
      final api = fixture.apiWith((r) async {
        if (r.method == 'POST') {
          writes.add(r);
          return fixture.fail(409, 'CONCURRENT_MODIFICATION');
        }
        if (r.url.path.endsWith('booking-services')) return page([]);
        return page([booking]);
      });
      addTearDown(api.dispose);
      final container = await mount(t, api);
      await t.ensureVisible(find.text('取消模拟预约'));
      await t.tap(find.text('取消模拟预约'));
      await t.pumpAndSettle();
      expect(writes.single.headers['If-Match'], '"4"');
      expect(find.textContaining('刷新后'), findsOneWidget);
      (container.read(authProvider.notifier) as SwitchIdentity).clear();
      await t.pumpAndSettle();
      expect(find.textContaining('预约编号 booking'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'late service load after logout cannot restore old account data',
    (t) async {
      final delayed = Completer<http.Response>();
      final api = fixture.apiWith(
        (r) async =>
            r.url.path.endsWith('booking-services') ? delayed.future : page([]),
      );
      addTearDown(api.dispose);
      final container = await mount(t, api);
      (container.read(authProvider.notifier) as SwitchIdentity).clear();
      await t.pump();
      delayed.complete(page([service]));
      await t.pumpAndSettle();
      expect(find.text('TEST wash'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'credential is transient and logout discards a late credential response',
    (t) async {
      Completer<http.Response>? pending;
      final api = fixture.apiWith((r) async {
        if (r.url.path.endsWith('/credential')) {
          pending = Completer<http.Response>();
          return pending!.future;
        }
        if (r.url.path.endsWith('booking-services')) return page([]);
        return page([booking]);
      });
      addTearDown(api.dispose);
      final container = await mount(t, api);
      await t.ensureVisible(find.text('出示模拟到店凭证'));
      await t.tap(find.text('出示模拟到店凭证'));
      await t.pump();
      (container.read(authProvider.notifier) as SwitchIdentity).clear();
      await t.pump();
      pending!.complete(
        http.Response(
          jsonEncode({
            'data': {
              'booking_id': 'booking',
              'credential': 'a' * 64,
              'valid_from': '2030-10-20T00:30:00Z',
              'expires_at': '2030-10-20T02:00:00Z',
              'simulated': true,
            },
            'meta': fixture.meta,
          }),
          200,
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('a' * 64), findsNothing);
      expect(find.text('TEST wash'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'credential refresh clears secret and fulfillment history shows departure and exception reason',
    (t) async {
      var done = false;
      final api = fixture.apiWith((r) async {
        if (r.url.path.endsWith('/credential')) {
          return http.Response(
            jsonEncode({
              'data': {
                'booking_id': 'booking',
                'credential': 'b' * 64,
                'valid_from': '2030-10-20T00:30:00Z',
                'expires_at': '2030-10-20T02:00:00Z',
                'simulated': true,
              },
              'meta': fixture.meta,
            }),
            200,
          );
        }
        if (r.url.path.endsWith('/fulfillment')) {
          return page([
            {
              'id': 'event',
              'booking_id': 'booking',
              'version': 2,
              'status': 'EXCEPTION',
              'reason_code': 'CUSTOMER_DISPUTE',
              'occurred_at': '2030-10-20T01:30:00Z',
              'simulated': true,
            },
          ]);
        }
        if (r.url.path.endsWith('booking-services')) return page([]);
        return page([
          {...booking, 'status': done ? 'EXCEPTION' : 'BOOKED'},
        ]);
      });
      addTearDown(api.dispose);
      await mount(t, api);
      await t.ensureVisible(find.text('出示模拟到店凭证'));
      await t.tap(find.text('出示模拟到店凭证'));
      await t.pumpAndSettle();
      expect(find.textContaining('b' * 64), findsOneWidget);
      expect(find.bySemanticsLabel('模拟到店凭证 ${'b' * 64}'), findsOneWidget);
      done = true;
      await t.ensureVisible(find.text('刷新服务与预约'));
      await t.tap(find.text('刷新服务与预约'));
      await t.pumpAndSettle();
      expect(find.textContaining('b' * 64), findsNothing);
      expect(find.text('异常待人工处理'), findsOneWidget);
      expect(find.text('取消模拟预约'), findsNothing);
      await t.ensureVisible(find.text('查看履约记录'));
      await t.tap(find.text('查看履约记录'));
      await t.pumpAndSettle();
      expect(find.textContaining('消费者异议'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
}
