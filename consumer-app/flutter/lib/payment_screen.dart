import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api/generated/dto.dart';
import 'checkout_repository.dart';
import 'order_screen.dart';
import 'payment_repository.dart';
import 'repositories.dart';

String paymentStatus(String status) => switch (status) {
  'PENDING' => '待付款',
  'PROCESSING' => '支付结果确认中',
  'SUCCEEDED' => '已付款',
  'CLOSED' => '已关闭',
  _ => '支付结果未知',
};

class PaymentScreen extends ConsumerStatefulWidget {
  final String id;
  const PaymentScreen({super.key, required this.id});
  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  PaymentDetail? payment;
  String? error;
  String channel = 'WECHAT';
  bool busy = false;
  int generation = 0;
  final Map<String, String> keys = {};
  String? get owner => ref.read(authProvider).principal?.user_id;
  @override
  void initState() {
    super.initState();
    if (widget.id.isNotEmpty) {
      Future.microtask(() => run((repo) => repo.get(widget.id)));
    }
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<void> run(
    Future<PaymentDetail> Function(PaymentRepository) work,
  ) async {
    final user = owner;
    if (busy || user == null) return;
    final epoch = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    bool valid() => mounted && epoch == generation && owner == user;
    try {
      final value = await work(ref.read(paymentRepositoryProvider));
      if (valid()) setState(() => payment = value);
    } catch (e) {
      if (valid()) {
        setState(() => error = checkoutError(e));
      }
    } finally {
      if (valid()) setState(() => busy = false);
    }
  }

  Future<void> simulate(String outcome) async {
    final current = payment, user = owner;
    if (current == null ||
        busy ||
        !current.simulation ||
        current.attempts.isEmpty) {
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('确认模拟渠道结果？'),
        content: const Text('仅用于开发环境验收，不发生真实扣款。订单状态仍以后端查询和确认结果为准。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认模拟'),
          ),
        ],
      ),
    );
    if (accepted != true ||
        !mounted ||
        owner != user ||
        payment?.id != current.id) {
      return;
    }
    await run(
      (repo) => repo.simulate(widget.id, current.attempts.last.id, outcome),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (previous, next) {
      if (previous?.principal?.user_id != next.principal?.user_id) {
        generation++;
        setState(() {
          payment = null;
          error = null;
          busy = false;
          keys.clear();
        });
      }
    });
    ref.watch(authProvider);
    final current = payment;
    return Scaffold(
      appBar: AppBar(
        title: const Text('收银台'),
        leading: BackButton(onPressed: () => context.go('/orders')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (error != null) Text(error!, key: const Key('payment-error')),
          if (busy) const LinearProgressIndicator(),
          if (current == null && !busy) const Text('请从本人订单进入收银台'),
          if (current != null) ...[
            Text(current.payment_no),
            Text(paymentStatus(current.status)),
            Text(
              '应付 ${orderMoney(current.amount_fen)}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text('付款期限 ${DateTime.parse(current.expires_at).toLocal()}'),
            Text(current.simulation ? '开发环境模拟支付，不发生真实扣款' : '支付渠道尚未配置'),
            if (current.status == 'PENDING' ||
                current.status == 'PROCESSING') ...[
              DropdownButton<String>(
                value: channel,
                onChanged: busy
                    ? null
                    : (value) => setState(() => channel = value!),
                items: const [
                  DropdownMenuItem(value: 'WECHAT', child: Text('微信')),
                  DropdownMenuItem(value: 'ALIPAY', child: Text('支付宝')),
                ],
              ),
              FilledButton(
                onPressed: busy || !current.simulation
                    ? null
                    : () {
                        final identity =
                            '$channel:${current.attempts.isEmpty ? 'first' : current.attempts.last.id}';
                        final key = keys.putIfAbsent(
                          identity,
                          checkoutCommandKey,
                        );
                        run((repo) => repo.attempt(widget.id, channel, key));
                      },
                child: const Text('发起或安全切换支付'),
              ),
            ],
            if (current.status == 'PROCESSING') ...[
              const Text('结果未知时不能重新下单或释放预占。可查询结果，或请求安全关闭渠道尝试。'),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => run((repo) => repo.close(widget.id)),
                child: const Text('安全关闭支付尝试'),
              ),
              if (current.simulation) ...[
                FilledButton(
                  onPressed: busy ? null : () => simulate('SUCCEEDED'),
                  child: const Text('模拟渠道成功'),
                ),
                TextButton(
                  onPressed: busy ? null : () => simulate('FAILED'),
                  child: const Text('模拟渠道失败'),
                ),
                TextButton(
                  onPressed: busy ? null : () => simulate('UNKNOWN'),
                  child: const Text('模拟结果未知'),
                ),
              ],
            ],
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => run((repo) => repo.requery(widget.id)),
              child: const Text('查询并核对支付结果'),
            ),
            if (current.status == 'SUCCEEDED')
              Text(
                '后端已确认付款 · ${current.final_channel == 'WECHAT' ? '微信' : '支付宝'}',
              ),
            if (current.cases.isNotEmpty)
              const Text('发现异常收款，系统按原交易处理补偿，不恢复已关闭订单'),
            for (final value in current.cases)
              Text(
                value.status == 'REFUNDED'
                    ? '异常模拟款项已原路补偿'
                    : value.status == 'NEEDS_REVIEW'
                    ? '补偿等待管理员核查'
                    : '原路补偿处理中',
              ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => context.go('/orders?id=${current.order_id}'),
              child: const Text('返回订单'),
            ),
          ],
        ],
      ),
    );
  }
}
