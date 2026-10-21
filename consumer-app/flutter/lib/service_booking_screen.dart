import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'reference_ui.dart';
import 'repositories.dart';
import 'service_booking_repository.dart';

String bookingError(Object error) => error is ApiFailure
    ? switch (error.code) {
        'BOOKING_SIMULATION_DISABLED' => '当前环境未开启服务预约演练。',
        'BOOKING_SLOT_FULL' => '这个时段已约满，请刷新或选择其他时段。',
        'BOOKING_ALREADY_EXISTS' => '你已预约这个时段，请查看我的预约。',
        'BOOKING_NOT_AVAILABLE' => '服务已暂停或时段已开始，请重新选择。',
        'BOOKING_ALREADY_STARTED' => '时段已经开始，无法在演练中取消。',
        'BOOKING_ALREADY_CANCELLED' => '预约已经取消，请刷新查看。',
        'BOOKING_CREDENTIAL_UNAVAILABLE' => '凭证已过期或预约状态已变，请刷新查看。',
        'BOOKING_FULFILLMENT_STARTED' => '已进入履约处理，不能取消，请联系门店。',
        'CONCURRENT_MODIFICATION' => '预约已更新，请刷新后再操作。',
        'RESOURCE_NOT_FOUND' => '门店或服务已不可用；已预约记录仍可在我的预约中查看。',
        'RATE_LIMITED' => '操作较频繁，请稍后再试。',
        _ => '暂时无法完成，请稍后重试。',
      }
    : '连接失败，请稍后重试。';

class ServiceBookingScreen extends ConsumerStatefulWidget {
  final String? storeId;
  const ServiceBookingScreen({super.key, this.storeId});
  @override
  ConsumerState<ServiceBookingScreen> createState() =>
      _ServiceBookingScreenState();
}

class _ServiceBookingScreenState extends ConsumerState<ServiceBookingScreen> {
  final credentials = <String, BookingCredential>{};
  final history = <String, List<BookingFulfillmentEvent>>{};
  final historyCursors = <String, String?>{};
  static const labels = {
    'BOOKED': '已预约 · 模拟不收费',
    'CANCELLED': '已取消',
    'CHECKED_IN': '已到店 · 模拟不收费',
    'COMPLETED': '已完成 · 模拟不收费',
    'NO_SHOW': '未到店',
    'EXCEPTION': '异常待人工处理',
    'SERVICE_UNAVAILABLE': '服务不可用',
    'SAFETY_STOP': '安全中止',
    'CUSTOMER_DISPUTE': '消费者异议',
  };
  List<BookingService> services = [];
  List<BookingSlot> slots = [];
  List<ServiceBooking> bookings = [];
  String? selected, serviceCursor, slotCursor, bookingCursor, error, notice;
  bool busy = false;
  int generation = 0;
  final keys = <String, String>{};
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void dispose() {
    generation++;
    credentials.clear();
    keys.clear();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ServiceBookingScreen old) {
    super.didUpdateWidget(old);
    if (old.storeId != widget.storeId) {
      reset();
      Future.microtask(load);
    }
  }

  void reset() {
    generation++;
    credentials.clear();
    history.clear();
    historyCursors.clear();
    services = [];
    slots = [];
    bookings = [];
    selected = null;
    serviceCursor = null;
    slotCursor = null;
    bookingCursor = null;
    error = null;
    notice = null;
    keys.clear();
    busy = false;
  }

  bool Function() stamp() {
    final g = generation, s = ref.read(authProvider).principal?.session_id;
    return () =>
        mounted &&
        g == generation &&
        s == ref.read(authProvider).principal?.session_id;
  }

