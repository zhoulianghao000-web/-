import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'ai_repository.dart';
import 'api/client.dart';
import 'api/generated/dto.dart';
import 'repositories.dart';

class AiScreen extends ConsumerStatefulWidget {
  final List<String> skuIds;
  const AiScreen({super.key, this.skuIds = const []});
  @override
  ConsumerState<AiScreen> createState() => _AiState();
}

class _AiState extends ConsumerState<AiScreen> {
  final text = TextEditingController();
  AiPreferences? preferences;
  AiQuota? quota;
  List<AiConversation> history = [];
  List<AiMessage> messages = [];
  String? conversation, nextCursor, error;
  bool busy = false;
  int generation = 0;
  final keys = <String, String>{};
  AiRepository get repo => ref.read(aiRepositoryProvider);
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  bool Function() fence() {
    final g = generation,
        session = ref.read(authProvider).principal?.session_id;
    return () =>
        mounted &&
        g == generation &&
        session == ref.read(authProvider).principal?.session_id;
  }

  void reset() {
    generation++;
    conversation = null;
    messages = [];
    busy = false;
    error = null;
    keys.clear();
    text.clear();
  }

  Future<void> load({bool next = false}) async {
    final current = fence();
    try {
      final p = await repo.preferences(),
          q = await repo.quota(),
          h = await repo.conversations(cursor: next ? nextCursor : null);
      if (current()) {
        setState(() {
          preferences = p;
          quota = q;
          history = next ? [...history, ...h.data] : h.data;
          nextCursor = h.page.next_cursor;
        });
      }
    } catch (e) {
      if (current()) setState(() => error = '$e');
    }
  }

