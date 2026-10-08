import 'dart:async';

import 'package:uuid/uuid.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'api/generated/dto.dart';
import 'repositories.dart';
import 'support_repository.dart';
import 'catalog_screen.dart';

const notificationLabels = {
  'ORDER': '订单',
  'AFTERSALE': '售后',
  'PRICE_DROP': '降价',
  'RESTOCK': '到货',
  'FOOD_REMINDER': '吃粮提醒',
  'ACTIVITY': '活动',
  'SUPPORT': '客服',
};

class SupportScreen extends ConsumerStatefulWidget {
  final String? storeId, suborderId, skuId;
  const SupportScreen({super.key, this.storeId, this.suborderId, this.skuId});
  @override
  ConsumerState<SupportScreen> createState() => _SupportState();
}

class _SupportState extends ConsumerState<SupportScreen> {
  List<Conversation> rows = [];
  String? nextCursor;
  String? error;
  bool busy = false;
  int generation = 0;
  SupportRepository get repo => ref.read(supportRepositoryProvider);
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  bool Function() fence() {
    final g = generation, s = ref.read(authProvider).principal?.session_id;
    return () =>
        mounted &&
        g == generation &&
        s == ref.read(authProvider).principal?.session_id;
  }

  Future<void> load({bool next = false}) async {
    final current = fence();
    try {
      final value = await repo.conversations(cursor: next ? nextCursor : null);
      if (current()) {
        setState(() {
          rows = next ? [...rows, ...value.data] : value.data;
          nextCursor = value.page.next_cursor;
        });
      }
    } catch (e) {
      if (current()) setState(() => error = '$e');
    }
  }

  Future<void> start(String? store) async {
    setState(() => busy = true);
    final current = fence();
    try {
      final c = await repo.create(store: store);
      if (current() && mounted) {
        await context.push(
          Uri(
            path: '/conversation',
            queryParameters: {
              'id': c.id,
              'suborder_id': ?widget.suborderId,
              'sku_id': ?widget.skuId,
            },
          ).toString(),
        );
      }
      if (current()) await load();
    } catch (e) {
      if (current()) setState(() => error = '$e');
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (_, next) {
      generation++;
      if (mounted) {
        setState(() {
          rows = [];
          error = null;
        });
      }
    });
    return Scaffold(
      appBar: AppBar(title: const Text('人工客服')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('平台人工客服或当前门店客服为你解答。'),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          FilledButton(
            onPressed: busy ? null : () => start(null),
            child: const Text('联系爪日平台客服'),
          ),
          if (widget.storeId != null)
            OutlinedButton(
              onPressed: busy ? null : () => start(widget.storeId),
              child: const Text('联系此门店客服'),
            ),
          if (nextCursor != null)
            TextButton(
              onPressed: () => load(next: true),
              child: const Text('更多会话'),
            ),
          for (final c in rows)
            ListTile(
              title: Text(c.kind == 'PLATFORM' ? '爪日平台客服' : '商家客服'),
              subtitle: Text(
                '${c.status == 'OPEN' ? '处理中' : '已关闭'} · 未读 ${c.unread_count}',
              ),
              onTap: () => context.push(
                Uri(
                  path: '/conversation',
                  queryParameters: {
                    'id': c.id,
                    'suborder_id': ?widget.suborderId,
                    'sku_id': ?widget.skuId,
                  },
                ).toString(),
              ),
            ),
        ],
      ),
    );
  }
}

class ConversationScreen extends ConsumerStatefulWidget {
  final String id;
  final String? suborderId, skuId;
  const ConversationScreen({
    super.key,
    required this.id,
    this.suborderId,
    this.skuId,
  });
  @override
  ConsumerState<ConversationScreen> createState() => _ConversationState();
}

class _ConversationState extends ConsumerState<ConversationScreen> {
  Conversation? conversation;
  List<SupportMessage> messages = [];
  final text = TextEditingController();
  final keys = <String, String>{};
  final images = <String, Uint8List>{};
  String? error, asset;
  bool busy = false, polling = false;
  int generation = 0;
  Timer? timer;
  SupportRepository get repo => ref.read(supportRepositoryProvider);
  bool Function() fence() {
    final g = generation, s = ref.read(authProvider).principal?.session_id;
    return () =>
        mounted &&
        g == generation &&
        s == ref.read(authProvider).principal?.session_id;
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(poll);
    timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    text.dispose();
    images.clear();
    super.dispose();
  }

