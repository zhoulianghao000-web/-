import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'merchant_repository.dart';
import 'reference_ui.dart';
import 'session.dart';

final apiProvider = Provider<MerchantApi>((ref) {
  final transport = http.Client();
  ref.onDispose(transport.close);
  return MerchantApi(
    base: Uri.parse(
      const String.fromEnvironment(
        'PAWDAY_API_BASE',
        defaultValue: 'https://api.pawday.example/api/v1',
      ),
    ),
    transport: transport,
    vault: kIsWeb ? MemoryVault() : PlatformVault(),
  );
});
final sessionProvider = Provider<MerchantSession>((ref) {
  final session = MerchantSession(MerchantRepository(ref.watch(apiProvider)));
  ref.onDispose(session.dispose);
  unawaited(session.init());
  return session;
});
final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(sessionProvider);
  final router = GoRouter(
    refreshListenable: session,
    redirect: (context, state) {
      if (!session.ready) {
        return state.uri.path == '/loading' ? null : '/loading';
      }
      if (session.principal == null) {
        return state.uri.path == '/login'
            ? null
            : '/login?returnTo=${Uri.encodeComponent(safeReturnTo(state.uri.path))}';
      }
      if (state.uri.path == '/login' ||
          state.uri.path == '/loading' ||
          state.uri.path == '/') {
        return safeReturnTo(state.uri.queryParameters['returnTo']);
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/dashboard'),
      GoRoute(
        path: '/loading',
        builder: (_, _) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(
        path: '/login',
        builder: (_, _) => LoginPage(session: session),
      ),
      ShellRoute(
        builder: (_, state, child) =>
            MerchantFrame(session: session, path: state.uri.path, child: child),
        routes: [
          for (final path in [
            '/dashboard',
            'offers',
            'orders',
            'account',
          ].map((x) => x.startsWith('/') ? x : '/$x'))
            GoRoute(
              path: path,
              builder: (_, _) => ListenableBuilder(
                listenable: session,
                builder: (_, _) => WorkspacePage(
                  key: ValueKey('$path:${session.revision}'),
                  session: session,
                  path: path,
                ),
              ),
            ),
        ],
      ),
    ],
    errorBuilder: (context, _) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => GoRouter.of(context).go('/dashboard'),
          child: const Text('页面不可用'),
        ),
      ),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});

class MerchantApp extends ConsumerWidget {
  const MerchantApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: '爪日商家',
    theme: PawdayDesign.theme,
    routerConfig: ref.watch(routerProvider),
  );
}

class LoginPage extends StatefulWidget {
  final MerchantSession session;
  const LoginPage({super.key, required this.session});
  @override
  State<LoginPage> createState() => _LoginState();
}

