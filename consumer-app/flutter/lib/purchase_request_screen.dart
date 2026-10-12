import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/generated/dto.dart';
import 'api/client.dart';
import 'repositories.dart';
import 'reference_ui.dart';
import 'care_repository.dart';

const requestLabels = {
  'OPEN': '待查看',
  'REVIEWING': '处理中',
  'RESOLVED': '已答复',
  'REJECTED': '暂不受理',
  'CANCELLED': '已撤回',
};
String requestError(Object e) => e is ApiFailure
    ? switch (e.code) {
        'PURCHASE_REQUEST_LIMIT' => '今天提交较多，请稍后再来。',
        'CONCURRENT_MODIFICATION' => '进度已更新，请刷新后重试。',
        'PURCHASE_REQUEST_CLOSED' => '这条求购已结束，请刷新查看。',
        'VALIDATION_ERROR' => '请检查商品名称和筛选条件。',
        _ => '暂时无法完成，请稍后重试。',
      }
    : '连接失败，请稍后重试。';
final purchaseRequestsProvider = FutureProvider.autoDispose
    .family<PurchaseRequestListEnvelope, String?>((ref, cursor) async {
      final session = ref.watch(authProvider).principal?.session_id;
      if (session == null) throw StateError('请先登录');
      final page = PurchaseRequestListEnvelope.fromJson(
        await ref
            .watch(consumerApiProvider)
            .request(
              'GET',
              Uri(
                path: '/consumer/purchase-requests',
                queryParameters: {'limit': '50', 'cursor': ?cursor},
              ).toString(),
            ),
      );
      if (ref.read(authProvider).principal?.session_id != session) {
        throw StateError('会话已变化');
      }
      return page;
    });

class PurchaseRequestForm extends ConsumerStatefulWidget {
  final Map<String, String> searchContext;
  const PurchaseRequestForm({super.key, required this.searchContext});
  @override
  ConsumerState<PurchaseRequestForm> createState() =>
      _PurchaseRequestFormState();
}

class _PurchaseRequestFormState extends ConsumerState<PurchaseRequestForm> {
  final form = GlobalKey<FormState>(),
      title = TextEditingController(),
      description = TextEditingController();
  String command = careKey();
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    title.text = widget.searchContext['q'] ?? '';
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    final session = ref.read(authProvider).principal?.session_id;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(consumerApiProvider)
          .request(
            'POST',
            '/consumer/purchase-requests',
            body: PurchaseRequestInput(
              title: title.text.trim(),
              description: description.text.trim(),
              search_context: PurchaseRequestContext.fromJson(
                widget.searchContext,
              ),
            ).toJson(),
            idempotencyKey: command,
          );
      if (!mounted || ref.read(authProvider).principal?.session_id != session) {
        return;
      }
      ref.invalidate(purchaseRequestsProvider);
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('求购已记录，可在“我的求购”查看进度。')));
    } catch (e) {
      if (mounted && ref.read(authProvider).principal?.session_id == session) {
        setState(() {
          busy = false;
          error = requestError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (a, b) {
      if (a?.principal?.session_id != b.principal?.session_id && mounted) {
        Navigator.pop(context);
      }
    });
    return AlertDialog(
      title: const Text('我想买这个商品'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('平台会查看需求，但不保证上架、采购或到货。请勿填写手机号、地址等私人资料；当前使用测试资料。'),
                const SizedBox(height: 24),
                TextFormField(
                  controller: title,
                  enabled: !busy,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: '想买的商品'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请填写商品名称' : null,
                  onChanged: (_) => command = careKey(),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: description,
                  enabled: !busy,
                  maxLength: 1000,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '补充需求（选填）',
                    hintText: '例如品牌、规格或预算',
                  ),
                  onChanged: (_) => command = careKey(),
                ),
                const SizedBox(height: 16),
                Text('会一并保存本次 ${widget.searchContext.length} 项搜索条件，方便核对。'),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        PawdayButton(
          onPressed: busy ? null : submit,
          child: Text(busy ? '提交中…' : '提交求购'),
        ),
      ],
    );
  }
}

class PurchaseRequestsScreen extends ConsumerStatefulWidget {
  const PurchaseRequestsScreen({super.key});
  @override
  ConsumerState<PurchaseRequestsScreen> createState() =>
      _PurchaseRequestsState();
}

class _PurchaseRequestsState extends ConsumerState<PurchaseRequestsScreen> {
  String? cursor;
  final previous = <String?>[];
  bool busy = false;
  String? error;
  Future<void> cancel(PurchaseRequest row) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤回这条求购？'),
        content: const Text('记录与处理历史会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续保留'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认撤回'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final session = ref.read(authProvider).principal?.session_id;
    setState(() => busy = true);
    try {
      await ref
          .read(consumerApiProvider)
          .request(
            'POST',
            '/consumer/purchase-requests/${row.id}/cancel',
            version: row.version,
            idempotencyKey: careKey(),
          );
      if (mounted && ref.read(authProvider).principal?.session_id == session) {
        ref.invalidate(purchaseRequestsProvider);
        setState(() {
          cursor = null;
          previous.clear();
          error = null;
        });
      }
    } catch (e) {
      if (mounted && ref.read(authProvider).principal?.session_id == session) {
        setState(() => error = requestError(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (a, b) {
      if (a?.principal?.session_id != b.principal?.session_id) {
        setState(() {
          cursor = null;
          previous.clear();
          error = null;
          busy = false;
        });
      }
    });
    final data = ref.watch(purchaseRequestsProvider(cursor));
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的求购'),
        actions: [
          IconButton(
            tooltip: '刷新求购',
            onPressed: busy
                ? null
                : () => ref.invalidate(purchaseRequestsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                '记录你想买的好物',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text('求购不是订单，不产生扣款或采购承诺。处理进度和平台答复可在这里刷新查看。'),
              const SizedBox(height: 24),
              if (error != null) Text(error!),
              data.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Column(
                  children: [
                    Text(requestError(e)),
                    TextButton(
                      onPressed: () => ref.invalidate(purchaseRequestsProvider),
                      child: const Text('重试'),
                    ),
                  ],
                ),
                data: (p) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (p.data.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('还没有求购记录，可从商品搜索无结果页面发起。'),
                      ),
                    for (final row in p.data)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row.title,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 12),
                                Text(requestLabels[row.status] ?? row.status),
                                if (row.description.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  Text(row.description),
                                ],
                                if (row.response != null) ...[
                                  const SizedBox(height: 16),
                                  Text('平台答复：${row.response}'),
                                ],
                                const SizedBox(height: 12),
                                Text('创建于 ${row.created_at.substring(0, 10)}'),
                                if (row.status == 'OPEN' ||
                                    row.status == 'REVIEWING')
                                  TextButton(
                                    onPressed: busy ? null : () => cancel(row),
                                    child: const Text('撤回求购'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (p.page.has_more)
                      TextButton(
                        onPressed: () => setState(() {
                          previous.add(cursor);
                          cursor = p.page.next_cursor;
                        }),
                        child: const Text('下一页'),
                      ),
                    if (previous.isNotEmpty)
                      TextButton(
                        onPressed: () =>
                            setState(() => cursor = previous.removeLast()),
                        child: const Text('上一页'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