  Future<void> load() async {
    final current = stamp();
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
      credentials.clear();
      history.clear();
      historyCursors.clear();
    });
    try {
      final repo = ref.read(serviceBookingRepositoryProvider);
      // Read owned bookings first; a hidden store must not hide cancellation access.
      final mine = await repo.mine();
      if (!current()) return;
      setState(() {
        bookings = mine.data;
        bookingCursor = mine.page.next_cursor;
      });
      if (widget.storeId != null) {
        final page = await repo.services(widget.storeId!);
        if (!current()) return;
        setState(() {
          services = page.data;
          serviceCursor = page.page.next_cursor;
          slots = [];
          slotCursor = null;
          if (!services.any((s) => s.id == selected)) {
            selected = services.isEmpty ? null : services.first.id;
          }
        });
        if (selected != null) await readSlots();
      }
    } catch (e) {
      if (current()) {
        setState(() {
          error = bookingError(e);
          services = [];
          slots = [];
          selected = null;
          serviceCursor = null;
          slotCursor = null;
        });
      }
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  Future<void> readSlots({bool more = false}) async {
    final id = selected, current = stamp();
    if (id == null) return;
    final page = await ref
        .read(serviceBookingRepositoryProvider)
        .slots(id, cursor: more ? slotCursor : null);
    if (current() && id == selected) {
      setState(() {
        slots = more ? [...slots, ...page.data] : page.data;
        slotCursor = page.page.next_cursor;
      });
    }
  }

  Future<void> more(String kind) async {
    final current = stamp();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(serviceBookingRepositoryProvider);
      if (kind == 'slots') {
        await readSlots(more: true);
      } else if (kind == 'services') {
        final page = await repo.services(
          widget.storeId!,
          cursor: serviceCursor,
        );
        if (current()) {
          setState(() {
            services = [...services, ...page.data];
            serviceCursor = page.page.next_cursor;
          });
        }
      } else {
        final page = await repo.mine(cursor: bookingCursor);
        if (current()) {
          setState(() {
            bookings = [...bookings, ...page.data];
            bookingCursor = page.page.next_cursor;
          });
        }
      }
    } catch (e) {
      if (current()) setState(() => error = bookingError(e));
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  Future<void> choose(String? id) async {
    setState(() {
      selected = id;
      slots = [];
      slotCursor = null;
      busy = true;
      error = null;
    });
    final current = stamp();
    try {
      await readSlots();
    } catch (e) {
      if (current()) setState(() => error = bookingError(e));
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  Future<void> command(
    String fingerprint,
    Future<ServiceBooking> Function(String key) action,
  ) async {
    if (busy) return;
    final current = stamp(),
        key = keys.putIfAbsent(fingerprint, () => const Uuid().v4());
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await action(key);
      if (!current()) return;
      keys.remove(fingerprint);
      setState(() => notice = '模拟记录已保存，不产生费用或真实履约承诺。');
      await load();
    } catch (e) {
      if (current()) setState(() => error = bookingError(e));
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  String time(String value) =>
      DateTime.parse(value).toLocal().toString().substring(0, 16);
  Future<void> readFulfillment(
    ServiceBooking b, {
    bool credential = false,
    bool more = false,
  }) async {
    if (busy) return;
    final current = stamp();
    setState(() {
      busy = true;
      error = null;
      credentials.clear();
    });
    try {
      final repo = ref.read(serviceBookingRepositoryProvider);
      if (credential) {
        final result = await repo.credential(b.id);
        if (current()) setState(() => credentials[b.id] = result);
      } else {
        final result = await repo.history(
          b.id,
          cursor: more ? historyCursors[b.id] : null,
        );
        if (current()) {
          setState(() {
            history[b.id] =
                (more ? [...history[b.id] ?? [], ...result.data] : result.data)
                  ..sort((a, b) => a.version.compareTo(b.version));
            historyCursors[b.id] = result.page.next_cursor;
          });
        }
      }
    } catch (e) {
      if (current()) setState(() => error = bookingError(e));
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
      appBar: AppBar(title: const Text('服务预约演练')),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '仅模拟预约，不收费，不代表真实门店承诺。每份预约占所选服务时段一个名额，开始前可取消。时间按本机时区展示。',
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => context.push(
                            Uri(
                              path: '/service-trades',
                              queryParameters: {'service_id': ?selected},
                            ).toString(),
                          ),
                    child: const Text('查看付费服务演练与交易'),
                  ),
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
                    onPressed: busy ? null : load,
                    child: const Text('刷新服务与预约'),
                  ),
                  if (busy) const LinearProgressIndicator(),
                  if (widget.storeId != null) ...[
                    const Text('门店模拟服务', style: TextStyle(fontSize: 22)),
                    if (services.isEmpty && !busy)
                      const Text('当前门店没有可预约的模拟服务。'),
                    for (final s in services)
                      ListTile(
                        title: Text(s.title),
                        subtitle: Text(s.kind == 'GROOMING' ? '洗护' : '寄养'),
                        selected: s.id == selected,
                        onTap: busy ? null : () => choose(s.id),
                      ),
                    if (serviceCursor != null)
                      TextButton(
                        onPressed: busy ? null : () => more('services'),
                        child: const Text('更多服务'),
                      ),
                    for (final slot in slots)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${time(slot.starts_at)} — ${time(slot.ends_at)}',
                              ),
                              Text('剩余 ${slot.remaining}/${slot.capacity} 个名额'),
                              PawdayButton(
                                onPressed: busy || slot.remaining < 1
                                    ? null
                                    : () => command(
                                        'reserve:${slot.id}',
                                        (key) => ref
                                            .read(
                                              serviceBookingRepositoryProvider,
                                            )
                                            .reserve(slot.id, key),
                                      ),
                                child: const Text('确认模拟预约'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (slotCursor != null)
                      TextButton(
                        onPressed: busy ? null : () => more('slots'),
                        child: const Text('更多时段'),
                      ),
                  ],
                  const SizedBox(height: 24),
                  const Text('我的模拟预约', style: TextStyle(fontSize: 22)),
                  if (bookings.isEmpty && !busy)
                    const Text('暂无模拟预约，可从附近门店进入选择服务。'),
                  for (final b in bookings)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.service_title),
                            Text('${time(b.starts_at)} — ${time(b.ends_at)}'),
                            Text(labels[b.status] ?? b.status),
                            SelectableText('预约编号 ${b.id}'),
                            if (b.status == 'BOOKED')
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () =>
                                          readFulfillment(b, credential: true),
                                child: const Text('出示模拟到店凭证'),
                              ),
                            if (credentials[b.id] case final c?) ...[
                              const Text('仅向本次预约门店出示；凭证只代表模拟到店，不代表真实身份核验。'),
                              Semantics(
                                container: true,
                                excludeSemantics: true,
                                label: '模拟到店凭证 ${c.credential}',
                                child: SelectableText('模拟到店凭证 ${c.credential}'),
                              ),
                              Text(
                                '可核销 ${time(c.valid_from)} — ${time(c.expires_at)}（结束时失效）',
                              ),
                              TextButton(
                                onPressed: () => setState(credentials.clear),
                                child: const Text('隐藏凭证'),
                              ),
                            ],
                            TextButton(
                              onPressed: busy ? null : () => readFulfillment(b),
                              child: const Text('查看履约记录'),
                            ),
                            if (history[b.id] case final events?) ...[
                              if (events.isEmpty) const Text('暂无模拟履约记录。'),
                              for (final e in events)
                                Text(
                                  '${e.version} · ${labels[e.status]} · ${time(e.occurred_at)} ${labels[e.reason_code] ?? ''}',
                                ),
                              if (historyCursors[b.id] != null)
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => readFulfillment(b, more: true),
                                  child: const Text('更多履约记录'),
                                ),
                            ],
                            if (b.status == 'BOOKED' &&
                                DateTime.parse(b.starts_at)
                                    .isAfter(DateTime.now()))
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => command(
                                        'cancel:${b.id}:${b.version}',
                                        (key) => ref
                                            .read(
                                              serviceBookingRepositoryProvider,
                                            )
                                            .cancel(b, key),
                                      ),
                                child: const Text('取消模拟预约'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (bookingCursor != null)
                    TextButton(
                      onPressed: busy ? null : () => more('bookings'),
                      child: const Text('更多预约'),
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
