import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'aftersale_repository.dart';
import 'api/generated/dto.dart';
import 'checkout_repository.dart';
import 'order_repository.dart';
import 'order_screen.dart' show orderMoney;
import 'repositories.dart';

String afterSaleStatusLabel(String status) =>
    const {
      'PENDING_MERCHANT': '待商家处理',
      'WAITING_RETURN': '待退货',
      'RETURN_IN_TRANSIT': '退货运输中',
      'WAITING_INSPECTION': '商家验收中',
      'REFUND_PENDING': '退款处理中',
      'PLATFORM_ESCALATED': '平台处理中',
      'COMPLETED': '已完成',
      'REJECTED': '已拒绝',
      'CANCELLED': '已撤销',
    }[status] ??
    '状态未知';
String afterSaleTypeLabel(String type) =>
    const {'REFUND_ONLY': '仅退款', 'RETURN_REFUND': '退货退款'}[type] ?? type;
String afterSaleReasonLabel(String code) =>
    const {
      'QUALITY_ISSUE': '质量问题',
      'WRONG_ITEM': '发错商品',
      'DAMAGED': '商品破损',
      'NOT_RECEIVED': '未收到货',
      'CONSUMER_REGRET': '不想要了',
      'OTHER': '其他原因',
    }[code] ??
    code;
String cancellationStatusLabel(String status) =>
    const {
      'ACCEPTED': '已受理',
      'REFUND_PENDING': '退款处理中',
      'COMPLETED': '已取消并退款',
    }[status] ??
    status;

class AfterSaleCard extends ConsumerStatefulWidget {
  final String suborderId;
  final VoidCallback onChanged;
  const AfterSaleCard({
    super.key,
    required this.suborderId,
    required this.onChanged,
  });
  @override
  ConsumerState<AfterSaleCard> createState() => _AfterSaleCardState();
}

class _AfterSaleCardState extends ConsumerState<AfterSaleCard> {
  Fulfillment? fulfillment;
  List<Cancellation> cancellations = const [];
  List<AfterSale> aftersales = const [];
  String? error;
  bool busy = false;
  int epoch = 0;
  final Map<String, String> keys = {};
  String? get owner => ref.read(authProvider).principal?.user_id;
  final List<TextEditingController> retired = [];
  void disposeLater(TextEditingController c) {
    // Dialog exit animations still read the controller after pop.
    retired.add(c);
  }
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void didUpdateWidget(AfterSaleCard old) {
    super.didUpdateWidget(old);
    if (old.suborderId != widget.suborderId) {
      epoch++;
      fulfillment = null;
      cancellations = const [];
      aftersales = const [];
      keys.clear();
      busy = false;
      Future.microtask(load);
    }
  }

