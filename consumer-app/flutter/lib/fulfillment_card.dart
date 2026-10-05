import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/generated/dto.dart';
import 'order_repository.dart';
import 'repositories.dart';
import 'checkout_repository.dart';

class FulfillmentCard extends ConsumerStatefulWidget {
  final String suborderId;
  final VoidCallback onChanged;
  const FulfillmentCard({
    super.key,
    required this.suborderId,
    required this.onChanged,
  });
  @override
  ConsumerState<FulfillmentCard> createState() => _FulfillmentCardState();
}

class _FulfillmentCardState extends ConsumerState<FulfillmentCard> {
  Fulfillment? detail;
  Tracking? tracking;
  String? error;
  bool busy = false;
  int epoch = 0;
  final Map<String, String> keys = {};
  String? get owner => ref.read(authProvider).principal?.user_id;
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void didUpdateWidget(FulfillmentCard old) {
    super.didUpdateWidget(old);
    if (old.suborderId != widget.suborderId) {
      epoch++;
      detail = null;
      tracking = null;
      keys.clear();
      busy = false;
      Future.microtask(load);
    }
  }

  @override
  void dispose() {
    epoch++;
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
      final d = await ref
          .read(orderRepositoryProvider)
          .fulfillment(widget.suborderId);
      if (mounted && step == epoch && owner == user) setState(() => detail = d);
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

  Future<void> action(Shipment h, bool receive) async {
    final d = detail, user = owner;
    if (d == null || user == null || busy) return;
    if (receive) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('确认这个包裹已收到？'),
          content: Text(
            '${h.carrier_code} · ${h.tracking_no}。仅确认此包裹，不会确认其他商家或包裹。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('暂不确认'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('确认已收到'),
            ),
          ],
        ),
      );
      if (yes != true ||
          !mounted ||
          owner != user ||
          detail?.version != d.version) {
        return;
      }
    }
    final step = ++epoch;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(orderRepositoryProvider);
      if (receive) {
        final value = await repo.receive(
          d,
          [h.id],
          keys.putIfAbsent(
            '${d.suborder_id}:${d.version}:${h.id}',
            checkoutCommandKey,
          ),
        );
        if (mounted && step == epoch && owner == user) {
          setState(() => detail = value);
          widget.onChanged();
        }
      } else {
        final value = await repo.tracking(h.id);
        if (mounted && step == epoch && owner == user) {
          setState(() => tracking = value);
        }
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

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (before, after) {
      if (before?.principal?.user_id != after.principal?.user_id) {
        epoch++;
        setState(() {
          detail = null;
          tracking = null;
          error = null;
          busy = false;
          keys.clear();
        });
      }
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        TextButton(onPressed: busy ? null : load, child: const Text('刷新包裹')),
        if (detail != null) ...[
          for (final i in detail!.items)
            Text(
              '已发 ${i.shipped_qty}/${i.quantity - i.cancelled_qty} · 已收 ${i.received_qty}',
            ),
          for (final h in detail!.shipments)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${h.carrier_code} · ${h.tracking_no}'),
                Text(h.confirmed_at == null ? '等待确认收货' : '用户已确认收货'),
                TextButton(
                  onPressed: busy ? null : () => action(h, false),
                  child: const Text('查看物流'),
                ),
                if (h.confirmed_at == null)
                  FilledButton(
                    onPressed: busy ? null : () => action(h, true),
                    child: const Text('确认这个包裹收货'),
                  ),
              ],
            ),
        ],
        if (tracking != null)
          Text(
            tracking!.status == 'UNKNOWN'
                ? '暂无可靠物流轨迹，请稍后重试'
                : '物流状态 ${tracking!.status}',
          ),
      ],
    );
  }
}