  Future<void> poll() async {
    if (polling) return;
    polling = true;
    final current = fence();
    try {
      var c = await repo.detail(widget.id);
      final page = await repo.messages(
        widget.id,
        messages.isEmpty ? 0 : messages.last.sequence,
      );
      if (!current()) return;
      final seen = messages.map((m) => m.id).toSet();
      final next = [
        ...messages,
        ...page.data.where((m) => !seen.contains(m.id)),
      ];
      if (next.isNotEmpty && next.last.sequence > c.read_sequence) {
        c = await repo.read(widget.id, next.last.sequence);
      }
      if (current()) {
        setState(() {
          if (conversation == null || c.version >= conversation!.version) {
            conversation = c;
          }
          messages = next;
        });
      }
    } catch (e) {
      if (current()) {
        setState(() {
          error = '$e';
          messages = [];
          images.clear();
        });
      }
    } finally {
      polling = false;
    }
  }

  Future<void> send(String type, {String? target}) async {
    setState(() {
      busy = true;
      error = null;
    });
    final current = fence();
    final body = SupportMessageInput(
      type: type,
      body: type == 'TEXT' ? text.text : null,
      asset_ids: type == 'IMAGE' && asset != null ? [asset!] : [],
      target_id: target,
    );
    final fingerprint = jsonEncode(body.toJson());
    final key = keys.putIfAbsent(fingerprint, () => const Uuid().v4());
    try {
      await repo.send(widget.id, body, key);
      if (current()) {
        keys.remove(fingerprint);
        text.clear();
        setState(() => asset = null);
        await poll();
      }
    } catch (e) {
      if (current()) setState(() => error = '$e · 可保留原内容重试');
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  Future<void> upload() async {
    final current = fence();
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null || !current()) return;
    setState(() => busy = true);
    try {
      final bytes = await file.readAsBytes();
      if (!current()) return;
      final mime = file.name.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      final value = await repo.upload(bytes, mime);
      if (current()) setState(() => asset = value.asset_id);
    } catch (e) {
      if (current()) setState(() => error = '$e');
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  Future<void> image(PublicationMedia m) async {
    final current = fence();
    try {
      final bytes = await repo.image(m.content_url);
      if (current()) setState(() => images[m.asset_id] = bytes);
    } catch (e) {
      if (current()) setState(() => error = '$e');
    }
  }

  Future<void> card(SupportMessage m) async {
    final current = fence();
    try {
      final value = await repo.card(widget.id, m.id);
      if (!current() || !mounted) return;
      if (!value.available) {
        setState(() => error = '关联商品暂不可用');
        return;
      }
      if (value.type == 'ORDER') {
        await context.push('/orders?id=${value.destination!.split('/').last}');
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProductScreen(sku: value.target_id),
          ),
        );
      }
    } catch (e) {
      if (current()) setState(() => error = '$e');
    }
  }

  Future<void> status() async {
    final c = conversation;
    if (c == null) return;
    setState(() => busy = true);
    final current = fence();
    try {
      final value = await repo.status(
        c,
        c.status == 'OPEN' ? 'CLOSED' : 'OPEN',
      );
      if (current()) setState(() => conversation = value);
    } catch (e) {
      if (current()) setState(() => error = '$e');
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (_, next) {
      generation++;
      timer?.cancel();
      if (mounted) {
        setState(() {
          conversation = null;
          messages = [];
          images.clear();
          asset = null;
          text.clear();
          keys.clear();
          error = null;
        });
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('客服会话'),
        actions: [IconButton(onPressed: poll, icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final m in messages)
                  Align(
                    alignment: m.outgoing
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Card(
                      color: m.outgoing ? const Color(0xffe8f3ec) : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${m.outgoing ? '我' : '客服'} · ${m.sequence}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            if (m.type == 'TEXT')
                              Text(m.body!)
                            else if (m.type == 'IMAGE') ...[
                              for (final media in m.media)
                                images.containsKey(media.asset_id)
                                    ? Image.memory(
                                        images[media.asset_id]!,
                                        width: 200,
                                      )
                                    : TextButton(
                                        onPressed: () => image(media),
                                        child: const Text('查看会话图片'),
                                      ),
                            ] else
                              TextButton(
                                onPressed: () => card(m),
                                child: Text(
                                  m.type == 'ORDER' ? '查看订单卡片' : '查看商品卡片',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (conversation != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(conversation!.assigned ? '客服正在接待' : '等待人工客服接待'),
                  TextButton(
                    onPressed: busy ? null : status,
                    child: Text(
                      conversation!.status == 'OPEN' ? '关闭会话' : '重新打开',
                    ),
                  ),
                  if (conversation!.status == 'OPEN') ...[
                    TextField(
                      controller: text,
                      maxLength: 2000,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: '消息'),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed: busy ? null : () => send('TEXT'),
                          child: const Text('发送'),
                        ),
                        OutlinedButton(
                          onPressed: busy ? null : upload,
                          child: const Text('选择图片'),
                        ),
                        if (asset != null)
                          FilledButton(
                            onPressed: busy ? null : () => send('IMAGE'),
                            child: const Text('发送已上传图片'),
                          ),
                        if (widget.suborderId != null)
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () =>
                                      send('ORDER', target: widget.suborderId),
                            child: const Text('发送此订单卡片'),
                          ),
                        if (widget.skuId != null)
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => send('PRODUCT', target: widget.skuId),
                            child: const Text('发送此商品卡片'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});
  @override
  ConsumerState<MessagesScreen> createState() => _MessagesState();
}

class _MessagesState extends ConsumerState<MessagesScreen> {
  List<NotificationMessage> rows = [];
  List<NotificationPreference> preferences = [];
  String? error, category, cursor;
  bool more = false, busy = false;
  int generation = 0;
  SupportRepository get repo => ref.read(supportRepositoryProvider);
  bool Function() fence() {
    final g = generation, s = ref.read(authProvider).principal?.session_id;
    return () =>
        mounted &&
        g == generation &&
        s == ref.read(authProvider).principal?.session_id;
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> load({bool next = false}) async {
    final current = fence();
    try {
      final page = await repo.notifications(
        category: category,
        cursor: next ? cursor : null,
      );
      final prefs = await repo.preferences();
      if (current()) {
        setState(() {
          rows = next ? [...rows, ...page.data] : page.data;
          preferences = prefs;
          cursor = page.page.next_cursor;
          more = page.page.has_more;
        });
      }
    } catch (e) {
      if (current()) setState(() => error = '$e');
    }
  }

  Future<void> open(NotificationMessage m) async {
    final current = fence();
    try {
      await repo.notificationRead(m.id);
      if (!current()) return;
      final destination = await repo.destination(m.id);
      if (!current() || !mounted) return;
      await context.push(destination);
      if (current()) await load();
    } catch (e) {
      if (current()) setState(() => error = '$e');
    }
  }

  Future<void> change(NotificationPreference p, bool enabled) async {
    setState(() => busy = true);
    final current = fence();
    try {
      await repo.preference(p.category, enabled);
      if (current()) await load();
    } catch (e) {
      if (current()) setState(() => error = '$e');
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (_, next) {
      generation++;
      if (mounted) {
        setState(() {
          rows = [];
          preferences = [];
          error = null;
        });
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('消息与提醒'),
        actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          DropdownButton<String>(
            value: category,
            hint: const Text('全部消息'),
            items: [
              const DropdownMenuItem(value: null, child: Text('全部消息')),
              for (final entry in notificationLabels.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) {
              generation++;
              setState(() => category = value);
              load();
            },
          ),
          for (final m in rows)
            ListTile(
              leading: Icon(
                m.read_at == null
                    ? Icons.mark_email_unread
                    : Icons.mail_outline,
              ),
              title: Text(notificationLabels[m.category] ?? m.category),
              subtitle: Text(m.event_type),
              onTap: () => open(m),
            ),
          if (more)
            TextButton(
              onPressed: () => load(next: true),
              child: const Text('更多消息'),
            ),
          const Divider(),
          const Text('提醒偏好', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('分别控制每类业务提醒；不改变会话和消息记录。这些设置与系统通知权限分开，当前版本未接入系统推送。'),
          for (final p in preferences)
            SwitchListTile(
              title: Text(notificationLabels[p.category] ?? p.category),
              value: p.enabled,
              onChanged: busy ? null : (value) => change(p, value),
            ),
        ],
      ),
    );
  }
}