  @override
  void dispose() {
    epoch++;
    for (final c in retired) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    if (busy || owner == null) return;
    final step = ++epoch, user = owner;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      Fulfillment? f;
      try {
        f = await ref
            .read(orderRepositoryProvider)
            .fulfillment(widget.suborderId);
      } catch (_) {
        f = null;
      }
      final repo = ref.read(afterSaleRepositoryProvider);
      final c = await repo.cancellations(widget.suborderId);
      final a = await repo.aftersales(widget.suborderId);
      if (mounted && step == epoch && owner == user) {
        setState(() {
          fulfillment = f;
          cancellations = c.data;
          aftersales = a.data;
        });
      }
    } catch (e) {
      if (mounted && step == epoch && owner == user) {
        setState(() => error = checkoutError(e));
      }
    } finally {
      if (mounted && step == epoch && owner == user) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> run(Future<void> Function() action) async {
    final step = ++epoch, user = owner;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted && step == epoch && owner == user) widget.onChanged();
      await load();
    } catch (e) {
      if (mounted && step == epoch && owner == user) {
        setState(() {
          busy = false;
          error = checkoutError(e);
        });
      }
    }
  }

  int cancellable(FulfillmentItem item) =>
      item.quantity - item.cancelled_qty - item.shipped_qty;

  Future<void> cancelPaid(FulfillmentItem item) async {
    final user = owner, limit = cancellable(item);
    if (user == null || busy || limit <= 0) return;
    final controller = TextEditingController(text: '$limit');
    final accepted = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('取消未发货商品？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('最多可取消 $limit 件，取消部分按实付金额原路退款，不返还优惠券。'),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '取消数量'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('再想想'),
          ),
          FilledButton(
            onPressed: () {
              final qty = int.tryParse(controller.text);
              if (qty == null || qty < 1 || qty > limit) return;
              Navigator.pop(c, qty);
            },
            child: const Text('确认取消'),
          ),
        ],
      ),
    );
    disposeLater(controller);
    if (accepted == null || !mounted || owner != user) return;
    final slot = 'cancel:${widget.suborderId}:${item.order_item_id}:$accepted';
    await run(() async {
      await ref
          .read(afterSaleRepositoryProvider)
          .cancelPaid(
            widget.suborderId,
            [
              CancellationItemInput(
                order_item_id: item.order_item_id,
                quantity: accepted,
              ),
            ],
            keys.putIfAbsent(slot, checkoutCommandKey),
          );
      keys.remove(slot);
    });
  }

  Future<void> apply(FulfillmentItem item) async {
    final user = owner, limit = item.quantity - item.cancelled_qty;
    if (user == null || busy || limit <= 0) return;
    String type = 'REFUND_ONLY', reason = 'QUALITY_ISSUE';
    final text = TextEditingController(),
        qty = TextEditingController(text: '1'),
        evidence = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, refresh) => AlertDialog(
          title: const Text('申请售后'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: '售后类型'),
                  items: const [
                    DropdownMenuItem(
                      value: 'REFUND_ONLY',
                      child: Text('仅退款'),
                    ),
                    DropdownMenuItem(
                      value: 'RETURN_REFUND',
                      child: Text('退货退款'),
                    ),
                  ],
                  onChanged: (v) => refresh(() => type = v ?? type),
                ),
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  decoration: const InputDecoration(labelText: '申请原因'),
                  items: const [
                    DropdownMenuItem(
                      value: 'QUALITY_ISSUE',
                      child: Text('质量问题'),
                    ),
                    DropdownMenuItem(value: 'WRONG_ITEM', child: Text('发错商品')),
                    DropdownMenuItem(value: 'DAMAGED', child: Text('商品破损')),
                    DropdownMenuItem(
                      value: 'NOT_RECEIVED',
                      child: Text('未收到货'),
                    ),
                    DropdownMenuItem(
                      value: 'CONSUMER_REGRET',
                      child: Text('不想要了'),
                    ),
                    DropdownMenuItem(value: 'OTHER', child: Text('其他原因')),
                  ],
                  onChanged: (v) => refresh(() => reason = v ?? reason),
                ),
                TextField(
                  controller: qty,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: '数量（最多 $limit 件）'),
                ),
                TextField(
                  controller: text,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: '问题描述'),
                ),
                TextField(
                  controller: evidence,
                  decoration: const InputDecoration(labelText: '凭证说明（可选）'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('暂不申请'),
            ),
            FilledButton(
              onPressed: () {
                final n = int.tryParse(qty.text);
                if (n == null ||
                    n < 1 ||
                    n > limit ||
                    text.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(c, true);
              },
              child: const Text('提交申请'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true || !mounted || owner != user) {
      disposeLater(text);
      disposeLater(qty);
      disposeLater(evidence);
      return;
    }
    final slot = 'apply:${widget.suborderId}:${item.order_item_id}';
    final input = AfterSaleInput(
      type: type,
      reason_code: reason,
      reason_text: text.text.trim(),
      items: [
        AfterSaleItemInput(
          order_item_id: item.order_item_id,
          quantity: int.parse(qty.text),
        ),
      ],
      evidence: evidence.text.trim().isEmpty
          ? const []
          : [AfterSaleEvidenceInput(content: evidence.text.trim())],
    );
    disposeLater(text);
    disposeLater(qty);
    disposeLater(evidence);
    await run(() async {
      await ref
          .read(afterSaleRepositoryProvider)
          .apply(widget.suborderId, input, keys.putIfAbsent(slot, checkoutCommandKey));
      keys.remove(slot);
    });
  }

  Future<void> withdraw(AfterSale value) async {
    final user = owner;
    if (user == null || busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('撤销这个售后申请？'),
        content: const Text('撤销后本次占用的退款数量会立即释放，可以稍后重新申请。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('暂不撤销'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认撤销'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || owner != user) return;
    final current = aftersales.firstWhere(
      (a) => a.id == value.id,
      orElse: () => value,
    );
    await run(
      () => ref
          .read(afterSaleRepositoryProvider)
          .cancelAftersale(
            current,
            keys.putIfAbsent(
              'withdraw:${current.id}:${current.version}',
              checkoutCommandKey,
            ),
          ),
    );
  }

  Future<void> shipReturn(AfterSale value) async {
    final user = owner;
    if (user == null || busy) return;
    final carrier = TextEditingController(text: 'SF'),
        tracking = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('填写退货运单'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: carrier,
              decoration: const InputDecoration(labelText: '承运商代码'),
            ),
            TextField(
              controller: tracking,
              decoration: const InputDecoration(labelText: '退货运单号'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('暂不填写'),
          ),
          FilledButton(
            onPressed: () {
              final valid =
                  RegExp(r'^[A-Z0-9_]{2,24}$').hasMatch(carrier.text) &&
                  RegExp(r'^[A-Za-z0-9-]{6,80}$').hasMatch(tracking.text);
              if (valid) Navigator.pop(c, true);
            },
            child: const Text('提交运单'),
          ),
        ],
      ),
    );
    if (submitted != true || !mounted || owner != user) {
      disposeLater(carrier);
      disposeLater(tracking);
      return;
    }
    final code = carrier.text, no = tracking.text;
    disposeLater(carrier);
    disposeLater(tracking);
    final current = aftersales.firstWhere(
      (a) => a.id == value.id,
      orElse: () => value,
    );
    await run(
      () => ref
          .read(afterSaleRepositoryProvider)
          .shipReturn(
            current,
            code,
            no,
            keys.putIfAbsent(
              'return:${current.id}:${current.version}',
              checkoutCommandKey,
            ),
          ),
    );
  }

  Future<void> escalate(AfterSale value) async {
    final user = owner;
    if (user == null || busy) return;
    final reason = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('申请平台介入？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('平台将依据双方凭证裁决，裁决结果为最终结果。'),
            TextField(
              controller: reason,
              maxLength: 500,
              decoration: const InputDecoration(labelText: '补充说明'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('暂不介入'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().isNotEmpty) Navigator.pop(c, true);
            },
            child: const Text('提交介入申请'),
          ),
        ],
      ),
    );
    if (submitted != true || !mounted || owner != user) {
      disposeLater(reason);
      return;
    }
    final text = reason.text.trim();
    disposeLater(reason);
    final current = aftersales.firstWhere(
      (a) => a.id == value.id,
      orElse: () => value,
    );
    await run(
      () => ref
          .read(afterSaleRepositoryProvider)
          .escalate(
            current,
            text,
            keys.putIfAbsent(
              'escalate:${current.id}:${current.version}',
              checkoutCommandKey,
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (before, after) {
      if (before?.principal?.user_id != after.principal?.user_id) {
        epoch++;
        setState(() {
          fulfillment = null;
          cancellations = const [];
          aftersales = const [];
          error = null;
          busy = false;
          keys.clear();
        });
      }
    });
    final f = fulfillment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        TextButton(onPressed: busy ? null : load, child: const Text('刷新售后')),
        if (f != null) ...[
          for (final item in f.items)
            if (cancellable(item) > 0)
              TextButton(
                onPressed: busy ? null : () => cancelPaid(item),
                child: Text('取消未发货商品（可取消 ${cancellable(item)} 件）'),
              ),
          for (final item in f.items)
            if (item.quantity - item.cancelled_qty > 0)
              TextButton(
                onPressed: busy ? null : () => apply(item),
                child: const Text('申请售后'),
              ),
        ],
        for (final c in cancellations)
          Text(
            '取消单 ${cancellationStatusLabel(c.status)} · 退款 ${orderMoney(c.refund_amount_fen)}',
          ),
        for (final a in aftersales)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${afterSaleTypeLabel(a.type)} · ${afterSaleStatusLabel(a.status)} · ${afterSaleReasonLabel(a.reason_code)}',
              ),
              Text(a.reason_text),
              if (a.refund_amount_fen > 0)
                Text('退款金额 ${orderMoney(a.refund_amount_fen)}'),
              if (a.return_tracking_no != null)
                Text('退货 ${a.return_carrier_code} · ${a.return_tracking_no}'),
              if (a.status == 'PENDING_MERCHANT' ||
                  a.status == 'WAITING_RETURN')
                TextButton(
                  onPressed: busy ? null : () => withdraw(a),
                  child: const Text('撤销申请'),
                ),
              if (a.status == 'WAITING_RETURN')
                FilledButton(
                  onPressed: busy ? null : () => shipReturn(a),
                  child: const Text('填写退货运单'),
                ),
              if (a.status == 'REJECTED' && a.decisions.isEmpty)
                FilledButton(
                  onPressed: busy ? null : () => escalate(a),
                  child: const Text('申请平台介入'),
                ),
            ],
          ),
      ],
    );
  }
}
