import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api/generated/dto.dart';
import 'checkout_repository.dart';
import 'order_repository.dart';
import 'repositories.dart';

String orderMoney(int fen) => '¥${(fen / 100).toStringAsFixed(2)}';

class OrdersScreen extends ConsumerStatefulWidget {
  final String? initialId;
  const OrdersScreen({super.key, this.initialId});
  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  final List<OrderSummary> rows = [];
  Order? detail;
  String? cursor, error;
  bool busy = false;
  int generation = 0;
  final Map<String, String> keys = {};
  String? get owner => ref.read(authProvider).principal?.user_id;
  @override
  void initState() {
    super.initState();
    Future.microtask(() => load(id: widget.initialId));
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<void> load({String? id, bool more = false}) async {
    if (busy) return;
    final epoch = ++generation, user = owner;
    if (user == null) return;
    setState(() {
      busy = true;
      error = null;
      if (!more && id == null) {
        rows.clear();
        detail = null;
      }
    });
    bool valid() => mounted && epoch == generation && owner == user;
    try {
      final repo = ref.read(orderRepositoryProvider);
      if (id != null) {
        final value = await repo.get(id);
        if (valid()) setState(() => detail = value);
      } else {
        final page = await repo.list(cursor: more ? cursor : null);
        if (valid()) {
          setState(() {
            rows.addAll(page.data);
            cursor = page.page.next_cursor;
          });
        }
      }
    } catch (e) {
      if (valid()) setState(() => error = checkoutError(e));
    } finally {
      if (valid()) setState(() => busy = false);
    }
  }

  Future<void> cancel() async {
    final order = detail, user = owner;
    if (order == null || busy || user == null) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('取消整单？'),
        content: const Text('此订单尚未付款。取消会释放全部商家的预占库存和优惠券，不能只取消其中一部分。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('保留订单'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认取消'),
          ),
        ],
      ),
    );
    if (accepted != true ||
        !mounted ||
        owner != user ||
        detail?.id != order.id) {
      return;
    }
    final epoch = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    bool valid() => mounted && epoch == generation && owner == user;
    try {
      final value = await ref
          .read(orderRepositoryProvider)
          .cancel(
            order,
            keys.putIfAbsent(
              '${order.id}:${order.version}',
              checkoutCommandKey,
            ),
          );
      if (valid()) setState(() => detail = value);
    } catch (e) {
      if (valid()) setState(() => error = checkoutError(e));
    } finally {
      if (valid()) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (previous, next) {
      if (previous?.principal?.user_id != next.principal?.user_id) {
        generation++;
        if (mounted) {
          setState(() {
            rows.clear();
            detail = null;
            cursor = null;
            keys.clear();
            error = null;
            busy = false;
          });
        }
      }
    });
    final order = detail;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的订单'),
        leading: BackButton(onPressed: () => context.go('/me')),
        actions: [
          IconButton(
            onPressed: busy ? null : () => load(id: detail?.id),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新订单',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!, key: const Key('order-error')),
          if (order == null) ...[
            if (!busy && rows.isEmpty) const Text('暂时没有订单'),
            for (final row in rows)
              ListTile(
                title: Text(row.order_no),
                subtitle: Text(
                  row.status == 'FULFILLING'
                      ? '已付款待履约'
                      : row.status == 'PAYMENT_PROCESSING'
                      ? '支付确认中'
                      : row.status == 'PENDING_PAYMENT'
                      ? '待付款'
                      : '已取消',
                ),
                trailing: Text(orderMoney(row.payable_amount_fen)),
                onTap: busy ? null : () => load(id: row.id),
              ),
            if (cursor != null)
              TextButton(
                onPressed: busy ? null : () => load(more: true),
                child: const Text('加载更多'),
              ),
          ] else ...[
            TextButton(
              onPressed: busy ? null : () => load(),
              child: const Text('返回订单列表'),
            ),
            Text(order.order_no),
            Text(
              order.status == 'FULFILLING'
                  ? '已付款待履约'
                  : order.status == 'PAYMENT_PROCESSING'
                  ? '支付确认中'
                  : order.status == 'PENDING_PAYMENT'
                  ? '待付款'
                  : '已取消',
            ),
            Text(
              '应付 ${orderMoney(order.payable_amount_fen)}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              '付款期限 ${DateTime.parse(order.reservation_expires_at).toLocal()}',
            ),
            const Text('当前接通开发环境模拟支付，不发生真实扣款。'),
            if (order.status == 'PENDING_PAYMENT' ||
                order.status == 'PAYMENT_PROCESSING')
              FilledButton(
                onPressed: busy
                    ? null
                    : () => context.go('/payments?id=${order.payment.id}'),
                child: const Text('进入收银台'),
              ),
            for (final sub in order.suborders)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sub.merchant_name),
                      for (final item in sub.items)
                        Text(
                          '${item.product_snapshot.name} × ${item.quantity} · ${orderMoney(item.payable_amount_fen)}',
                        ),
                      Text('商品及运费 ${orderMoney(sub.payable_amount_fen)}'),
                    ],
                  ),
                ),
              ),
            if (order.status == 'PENDING_PAYMENT')
              OutlinedButton(
                onPressed: busy ? null : cancel,
                child: const Text('取消未付款整单'),
              ),
            if (order.cancellation != null)
              Text(
                order.cancellation!.reason_code == 'PAYMENT_WINDOW_EXPIRED'
                    ? '付款超时，库存与优惠券预占已释放'
                    : '订单已取消，库存与优惠券预占已释放',
              ),
          ],
        ],
      ),
    );
  }
}
