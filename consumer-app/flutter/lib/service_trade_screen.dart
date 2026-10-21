import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'repositories.dart';
import 'service_trade_repository.dart';

String serviceTradeError(Object error) => error is ApiFailure
    ? switch (error.code) {
        'SERVICE_TRADE_SIMULATION_DISABLED' ||
        'SERVICE_PAYMENT_SIMULATION_DISABLED' => '当前环境未开启付费服务演练。',
        'SERVICE_TERMS_UNAVAILABLE' => '暂时没有已审核的服务条款，请稍后再试。',
        'BOOKING_SLOT_FULL' => '这个时段已约满，请刷新或选择其他时段。',
        'BOOKING_NOT_AVAILABLE' => '服务已暂停或时段已开始，请刷新后重新选择。',
        'BOOKING_ALREADY_EXISTS' => '这个时段已有你的预约或交易，请先查看已有记录。',
        'SERVICE_QUOTE_EXPIRED' ||
        'SERVICE_QUOTE_STALE' => '报价已失效，请刷新条款并重新获取报价。',
        'SERVICE_REFUND_REVIEW_REQUIRED' => '此交易需要人工评估；未自动扣费或发起退款，请联系平台。',
        'PAYMENT_CONFIRMATION_PENDING' => '付款结果仍在确认，名额会保留，请稍后查证。',
        'SERVICE_FULFILLMENT_FROZEN' => '交易有待处理事项，暂时不能生成凭证。',
        'SERVICE_CREDENTIAL_UNAVAILABLE' => '凭证已过期或履约状态已更新，请刷新查看。',
        'SERVICE_DISPUTE_ALREADY_OPEN' => '争议已登记，请查看处理记录。',
        'CONCURRENT_MODIFICATION' => '交易已更新，请刷新后再操作。',
        'RESOURCE_NOT_FOUND' => '服务暂不可用，已有交易仍可在下方查看。',
        'RATE_LIMITED' => '操作较频繁，请稍后再试。',
        'PILOT_PAUSED' => '演练暂时暂停，已有记录会保留。',
        _ => '暂时无法完成，请刷新或稍后重试。',
      }
    : '连接失败，请稍后重试。';

class ServiceTradeScreen extends ConsumerStatefulWidget {
  final String? serviceId;
  const ServiceTradeScreen({super.key, this.serviceId});
  @override
  ConsumerState<ServiceTradeScreen> createState() => _ServiceTradeScreenState();
}

class _ServiceTradeScreenState extends ConsumerState<ServiceTradeScreen> {
  List<ServiceTrade> trades = [];
  List<BookingSlot> slots = [];
  ConsumerServiceTerms? terms;
  ServiceQuote? quote;
  String? tradeCursor, slotCursor, error, notice;
  bool busy = false, accepted = false;
  int generation = 0;
  final keys = <String, String>{},
      credentials = <String, ServiceTradeCredential>{},
      reasons = <String, String>{};
  final histories = <String, List<ServiceTradeFulfillmentEvent>>{},
      disputes = <String, List<ServiceTradeDispute>>{},
      refunds = <String, List<ServiceRefund>>{};
  final detailCursors = <String, String?>{};
  static const labels = {
    'AWAITING_PAYMENT': '待付款',
    'CONFIRMED': '已确认',
    'CANCELLED': '已取消',
    'EXPIRED': '已关闭',
    'PENDING': '待确认',
    'PROCESSING': '处理中',
    'UNKNOWN': '结果未知，仍在确认',
    'SUCCEEDED': '已成功',
    'NOT_STARTED': '尚未到店',
    'CHECKED_IN': '已到店',
    'COMPLETED': '已完成',
    'NO_SHOW': '未到店，需人工评估',
    'EXCEPTION': '异常待处理',
    'OPEN': '处理中',
    'RESOLVED': '已处理',
    'RESERVED': '已受理，未到账',
    'FAILED_RETRYABLE': '重试处理中',
    'NEEDS_REVIEW': '待人工处理',
  };
  ServiceTradeRepository get repo => ref.read(serviceTradeRepositoryProvider);
  String money(int fen) => '¥${(fen / 100).toStringAsFixed(2)}';
  String time(String value) =>
      DateTime.parse(value).toLocal().toString().substring(0, 16);
  bool Function() stamp() {
    final g = generation, s = ref.read(authProvider).principal?.session_id;
    return () =>
        mounted &&
        generation == g &&
        s == ref.read(authProvider).principal?.session_id;
  }