class _LoginState extends State<LoginPage> {
  final name = TextEditingController(), password = TextEditingController();
  bool busy = false;
  String error = '';
  @override
  void dispose() {
    name.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (busy) return;
    if (name.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = '请输入商家账号和密码。');
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.session.login(name.text.trim(), password.text);
      password.clear();
    } catch (e) {
      if (mounted) setState(() => error = explain(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          if (pilotMode) const PilotNotice(),
          Expanded(
            child: ReferenceLoginFrame(
              compactHeader: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'MERCHANT',
                          style: TextStyle(letterSpacing: 3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '回到你的门店',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 12),
                        const Text('使用已分配的商家员工账号登录。'),
                        const SizedBox(height: 24),
                        TextField(
                          controller: name,
                          enabled: !busy,
                          decoration: const InputDecoration(labelText: '商家账号'),
                          autofillHints: const [AutofillHints.username],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: password,
                          enabled: !busy,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: '密码'),
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => login(),
                        ),
                        const SizedBox(height: 20),
                        if (error.isNotEmpty)
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              error,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        const SizedBox(height: 16),
                        PawdayButton(
                          onPressed: busy ? null : login,
                          child: Text(busy ? '正在登录…' : '登录商家工作台'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class PilotNotice extends StatelessWidget {
  const PilotNotice({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: PawdayDesign.green,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: const Text(
      '模拟经营数据 · 仅指定测试账号 · 不发生真实交易',
      style: TextStyle(color: Colors.white, fontSize: 12),
      textAlign: TextAlign.center,
    ),
  );
}

class MerchantFrame extends StatelessWidget {
  final MerchantSession session;
  final String path;
  final Widget child;
  const MerchantFrame({
    super.key,
    required this.session,
    required this.path,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('爪日 · 商家'),
        actions: [
          IconButton(
            tooltip: '退出登录',
            onPressed: () => session.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (pilotMode) const PilotNotice(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: DropdownButtonFormField<String>(
                key: ValueKey('${session.store}:${session.revision}'),
                initialValue: session.store ?? '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: '工作范围'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('全部授权范围')),
                  for (final store in session.stores)
                    DropdownMenuItem(
                      value: store.id,
                      child: Text(store.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) =>
                    session.selectStore(value == '' ? null : value),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: const [
          '/dashboard',
          '/offers',
          '/orders',
          '/account',
        ].indexOf(path).clamp(0, 3),
        onDestinationSelected: (i) => context.go(
          const ['/dashboard', '/offers', '/orders', '/account'][i],
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            label: '经营',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: '报价库存',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: '订单',
          ),
          NavigationDestination(
            icon: Icon(Icons.manage_accounts_outlined),
            label: '账号',
          ),
        ],
      ),
    ),
  );
}

class WorkspacePage extends StatefulWidget {
  final MerchantSession session;
  final String path;
  const WorkspacePage({super.key, required this.session, required this.path});
  @override
  State<WorkspacePage> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<WorkspacePage> {
  bool busy = false;
  String error = '';
  BusinessAnalytics? analytics;
  List<Map<String, dynamic>> rows = [];
  String? cursor;
  bool more = false;
  DateTime from = shanghaiToday(), to = shanghaiToday();
  int generation = 0;
  BuildContext? dialogContext;
  MerchantSession get session => widget.session;
  MerchantRepository get repository => session.repository;
  String get permission => switch (widget.path) {
    '/dashboard' => 'ledger.read',
    '/offers' => 'offer.read',
    '/orders' => 'order.read',
    _ => '',
  };
  @override
  void initState() {
    super.initState();
    session.addListener(closeDialog);
    unawaited(load());
  }

  void closeDialog() {
    if (dialogContext != null) {
      Navigator.of(dialogContext!).pop();
      dialogContext = null;
    }
  }

  @override
  void dispose() {
    generation++;
    session.removeListener(closeDialog);
    if (dialogContext != null) {
      final ctx = dialogContext;
      dialogContext = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ctx != null && ctx.mounted) Navigator.of(ctx).pop();
      });
    }
    super.dispose();
  }

  Future<void> load({bool append = false}) async {
    if (busy) return;
    final epoch = ++generation,
        identity = repository.api.generation,
        revision = session.revision;
    setState(() {
      busy = true;
      error = '';
      if (!append) {
        analytics = null;
        rows = [];
        cursor = null;
        more = false;
      }
    });
    try {
      await session.refreshIdentity();
      if (!mounted ||
          epoch != generation ||
          identity != repository.api.generation ||
          revision != session.revision) {
        return;
      }
      if (permission.isNotEmpty && !session.can(permission) ||
          widget.path == '/dashboard' && !session.can('order.read')) {
        throw const ApiFailure(403, 'PERMISSION_DENIED');
      }
      if (widget.path == '/dashboard') {
        final data = await repository.analytics(
          dateText(from),
          dateText(to),
          session.store,
        );
        if (mounted &&
            epoch == generation &&
            identity == repository.api.generation) {
          analytics = data;
        }
      } else {
        final path = switch (widget.path) {
          '/offers' => '/merchant/offers',
          '/orders' => '/merchant/suborders',
          _ => '/merchant/auth/sessions',
        };
        final data = await repository.list(
          path,
          store: widget.path == '/offers' ? session.store : null,
          cursor: append ? cursor : null,
        );
        if (!mounted ||
            epoch != generation ||
            identity != repository.api.generation) {
          return;
        }
        var next = (data['data'] as List)
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList();
        if (widget.path == '/orders' && session.store != null) {
          next = next
              .where(
                (x) =>
                    (x['items'] as List).isNotEmpty &&
                    (x['items'] as List).every(
                      (i) => (i as Map)['store_id'] == session.store,
                    ),
              )
              .toList();
        }
        rows = [if (append) ...rows, ...next];
        cursor = (data['page'] as Map?)?['next_cursor'] as String?;
        more = ((data['page'] as Map?)?['has_more'] as bool?) ?? false;
      }
    } catch (e) {
      if (mounted && epoch == generation) error = explain(e);
    } finally {
      if (mounted && epoch == generation) setState(() => busy = false);
    }
  }

  Future<void> chooseDate(bool start) async {
    final date = await showDatePicker(
      context: context,
      initialDate: start ? from : to,
      firstDate: DateTime(2000),
      lastDate: shanghaiToday(),
    );
    if (date != null && mounted) {
      setState(() {
        if (start) {
          from = DateTime.utc(date.year, date.month, date.day);
        } else {
          to = DateTime.utc(date.year, date.month, date.day);
        }
        analytics = null;
      });
    }
  }

  Future<void> action(Map<String, dynamic> row, String kind) async {
    final identity = repository.api.generation, revision = session.revision;
    String dialogError = '';
    bool sending = false;
    String reason = '';
    int delta = 0;
    final password = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          dialogContext = ctx;
          return StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
              title: Text(
                kind == 'inventory'
                    ? '调整库存'
                    : kind == 'sessions'
                    ? '注销其他设备'
                    : kind == 'pause'
                    ? '暂停报价'
                    : '启用报价',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      kind == 'inventory'
                          ? '填写变动数量，正数增加、负数减少；不覆盖已预占库存。'
                          : kind == 'sessions'
                          ? '验证当前密码后，仅注销其他设备。'
                          : '操作会使用当前读取的资料版本，请确认。',
                    ),
                    const SizedBox(height: 16),
                    if (kind == 'sessions')
                      TextField(
                        controller: password,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: '再次输入密码'),
                      )
                    else
                      TextField(
                        decoration: InputDecoration(
                          labelText: kind == 'inventory' ? '变动数量（整数）' : '操作原因',
                        ),
                        keyboardType: kind == 'inventory'
                            ? const TextInputType.numberWithOptions(
                                signed: true,
                              )
                            : TextInputType.text,
                        onChanged: (x) {
                          if (kind == 'inventory') {
                            delta = int.tryParse(x) ?? 0;
                          } else {
                            reason = x.trim();
                          }
                        },
                      ),
                    if (dialogError.isNotEmpty)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          dialogError,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: sending ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: sending
                      ? null
                      : () async {
                          if (identity != repository.api.generation ||
                              revision != session.revision ||
                              session.principal == null) {
                            return;
                          }
                          if (kind == 'inventory' && delta == 0 ||
                              kind == 'sessions' && password.text.isEmpty ||
                              !['sessions', 'inventory'].contains(kind) &&
                                  reason.isEmpty) {
                            update(() => dialogError = '请填写有效的操作内容。');
                            return;
                          }
                          update(() {
                            sending = true;
                            dialogError = '';
                          });
                          try {
                            if (kind == 'sessions') {
                              await repository.revokeOthers(password.text);
                            } else if (kind == 'inventory') {
                              await repository.command(
                                '/merchant/offers/${row['id']}/inventory-adjustments',
                                {
                                  'delta_qty': delta,
                                  'reason_code': 'COUNT_CORRECTION',
                                  'expected_version':
                                      (row['inventory'] as Map)['version'],
                                },
                              );
                            } else {
                              await repository.command(
                                '/merchant/offers/${row['id']}/$kind',
                                {'reason': reason},
                                version: row['version'] as int,
                              );
                            }
                            if (ctx.mounted &&
                                identity == repository.api.generation &&
                                revision == session.revision) {
                              Navigator.of(ctx).pop();
                              dialogContext = null;
                              await load();
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              update(() => dialogError = explain(e));
                            }
                          } finally {
                            if (ctx.mounted) update(() => sending = false);
                          }
                        },
                  child: Text(sending ? '处理中…' : '确认'),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      dialogContext = null;
      password.dispose();
    }
  }

  Future<void> details(Map<String, dynamic> row) async {
    final identity = repository.api.generation, revision = session.revision;
    try {
      final data = await repository.get('/merchant/suborders/${row['id']}');
      if (!mounted ||
          identity != repository.api.generation ||
          revision != session.revision) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          dialogContext = ctx;
          return AlertDialog(
            title: const Text('子订单明细'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data['suborder_no'].toString()),
                  Text('状态：${data['fulfillment_status']}'),
                  Text('冻结应付：${money(data['payable_amount_fen'] as int)}'),
                  for (final i in data['items'] as List)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        '${(i['product_snapshot'] as Map)['name'] ?? (i['product_snapshot'] as Map)['sku_code']}\n数量 ${i['quantity']} · 已取消 ${i['cancelled_qty']}',
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) setState(() => error = explain(e));
    } finally {
      dialogContext = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = {
      '/dashboard': '经营分析',
      '/offers': '报价与库存',
      '/orders': '子订单',
      '/account': '账号与设备',
    };
    return RefreshIndicator(
      onRefresh: () => load(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titles[widget.path]!,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: busy ? null : () => load(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(error, style: const TextStyle(color: Colors.red)),
              ),
            ),
          if (busy) const LinearProgressIndicator(),
          if (widget.path == '/dashboard') ...dashboard() else ...listing(),
          if (more)
            TextButton(
              onPressed: busy ? null : () => load(append: true),
              child: const Text('加载更多'),
            ),
        ],
      ),
    );
  }

  List<Widget> dashboard() => [
    const Text('支付与退款按上海记账日统计；金额不代表利润或可提余额。单店范围不包含混店子订单。'),
    const SizedBox(height: 16),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton(
          onPressed: () => chooseDate(true),
          child: Text('从 ${dateText(from)}'),
        ),
        OutlinedButton(
          onPressed: () => chooseDate(false),
          child: Text('至 ${dateText(to)}'),
        ),
        PawdayButton(
          onPressed: busy ? null : () => load(),
          child: const Text('查询经营分析'),
        ),
      ],
    ),
    const SizedBox(height: 20),
    if (analytics case final data?) ...[
      if (data.simulated && !pilotMode) const Text('模拟经营数据'),
      Text(
        '截至 ${data.as_of} · ${data.timezone}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      for (final metric in [
        ('支付入账', money(data.totals.paid_fen)),
        ('成功退款', money(data.totals.refund_fen)),
        ('收退款净额', money(data.totals.net_fen)),
        ('佣金净扣减', money(data.totals.commission_net_fen)),
        ('扣佣后经营净额', money(data.totals.merchant_net_fen)),
      ])
        Card(
          child: ListTile(
            title: Text(metric.$1),
            trailing: Text(
              metric.$2,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      Text(
        '${data.totals.paid_suborders} 笔支付子订单 · ${data.totals.refund_count} 笔成功退款',
      ),
      if (data.totals.paid_suborders == 0 && data.totals.refund_count == 0)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Text('所选范围暂无支付或退款记账事实。'),
        ),
      const SizedBox(height: 20),
      const Text('逐日记账'),
      for (final d in data.days)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.date),
                Text(
                  '支付 ${money(d.metrics.paid_fen)} · 退款 ${money(d.metrics.refund_fen)}',
                ),
                Text('净额 ${money(d.metrics.net_fen)}'),
              ],
            ),
          ),
        ),
    ],
  ];
  List<Widget> listing() => [
    if (widget.path == '/account') ...[
      const Text('门店和权限以服务端授权为准。完整履约、售后与结算操作请使用已登录的商家 Web 工作台。'),
      const SizedBox(height: 16),
      PawdayButton(
        onPressed: busy ? null : () => action({}, 'sessions'),
        child: const Text('验证密码并注销其他设备'),
      ),
      const SizedBox(height: 20),
    ],
    if (widget.path == '/orders')
      const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Text('仅显示完整授权的子订单；单店范围不包含混店子订单。完整履约和售后请使用商家 Web 工作台。'),
      ),
    for (final row in rows)
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (row['sku_code'] ??
                        row['suborder_no'] ??
                        row['device_id'] ??
                        '')
                    .toString(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (widget.path == '/offers') ...[
                Text(
                  '${row['store_name'] ?? '商户默认范围'} · ${row['sale_status']}',
                ),
                Text('普通报价 ${money(row['sale_price_fen'] as int)}'),
                Text(
                  '实物库存 ${(row['inventory'] as Map)['on_hand_qty']} · 预占 ${(row['inventory'] as Map)['reserved_qty']}',
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (session.can('inventory.adjust'))
                      TextButton(
                        onPressed: () => action(row, 'inventory'),
                        child: const Text('库存调整'),
                      ),
                    if (session.can('offer.write') &&
                        [
                          'DRAFT',
                          'PAUSED',
                          'ACTIVE',
                        ].contains(row['sale_status']))
                      TextButton(
                        onPressed: () => action(
                          row,
                          row['sale_status'] == 'ACTIVE' ? 'pause' : 'activate',
                        ),
                        child: Text(
                          row['sale_status'] == 'ACTIVE' ? '暂停报价' : '启用报价',
                        ),
                      ),
                  ],
                ),
              ],
              if (widget.path == '/orders') ...[
                Text(
                  '${row['fulfillment_status']} · 冻结应付 ${money(row['payable_amount_fen'] as int)}',
                ),
                TextButton(
                  onPressed: () => details(row),
                  child: const Text('查看明细'),
                ),
              ],
              if (widget.path == '/account')
                Text(
                  row['revoked_at'] != null
                      ? '已注销'
                      : row['id'] == session.principal?.session_id
                      ? '当前设备'
                      : '其他设备',
                ),
            ],
          ),
        ),
      ),
    if (rows.isEmpty && !busy)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Text('当前范围暂无记录。'),
      ),
  ];
}
