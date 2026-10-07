import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:pawday_consumer/membership_repository.dart';
import 'package:pawday_consumer/membership_screen.dart';
import 'package:pawday_consumer/points_repository.dart';
import 'package:pawday_consumer/points_screen.dart';
import 'package:pawday_consumer/repositories.dart';

import 'checkout_test.dart' show client, envelope;
import 'navigation_test.dart' show GuestRepository;

const now = '2026-10-07T00:00:00Z';
final plan = {
  'id': 'plan',
  'code': 'MEMBER_MONTH',
  'name': '月度会员',
  'term': 'MONTH',
  'price_fen': 1500,
  'ai_quota': 20,
  'benefits': ['会员价'],
  'status': 'ACTIVE',
  'plan_version': 1,
  'created_by': null,
  'created_at': now,
};
Map<String, dynamic> membershipPayment() => {
  'id': 'mpay',
  'payment_no': 'Pmpay',
  'order_id': null,
  'membership_order_id': 'morder',
  'amount_fen': 1500,
  'currency': 'CNY',
  'status': 'PENDING',
  'expires_at': '2026-10-07T00:15:00Z',
  'version': 0,
  'created_at': now,
  'successful_attempt_id': null,
  'successful_receipt_id': null,
  'paid_at': null,
};
Map<String, dynamic> membershipOrder({String status = 'PENDING_PAYMENT'}) => {
  'id': 'morder',
  'order_no': 'Mmorder',
  'user_id': 'user',
  'plan_id': 'plan',
  'plan_snapshot': {
    'plan_id': 'plan',
    'code': 'MEMBER_MONTH',
    'name': '月度会员',
    'term': 'MONTH',
    'price_fen': 1500,
    'ai_quota': 20,
    'plan_version': 1,
    'benefits': ['会员价'],
  },
  'amount_fen': 1500,
  'status': status,
  'payment_id': 'mpay',
  'version': 0,
  'created_at': now,
  'paid_at': null,
  'payment': membershipPayment(),
};
final policy = {
  'id': 'policy',
  'earn_points_per_yuan': 1,
  'checkin_points': 5,
  'checkin_cycle_days': 30,
  'policy_version': 1,
  'created_by': null,
  'created_at': now,
};
final reward = {
  'id': 'reward',
  'code': 'TREAT',
  'name': '零食券',
  'cost_points': 50,
  'status': 'ACTIVE',
  'reward_version': 1,
  'created_by': null,
  'created_at': now,
};
Map<String, dynamic> overview({int balance = 30, bool checked = false}) => {
  'balance': balance,
  'checked_in_today': checked,
  'current_cycle_day': 2,
  'policy': policy,
};
final ledgerEntry = {
  'id': 'entry',
  'user_id': 'user',
  'entry_type': 'CHECKIN_EARN',
  'points': 5,
  'business_key': 'CHECKIN:user:2026-10-07',
  'order_id': null,
  'refund_id': null,
  'redemption_id': null,
  'policy_version': 1,
  'reason': '连续签到第 2 天',
  'created_by_type': 'SYSTEM',
  'created_by': null,
  'created_at': now,
};
final checkin = {
  'id': 'checkin',
  'user_id': 'user',
  'checkin_date': '2026-10-07',
  'cycle_day': 3,
  'points': 5,
  'created_at': now,
};

void main() {
  test('membership purchase posts plan code with a stable idempotency key', () async {
    final calls = <http.Request>[];
    final api = client((r) async {
      calls.add(r);
      return envelope(membershipOrder());
    });
    final repo = MembershipRepository(api);
    final created = await repo.purchase('MEMBER_MONTH', 'stable-membership-key');
    expect(created.payment_id, 'mpay');
    expect(calls.single.headers['Idempotency-Key'], 'stable-membership-key');
    expect(jsonDecode(calls.single.body), {'plan_code': 'MEMBER_MONTH'});
  });

  test('points overview and ledger parse from envelopes', () async {
    final api = client((r) async {
      if (r.url.path.endsWith('/consumer/points')) return envelope(overview());
      if (r.url.path.endsWith('/ledger')) return envelope([ledgerEntry]);
      if (r.url.path.endsWith('/rewards')) return envelope([reward]);
      return envelope([]);
    });
    final repo = PointsRepository(api);
    expect((await repo.overview()).balance, 30);
    expect((await repo.ledger()).single.entry_type, 'CHECKIN_EARN');
    expect((await repo.rewards()).single.cost_points, 50);
  });

  testWidgets('membership screen lists plans and purchase jumps to the shared payment', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final api = client((r) async {
      calls.add(r);
      final path = r.url.path;
      if (path.endsWith('/membership/plans')) return envelope([plan]);
      if (path.endsWith('/membership/orders') && r.method == 'POST') return envelope(membershipOrder());
      if (path.endsWith('/membership/orders')) return envelope([]);
      if (path.endsWith('/membership')) return envelope({'effective_status': 'NONE'});
      return envelope({});
    });
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const MembershipScreen()),
        GoRoute(
          path: '/payments',
          builder: (_, state) =>
              Scaffold(body: Text('pay ${state.uri.queryParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          consumerApiProvider.overrideWithValue(api),
          consumerRepositoryProvider.overrideWithValue(GuestRepository(api)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(MembershipScreen)));
    await container.read(authProvider.notifier).login('TEST', 'TEST');
    await tester.pumpAndSettle();
    expect(find.textContaining('月度会员'), findsWidgets);
    expect(find.text('还不是会员'), findsOneWidget);
    await tester.tap(find.text('开通').first);
    await tester.pumpAndSettle();
    expect(find.text('pay mpay'), findsOneWidget);
    final posted = calls.where((r) => r.method == 'POST' && r.url.path.endsWith('/membership/orders'));
    expect(posted.single.headers['Idempotency-Key'], isNotEmpty);
  });

  testWidgets('points screen checks in once and disables unaffordable rewards', (
    tester,
  ) async {
    var checked = false;
    final calls = <http.Request>[];
    final api = client((r) async {
      calls.add(r);
      final path = r.url.path;
      if (path.endsWith('/consumer/points')) return envelope(overview(balance: 30, checked: checked));
      if (path.endsWith('/rewards')) return envelope([reward]);
      if (path.endsWith('/ledger')) return envelope([ledgerEntry]);
      if (path.endsWith('/checkins') && r.method == 'POST') {
        checked = true;
        return envelope(checkin);
      }
      if (path.endsWith('/checkins')) return envelope([checkin]);
      return envelope({});
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          consumerApiProvider.overrideWithValue(api),
          consumerRepositoryProvider.overrideWithValue(GuestRepository(api)),
        ],
        child: const MaterialApp(home: PointsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(PointsScreen)));
    await container.read(authProvider.notifier).login('TEST', 'TEST');
    await tester.pumpAndSettle();
    expect(find.text('30 分'), findsOneWidget);
    expect(find.text('每日签到'), findsOneWidget);
    final redeemButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '兑换'));
    expect(redeemButton.onPressed, isNull, reason: 'balance 30 cannot afford a 50 point reward');
    await tester.tap(find.text('签到'));
    await tester.pumpAndSettle();
    expect(find.textContaining('连续第 3 天'), findsOneWidget);
    expect(find.text('已签到'), findsOneWidget);
    final posted = calls.where((r) => r.method == 'POST' && r.url.path.endsWith('/checkins'));
    expect(posted.single.headers['Idempotency-Key'], isNotEmpty);
  });
}