  Future<void> consent(bool enabled) async {
    if (preferences == null || busy) return;
    final current = fence();
    setState(() => busy = true);
    try {
      final value = await repo.consent(enabled, preferences!.version);
      if (current()) {
        setState(() {
          reset();
          preferences = value;
        });
      }
    } catch (e) {
      if (current()) setState(() => error = '$e');
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  Future<void> send() async {
    final question = text.text.trim();
    if (question.isEmpty || busy) return;
    final p = preferences, q = quota;
    if (p == null ||
        !p.provider_available ||
        q == null ||
        !q.enabled ||
        q.remaining == 0) {
      return;
    }
    final pet = p.personalization_enabled
        ? ref.read(currentPetProvider)?.id
        : null;
    final current = fence();
    setState(() {
      busy = true;
      error = null;
    });
    final createFingerprint = jsonEncode(['create', pet]);
    String? fingerprint;
    try {
      String? id = conversation;
      if (id == null) {
        final c = await repo.create(
          pet,
          keys.putIfAbsent(createFingerprint, () => const Uuid().v4()),
        );
        if (!current()) return;
        id = c.id;
        setState(() => conversation = id);
      }
      fingerprint = jsonEncode([id, pet, widget.skuIds, question]);
      final key = keys.putIfAbsent(fingerprint, () => const Uuid().v4());
      final result = await repo.send(
        id,
        AiMessageInput(
          text: question,
          current_pet_id: pet,
          selected_sku_ids: widget.skuIds,
        ),
        key,
      );
      if (current()) {
        setState(() {
          if (!messages.any((m) => m.message_id == result.message_id)) {
            messages = [...messages, result];
          }
          quota = result.quota;
          text.clear();
          keys.remove(fingerprint);
        });
        await load();
      }
    } catch (e) {
      if (current()) {
        if (e is ApiFailure &&
            (e.status == 503 ||
                e.code == 'AI_REQUEST_RELEASED_RETRY_NEW_KEY')) {
          keys.remove(fingerprint);
        }
        setState(() => error = '$e');
        await load();
      }
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  Future<void> open(AiConversation row) async {
    if (busy) return;
    setState(reset);
    final current = fence();
    setState(() => busy = true);
    try {
      final result = await repo.detail(row.id);
      if (current()) {
        setState(() {
          conversation = result.id;
          messages = result.messages;
        });
      }
    } catch (e) {
      if (current()) setState(() => error = '$e');
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  Future<void> clear() async {
    final id = conversation;
    if (id == null || busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除这段 AI 会话？'),
        content: const Text('问题和回答将从服务端清除。已经确认保存的宠物资料保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('保留'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除会话'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    final current = fence();
    try {
      await repo.clear(id);
      if (current()) {
        setState(reset);
        await load();
      }
    } catch (e) {
      if (current()) setState(() => error = '$e');
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  Future<void> proposal(String id) async {
    if (busy) return;
    setState(() => busy = true);
    final current = fence();
    try {
      final p = await repo.proposal(id);
      if (!mounted || !current()) return;
      if (p.status != 'PENDING') {
        setState(() => error = '该资料建议已处理或已过期。');
        return;
      }
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认宠物资料变更'),
          content: Text(
            '绝育状态：${p.before_value} → ${p.proposed_value}\n只会在你确认后保存。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('拒绝变更'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认保存'),
            ),
          ],
        ),
      );
      if (choice == null || !current()) return;
      await repo.decide(p, choice);
      if (current()) setState(() => error = choice ? '宠物资料已保存。' : '已拒绝资料变更。');
    } catch (e) {
      if (current()) setState(() => error = '$e');
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    generation++;
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (previous, next) {
      if (previous?.principal?.session_id != next.principal?.session_id) {
        setState(() {
          reset();
          preferences = null;
          quota = null;
          history = [];
          nextCursor = null;
        });
        if (next.principal != null) Future.microtask(load);
      }
    });
    ref.listen(currentPetProvider, (previous, next) {
      if (previous?.id != next?.id) setState(reset);
    });
    final pet = ref.watch(currentPetProvider), p = preferences, q = quota;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 商品资料解释'),
        actions: [
          IconButton(
            tooltip: '重新读取',
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('商品适合与否由平台规则判断。AI 帮你整理已核对资料；资料不足时会明确提示。'),
          if (p != null) ...[
            Text(p.data_usage),
            SwitchListTile(
              title: const Text('允许使用当前宠物进行个性化解释'),
              subtitle: Text(pet == null ? '尚未选择宠物' : pet.name),
              value: p.personalization_enabled,
              onChanged: busy ? null : consent,
            ),
          ],
          TextButton(
            onPressed: busy ? null : () => context.go('/pets'),
            child: const Text('选择当前宠物'),
          ),
          if (q != null)
            Text(
              '剩余 ${q.remaining} 次 · 普通 ${q.ordinary_remaining} 次／日 · 会员 ${q.membership_remaining} 次／购买周期',
            ),
          if (p != null && !p.provider_available)
            const Text('解释服务尚未配置，暂时不能发送问题。'),
          if (q != null && !q.enabled) const Text('解释服务暂时关闭。'),
          if (error != null) Text(error!, key: const ValueKey('ai-error')),
          for (final m in messages)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('你：${m.user_text}'),
                    Text(m.text),
                    Text('资料版本：${m.fit_rule_version}'),
                    for (final c in m.product_cards)
                      ListTile(
                        title: Text(c.name),
                        subtitle: Text(
                          '¥${(c.price_fen / 100).toStringAsFixed(2)} · ${c.fit_result} · 可售 ${c.available_qty}',
                        ),
                        onTap: () => context.go('/categories'),
                      ),
                    if (m.proposal_id != null)
                      TextButton(
                        onPressed: busy ? null : () => proposal(m.proposal_id!),
                        child: const Text('查看并确认资料建议'),
                      ),
                  ],
                ),
              ),
            ),
          TextField(
            controller: text,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            enabled: !busy,
            decoration: const InputDecoration(labelText: '想了解什么？例如 30元以内的食品'),
          ),
          FilledButton(
            onPressed:
                busy ||
                    p?.provider_available != true ||
                    q?.enabled != true ||
                    q?.remaining == 0
                ? null
                : send,
            child: Text(busy ? '正在整理…' : '发送问题'),
          ),
          if (conversation != null)
            TextButton(
              onPressed: busy ? null : clear,
              child: const Text('清除当前 AI 会话'),
            ),
          TextButton(
            onPressed: busy ? null : () => setState(reset),
            child: const Text('开始新会话'),
          ),
          const Text('历史会话'),
          for (final row in history)
            ListTile(
              title: Text('会话 ${row.created_at}'),
              subtitle: Text('保留至 ${row.expires_at}'),
              onTap: busy ? null : () => open(row),
            ),
          if (nextCursor != null)
            TextButton(
              onPressed: busy ? null : () => load(next: true),
              child: const Text('更多会话'),
            ),
        ],
      ),
    );
  }
}
