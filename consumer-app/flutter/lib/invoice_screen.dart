import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/generated/dto.dart';
import 'care_repository.dart';
import 'repositories.dart';
import 'reference_ui.dart';

const invoiceStatus = {
  'REQUESTED': '待商家处理',
  'ACCEPTED': '商家已受理',
  'REJECTED': '商家已拒绝',
};
final invoicesProvider = FutureProvider.autoDispose
    .family<InvoiceApplicationListEnvelope, String?>((ref, cursor) async {
      final session = ref.watch(authProvider).principal?.session_id;
      if (session == null) throw StateError('请登录');
      final page = InvoiceApplicationListEnvelope.fromJson(
        await ref
            .watch(consumerApiProvider)
            .request(
              'GET',
              Uri(
                path: '/consumer/invoices',
                queryParameters: {'limit': '50', 'cursor': ?cursor},
              ).toString(),
            ),
      );
      if (ref.read(authProvider).principal?.session_id != session) {
        throw StateError('会话已更换');
      }
      return page;
    });

class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});
  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesState();
}

class _InvoicesState extends ConsumerState<InvoicesScreen> {
  String? cursor;
  final previous = <String?>[];
  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (a, b) {
      if (a?.principal?.session_id != b.principal?.session_id) {
        setState(() {
          cursor = null;
          previous.clear();
        });
      }
    });
    final data = ref.watch(invoicesProvider(cursor));
    return Scaffold(
      appBar: AppBar(
        title: const Text('发票申请'),
        actions: [
          IconButton(
            tooltip: '刷新申请',
            onPressed: () => ref.invalidate(invoicesProvider),
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
              const Text('从已付款订单发起申请，由对应商家分别处理。当前仅验证申请与受理流程，不开具真实税务发票。'),
              const SizedBox(height: 24),
              data.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text(careError(e)),
                data: (p) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (p.data.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('还没有发票申请，可前往我的订单选择已付款子订单。'),
                      ),
                    for (final i in p.data)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                i.merchant_name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              Text('子订单 ${i.suborder_no}'),
                              const SizedBox(height: 12),
                              Text(invoiceStatus[i.status] ?? i.status),
                              if (i.reason != null) Text('处理说明：${i.reason}'),
                              const SizedBox(height: 12),
                              Text(i.issuer_notice),
                            ],
                          ),
                        ),
                      ),
                    if (p.page.has_more)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            previous.add(cursor);
                            cursor = p.page.next_cursor;
                          });
                        },
                        child: const Text('下一页'),
                      ),
                    if (previous.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          setState(() => cursor = previous.removeLast());
                        },
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

class InvoiceForm extends ConsumerStatefulWidget {
  final String orderId, subId;
  const InvoiceForm({super.key, required this.orderId, required this.subId});
  @override
  ConsumerState<InvoiceForm> createState() => _InvoiceFormState();
}

class _InvoiceFormState extends ConsumerState<InvoiceForm> {
  final form = GlobalKey<FormState>(),
      title = TextEditingController(),
      tax = TextEditingController(),
      email = TextEditingController();
  String type = 'PERSONAL', command = careKey();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    title.dispose();
    tax.dispose();
    email.dispose();
    super.dispose();
  }

  Future<void> save() async {
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
            '/consumer/invoices',
            body: InvoiceInput(
              order_id: widget.orderId,
              suborder_ids: [widget.subId],
              title_type: type,
              title: title.text.trim(),
              tax_number: type == 'BUSINESS' ? tax.text.trim() : null,
              email: email.text.trim(),
            ).toJson(),
            idempotencyKey: command,
          );
      if (!mounted || ref.read(authProvider).principal?.session_id != session) {
        return;
      }
      ref.invalidate(invoicesProvider);
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('申请已提交，等待对应商家处理。')));
    } catch (e) {
      if (mounted && ref.read(authProvider).principal?.session_id == session) {
        setState(() {
          busy = false;
          error = careError(e);
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
      title: const Text('申请发票'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('仅记录申请并交给对应商家；当前模拟环境不会开具真实税务发票。请使用测试抬头和测试邮箱。'),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: '抬头类型'),
                  items: const [
                    DropdownMenuItem(value: 'PERSONAL', child: Text('个人')),
                    DropdownMenuItem(value: 'BUSINESS', child: Text('企业')),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          type = v!;
                          command = careKey();
                        }),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: title,
                  enabled: !busy,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: '发票抬头'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请填写抬头' : null,
                  onChanged: (_) => command = careKey(),
                ),
                if (type == 'BUSINESS') ...[
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: tax,
                    enabled: !busy,
                    maxLength: 20,
                    decoration: const InputDecoration(labelText: '纳税人识别号'),
                    validator: (v) =>
                        RegExp(r'^[A-Z0-9]{15,20}$').hasMatch(v?.trim() ?? '')
                        ? null
                        : '请输入 15–20 位大写字母或数字',
                    onChanged: (_) => command = careKey(),
                  ),
                ],
                const SizedBox(height: 20),
                TextFormField(
                  controller: email,
                  enabled: !busy,
                  maxLength: 254,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: '接收邮箱'),
                  validator: (v) =>
                      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                          .hasMatch(v?.trim() ?? '')
                      ? null
                      : '请填写有效邮箱',
                  onChanged: (_) => command = careKey(),
                ),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
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
          onPressed: busy ? null : save,
          child: Text(busy ? '提交中…' : '提交申请'),
        ),
      ],
    );
  }
}
