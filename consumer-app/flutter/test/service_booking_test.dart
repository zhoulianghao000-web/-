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
}