  void reset() {
    generation++;
    trades = [];
    slots = [];
    terms = null;
    quote = null;
    accepted = false;
    busy = false;
    tradeCursor = null;
    slotCursor = null;
    error = null;
    notice = null;
    keys.clear();
    credentials.clear();
    reasons.clear();
    histories.clear();
    disputes.clear();
    refunds.clear();
    detailCursors.clear();
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void didUpdateWidget(covariant ServiceTradeScreen old) {
    super.didUpdateWidget(old);
    if (old.serviceId != widget.serviceId) {
      reset();
      Future.microtask(load);
    }
  }

  @override
  void dispose() {
    reset();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    final current = stamp();
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
      credentials.clear();
    });
    try {
      final mine = await repo.mine(more ? tradeCursor : null);
      if (!current()) return;
      setState(() {
        trades = more ? [...trades, ...mine.data] : mine.data;
        tradeCursor = mine.page.next_cursor;
      });
      if (!more && widget.serviceId != null) {
        final shown = await repo.terms(widget.serviceId!);
        final available = await repo.slots(widget.serviceId!);
        if (current()) {
          setState(() {
            if (terms?.terms_sha256 != shown.terms_sha256) {
              quote = null;
              accepted = false;
            }
            terms = shown;
            slots = available.data;
            slotCursor = available.page.next_cursor;
          });
        }
      }
    } catch (e) {
      if (current()) {
        setState(() {
          error = serviceTradeError(e);
          if (e is ApiFailure &&
              [
                'SERVICE_TRADE_SIMULATION_DISABLED',
                'SERVICE_PAYMENT_SIMULATION_DISABLED',
              ].contains(e.code)) {
            trades = [];
          }
          if (!more) {
            terms = null;
            slots = [];
            slotCursor = null;
            quote = null;
            accepted = false;
          }
        });
      }
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  Future<void> command(
    String fingerprint,
    Future<void> Function(String) work,
  ) async {
    if (busy) return;
    final current = stamp(),
        key = keys.putIfAbsent(fingerprint, () => const Uuid().v4());
    setState(() {
      busy = true;
      error = null;
      notice = null;
      credentials.clear();
    });
    try {
      await work(key);
      if (!current()) return;
      keys.remove(fingerprint);
      setState(() => notice = '操作已保存，正在读取最新记录。');
      await load();
    } catch (e) {
      if (current()) setState(() => error = serviceTradeError(e));
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  Future<void> obtainQuote(BookingSlot slot) async {
    final shown = terms, current = stamp();
    if (shown == null) return;
    await command('quote:${shown.id}:${shown.version}:${slot.id}', (key) async {
      final q = await repo.quote(shown, slot, key);
      if (q.terms_sha256 != shown.terms_sha256) {
        throw const ApiFailure(409, 'SERVICE_QUOTE_STALE');
      }
      if (current()) {
        setState(() {
          quote = q;
          accepted = false;
        });
      }
    });
  }

  Future<void> reserve() async {
    final q = quote, current = stamp();
    if (q == null || !accepted) return;
    await command('reserve:${q.id}', (key) async {
      await repo.reserve(q, key);
      if (current()) {
        setState(() {
          quote = null;
          accepted = false;
        });
      }
    });
  }

  Future<void> details(
    ServiceTrade trade,
    String kind, {
    bool more = false,
  }) async {
    if (busy) return;
    final current = stamp();
    setState(() {
      busy = true;
      error = null;
      credentials.clear();
    });
    final fingerprint = '$kind:${trade.id}';
    try {
      final cursor = more ? detailCursors[fingerprint] : null;
      if (kind == 'credential') {
        final c = await repo.credential(trade);
        if (current()) setState(() => credentials[trade.id] = c);
      } else if (kind == 'history') {
        final r = await repo.history(trade, cursor);
        if (current()) {
          setState(() {
            histories[trade.id] = more
                ? [...histories[trade.id] ?? [], ...r.data]
                : r.data;
            histories[trade.id]!.sort((a, b) => a.version.compareTo(b.version));
            detailCursors[fingerprint] = r.page.next_cursor;
          });
        }
      } else if (kind == 'disputes') {
        final r = await repo.disputes(trade, cursor);
        if (current()) {
          setState(() {
            disputes[trade.id] = more
                ? [...disputes[trade.id] ?? [], ...r.data]
                : r.data;
            detailCursors[fingerprint] = r.page.next_cursor;
          });
        }
      } else {
        final r = await repo.refunds(trade, cursor);
        if (current()) {
          setState(() {
            refunds[trade.id] = more
                ? [...refunds[trade.id] ?? [], ...r.data]
                : r.data;
            detailCursors[fingerprint] = r.page.next_cursor;
          });
        }
      }
    } catch (e) {
      if (current()) setState(() => error = serviceTradeError(e));
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  Future<void> moreSlots() async {
    if (busy || widget.serviceId == null || slotCursor == null) return;
    final current = stamp();
    setState(() => busy = true);
    try {
      final r = await repo.slots(widget.serviceId!, slotCursor);
      if (current()) {
        setState(() {
          slots = [...slots, ...r.data];
          slotCursor = r.page.next_cursor;
        });
      }
    } catch (e) {
      if (current()) setState(() => error = serviceTradeError(e));
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (before, after) {
      if (before?.principal?.session_id != after.principal?.session_id) {
        setState(reset);
        if (after.principal != null) Future.microtask(load);
      }
    });
    return Scaffold(
      appBar: AppBar(title: const Text('付费服务演练')),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('仅合成服务交易与模拟收退款，不会真实扣款，不代表真实门店承诺。时间按本机时区展示。'),
                  if (error != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  if (notice != null)
                    Semantics(liveRegion: true, child: Text(notice!)),
                  TextButton(
                    onPressed: busy ? null : () => load(),
                    child: const Text('刷新服务交易'),
                  ),
                  if (terms case final t?) ...[
                    Text(t.service_title, style: const TextStyle(fontSize: 22)),
                    Text('每时段 ${money(t.amount_fen)} · 模拟收款'),
                    Text(
                      '开始前 ${t.cancel_cutoff_minutes} 分钟以外取消按合成条款全退；界线内、开始后或已到店需人工评估。商家在服务开始前取消按已冻结合成规则全退；开始后或已到店需人工评估。未到店不会自动形成扣罚或退款。',
                    ),
                    for (final slot in slots)
                      ListTile(
                        title: Text(
                          '${time(slot.starts_at)} — ${time(slot.ends_at)}',
                        ),
                        subtitle: Text(
                          '剩余 ${slot.remaining}/${slot.capacity} 个名额',
                        ),
                        trailing: TextButton(
                          onPressed: busy || slot.remaining < 1
                              ? null
                              : () => obtainQuote(slot),
                          child: const Text('获取服务报价'),
                        ),
                      ),
                    if (slotCursor != null)
                      TextButton(
                        onPressed: busy ? null : moreSlots,
                        child: const Text('更多服务时段'),
                      ),
                  ],
                  if (quote case final q?)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              '服务端报价 ${money(q.payable_fen)} · 有效至 ${time(q.expires_at)}',
                            ),
                            CheckboxListTile(
                              value: accepted,
                              onChanged: busy
                                  ? null
                                  : (value) => setState(
                                      () => accepted = value ?? false,
                                    ),
                              title: const Text('我已阅读并确认上方服务、价格及取消条款'),
                            ),
                            FilledButton(
                              onPressed: busy || !accepted ? null : reserve,
                              child: const Text('确认条款并预占名额'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  const Text('我的付费服务交易', style: TextStyle(fontSize: 22)),
                  if (trades.isEmpty && !busy)
                    const Text('暂无付费服务交易，可从门店服务中选择演练。'),
                  for (final t in trades)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText('交易编号 ${t.id}'),
                            Text(
                              '${time(t.starts_at)} · ${labels[t.order_state] ?? t.order_state} · ${labels[t.fulfillment_state] ?? t.fulfillment_state}',
                            ),
                            Text(
                              '应付 ${money(t.payable_fen)} · 已确认收款 ${money(t.paid_fen)} · 已成功退款 ${money(t.refunded_fen)} · 退款处理中 ${money(t.refund_reserved_fen)}',
                            ),
                            Text(
                              '付款：${labels[t.payment_state] ?? t.payment_state}',
                            ),
                            if (t.order_state == 'AWAITING_PAYMENT')
                              Text(
                                '名额保留至 ${time(t.hold_expires_at)}；结果未知时继续保留待确认责任。',
                              ),
                            Wrap(
                              spacing: 8,
                              children: [
                                if (t.order_state == 'AWAITING_PAYMENT' &&
                                    t.payment_state == 'PENDING')
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => command(
                                            'pay:${t.id}:${t.version}',
                                            (key) => repo.payment(t, key),
                                          ),
                                    child: const Text('发起模拟付款'),
                                  ),
                                if (t.payment_state != 'CLOSED')
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => command(
                                            'query:${t.id}:${t.version}',
                                            (key) => repo.payment(
                                              t,
                                              key,
                                              requery: true,
                                            ),
                                          ),
                                    child: const Text('查证付款结果'),
                                  ),
                                if ([
                                      'AWAITING_PAYMENT',
                                      'CONFIRMED',
                                    ].contains(t.order_state) &&
                                    t.fulfillment_state == 'NOT_STARTED')
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => command(
                                            'cancel:${t.id}:${t.version}',
                                            (key) => repo.cancel(t, key),
                                          ),
                                    child: const Text('申请取消服务'),
                                  ),
                                if (t.order_state == 'CONFIRMED' &&
                                    t.fulfillment_state == 'NOT_STARTED')
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => details(t, 'credential'),
                                    child: const Text('查看到店凭证'),
                                  ),
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => details(t, 'history'),
                                  child: const Text('读取履约记录'),
                                ),
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => details(t, 'refunds'),
                                  child: const Text('读取退款记录'),
                                ),
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => details(t, 'disputes'),
                                  child: const Text('读取争议记录'),
                                ),
                              ],
                            ),
                            if (credentials[t.id] case final c?) ...[
                              Semantics(
                                label: '到店凭证 ${c.credential}',
                                child: SelectableText('到店凭证 ${c.credential}'),
                              ),
                              Text(
                                '使用时间 ${time(c.valid_from)} — ${time(c.expires_at)}，请仅向授权门店出示。',
                              ),
                            ],
                            for (final h
                                in histories[t.id] ??
                                    <ServiceTradeFulfillmentEvent>[])
                              Text(
                                '${labels[h.status] ?? h.status} · ${time(h.occurred_at)}',
                              ),
                            for (final r in refunds[t.id] ?? <ServiceRefund>[])
                              Text(
                                '退款 ${money(r.amount_fen)} · ${labels[r.state] ?? r.state}',
                              ),
                            for (final d
                                in disputes[t.id] ?? <ServiceTradeDispute>[])
                              Text(
                                '争议 ${labels[d.state] ?? d.state} · ${time(d.opened_at)}',
                              ),
                            for (final kind in [
                              'history',
                              'refunds',
                              'disputes',
                            ])
                              if (detailCursors['$kind:${t.id}'] != null)
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => details(t, kind, more: true),
                                  child: Text(
                                    '更多${kind == 'history'
                                        ? '履约'
                                        : kind == 'refunds'
                                        ? '退款'
                                        : '争议'}记录',
                                  ),
                                ),
                            if (t.payment_state == 'SUCCEEDED' &&
                                !t.open_dispute) ...[
                              DropdownButton<String>(
                                value: reasons[t.id] ?? 'SERVICE_QUALITY',
                                onChanged: busy
                                    ? null
                                    : (value) => setState(
                                        () => reasons[t.id] = value!,
                                      ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'SERVICE_QUALITY',
                                    child: Text('服务质量'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'BOOKING_MISMATCH',
                                    child: Text('预约信息不符'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'SAFETY_CONCERN',
                                    child: Text('安全问题'),
                                  ),
                                ],
                              ),
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => command(
                                        'dispute:${t.id}:${t.version}:${reasons[t.id]}',
                                        (key) => repo.dispute(
                                          t,
                                          reasons[t.id] ?? 'SERVICE_QUALITY',
                                          key,
                                        ),
                                      ),
                                child: const Text('登记合成争议'),
                              ),
                            ],
                            if (t.open_dispute)
                              const Text('争议处理中，暂停履约与结算；处理记录不代表已作退款决定。'),
                          ],
                        ),
                      ),
                    ),
                  if (tradeCursor != null)
                    TextButton(
                      onPressed: busy ? null : () => load(more: true),
                      child: const Text('更多服务交易'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
