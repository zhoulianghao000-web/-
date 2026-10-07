import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api/generated/dto.dart';
import 'membership_repository.dart';
import 'order_screen.dart';
import 'repositories.dart';

class MembershipScreen extends ConsumerStatefulWidget {
  const MembershipScreen({super.key});
  @override
  ConsumerState<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends ConsumerState<MembershipScreen> {
  List<MembershipPlan> plans = [];
  List<MembershipOrder> orders = [];
  MembershipStatus? current;
  String? error;
  bool busy = false;
  int generation = 0;
  final Map<String, String> keys = {};
  String? get owner => ref.read(authProvider).principal?.user_id;
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  String keyFor(String payload) =>
      keys.putIfAbsent(payload, () => DateTime.now().microsecondsSinceEpoch.toString() + owner.toString());

  Future<void> load() async {
    if (busy) return;
    final epoch = ++generation, user = owner;
    if (user == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    bool valid() => mounted && epoch == generation && owner == user;
    try {
      final repo = ref.read(membershipRepositoryProvider);
      final results = await Future.wait([repo.plans(), repo.current(), repo.orders()]);
      if (valid()) {
        setState(() {
          plans = results[0] as List<MembershipPlan>;
          current = results[1] as MembershipStatus;
          orders = results[2] as List<MembershipOrder>;
        });
      }
    } catch (e) {
      if (valid()) setState(() => error = '会员信息暂时不可用，请稍后重试。');
    } finally {
      if (valid()) setState(() => busy = false);
    }
  }

  Future<void> purchase(MembershipPlan plan) async {
    if (busy) return;
    final user = owner;
    if (user == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final created = await ref
          .read(membershipRepositoryProvider)
          .purchase(plan.code, keyFor('membership:${plan.code}'));
      final payment = created.payment_id;
      if (mounted && payment != null) {
        await context.push('/payments?id=$payment');
      }
    } catch (e) {
      if (mounted) setState(() => error = '下单失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
    await load();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (prev, next) {
      if (next.principal?.user_id != prev?.principal?.user_id) load();
    });
    final status = current?.effective_status ?? 'NONE';
    return Scaffold(
      appBar: AppBar(title: const Text('会员中心')),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
            Card(
              child: ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: Text(
                  status == 'ACTIVE'
                      ? '会员生效中'
                      : status == 'EXPIRED'
                      ? '会员已过期'
                      : '还不是会员',
                ),
                subtitle: Text(
                  status == 'ACTIVE' && current?.expires_at != null
                      ? '有效期至 ${current!.expires_at}'
                      : '开通会员可享会员价与 AI 问答额度。',
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('选择计划', style: TextStyle(fontSize: 18)),
            for (final plan in plans)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${plan.name} · ${orderMoney(plan.price_fen)}',
                        style: const TextStyle(fontSize: 17),
                      ),
                      const SizedBox(height: 4),
                      Text(plan.benefits.join('、')),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: busy ? null : () => purchase(plan),
                        child: Text(status == 'ACTIVE' ? '续费 ${plan.term == 'MONTH' ? '月度' : '年度'}会员' : '开通'),
                      ),
                    ],
                  ),
                ),
              ),
            if (orders.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('会员订单', style: TextStyle(fontSize: 18)),
              for (final order in orders)
                ListTile(
                  title: Text('${order.plan_snapshot.name} · ${orderMoney(order.amount_fen)}'),
                  subtitle: Text(order.created_at),
                  trailing: Text(
                    const {
                          'PENDING_PAYMENT': '待付款',
                          'PAID': '已支付',
                          'EXPIRED': '已过期',
                          'CANCELLED': '已取消',
                        }[order.status] ??
                        order.status,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
