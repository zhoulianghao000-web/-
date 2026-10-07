import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/generated/dto.dart';
import 'points_repository.dart';
import 'repositories.dart';

String pointsEntryLabel(String type) =>
    const {
      'PURCHASE_EARN': '购物得积分',
      'REVIEW_EARN': '评价奖励',
      'MEDIA_REVIEW_BONUS': '图文评价加奖',
      'CHECKIN_EARN': '每日签到',
      'REDEMPTION_SPEND': '积分兑换',
      'REFUND_CLAWBACK': '退款追回',
      'MANUAL_ADJUSTMENT': '人工调整',
    }[type] ??
    type;

class PointsScreen extends ConsumerStatefulWidget {
  const PointsScreen({super.key});
  @override
  ConsumerState<PointsScreen> createState() => _PointsScreenState();
}

class _PointsScreenState extends ConsumerState<PointsScreen> {
  PointsOverview? overview;
  List<PointsReward> rewards = [];
  List<PointsLedgerEntry> entries = [];
  String? error, notice;
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
      keys.putIfAbsent(payload, () => '${owner.hashCode}-${payload.hashCode}');

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
      final repo = ref.read(pointsRepositoryProvider);
      final results = await Future.wait([repo.overview(), repo.rewards(), repo.ledger()]);
      if (valid()) {
        setState(() {
          overview = results[0] as PointsOverview;
          rewards = results[1] as List<PointsReward>;
          entries = results[2] as List<PointsLedgerEntry>;
        });
      }
    } catch (e) {
      if (valid()) setState(() => error = '积分信息暂时不可用，请稍后重试。');
    } finally {
      if (valid()) setState(() => busy = false);
    }
  }

  Future<void> checkin() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final done = await ref.read(pointsRepositoryProvider).checkin(keyFor('checkin'));
      if (mounted) {
        setState(() => notice = '签到成功，连续第 ${done.cycle_day} 天，+${done.points} 分。');
      }
    } catch (e) {
      if (mounted) setState(() => error = '今天已经签到过了，明天再来吧。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
    await load();
  }

  Future<void> redeem(PointsReward reward) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await ref.read(pointsRepositoryProvider).redeem(reward.id, keyFor('redeem:${reward.code}'));
      if (mounted) setState(() => notice = '已兑换「${reward.name}」。');
    } catch (e) {
      if (mounted) setState(() => error = '积分不足，暂时无法兑换。');
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
    final current = overview;
    return Scaffold(
      appBar: AppBar(title: const Text('我的积分')),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            if (notice != null) Text(notice!, style: const TextStyle(color: Colors.green)),
            Card(
              child: ListTile(
                leading: const Icon(Icons.stars_outlined),
                title: Text('${current?.balance ?? 0} 分', style: const TextStyle(fontSize: 22)),
                subtitle: Text(
                  current == null
                      ? '购物、签到都能攒积分。'
                      : '每消费 1 元得 ${current.policy.earn_points_per_yuan} 分 · 连续签到第 ${current.current_cycle_day} 天',
                ),
                trailing: FilledButton(
                  onPressed: busy || (current?.checked_in_today ?? false) ? null : checkin,
                  child: Text(current?.checked_in_today ?? false ? '已签到' : '签到'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('积分兑换', style: TextStyle(fontSize: 18)),
            if (rewards.isEmpty) const Text('暂无奖励，先看看别处吧。'),
            for (final reward in rewards)
              Card(
                child: ListTile(
                  title: Text(reward.name),
                  subtitle: Text('${reward.cost_points} 积分'),
                  trailing: FilledButton.tonal(
                    onPressed: busy || (current?.balance ?? 0) < reward.cost_points
                        ? null
                        : () => redeem(reward),
                    child: const Text('兑换'),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Text('积分明细', style: TextStyle(fontSize: 18)),
            if (entries.isEmpty) const Text('暂无积分明细。'),
            for (final entry in entries)
              ListTile(
                dense: true,
                title: Text(pointsEntryLabel(entry.entry_type)),
                subtitle: Text(entry.reason ?? entry.created_at),
                trailing: Text(
                  entry.points > 0 ? '+${entry.points}' : '${entry.points}',
                  style: TextStyle(color: entry.points > 0 ? Colors.green : Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
