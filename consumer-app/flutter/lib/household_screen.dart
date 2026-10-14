import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'household_repository.dart';
import 'pet_repository.dart';
import 'reference_ui.dart';
import 'repositories.dart';

String householdError(Object e) => e is ApiFailure
    ? switch (e.code) {
        'CONCURRENT_MODIFICATION' => '这条记录已被更新，请刷新后再操作。',
        'RESOURCE_NOT_FOUND' => '共享权限或宠物已不可用，请重新选择。',
        'INVITE_UNAVAILABLE' => '邀请已过期、撤销或被使用，请向主人索取新邀请。',
        'OWNER_CANNOT_ACCEPT_INVITE' => '主人无需接受自己的邀请。',
        'INVITE_LIMIT_REACHED' => '最多保留5个有效邀请，请先撤销不用的邀请。',
        'ALREADY_A_MEMBER' => '你已加入这只宠物的家庭照顾。',
        'PERMISSION_DENIED' => '当前成员没有此操作权限。',
        'TASK_CLOSED' => '任务已经结束，请刷新查看最新状态。',
        'VALIDATION_ERROR' => '请检查日期、邀请凭证和填写内容。',
        'RATE_LIMITED' => '操作较频繁，请稍后重试。',
        _ => '暂时无法完成，请稍后重试。',
      }
    : '连接失败，请稍后重试。';

class HouseholdScreen extends ConsumerStatefulWidget {
  const HouseholdScreen({super.key});
  @override
  ConsumerState<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends ConsumerState<HouseholdScreen> {
  List<HouseholdPet> pets = [];
  HouseholdOverview? overview;
  String? current;
  String? error;
  bool loading = true, busy = false;
  int generation = 0;
  Timer? poll;
  final pendingKeys = <String, String>{};
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
    poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!busy && !loading) load(quiet: true);
    });
  }

  @override
  void dispose() {
    generation++;
    poll?.cancel();
    pendingKeys.clear();
    super.dispose();
  }

  Future<void> load({bool quiet = false}) async {
    if (!mounted) return;
    final epoch = ++generation,
        session = ref.read(authProvider).principal?.session_id;
    if (session == null) {
      setState(() {
        pets = [];
        current = null;
        overview = null;
        loading = false;
      });
      return;
    }
    if (!quiet) {
      setState(() {
        loading = true;
        error = null;
        overview = null;
      });
    }
    try {
      final repo = ref.read(householdRepositoryProvider),
          list = await repo.pets();
      final selected = list.any((p) => p.id == current)
          ? current
          : (list.isEmpty ? null : list.first.id);
      final detail = selected == null ? null : await repo.overview(selected);
      if (!mounted ||
          epoch != generation ||
          ref.read(authProvider).principal?.session_id != session) {
        return;
      }
      setState(() {
        pets = list;
        current = selected;
        overview = detail;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted || epoch != generation) return;
      setState(() {
        error = householdError(e);
        loading = false;
        overview = null;
        if (e is ApiFailure && [401, 403, 404].contains(e.status)) {
          current = null;
          pets = [];
          pendingKeys.clear();
        }
      });
    }
  }

  Future<Map<String, dynamic>?> write(
    String path, {
    Map<String, dynamic>? body,
    int? version,
  }) async {
    if (busy) return null;
    final session = ref.read(authProvider).principal?.session_id;
    if (session == null) return null;
    final signature = jsonEncode([session, path, version, body]);
    final key = pendingKeys.putIfAbsent(signature, newPetCommandKey);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await ref
          .read(householdRepositoryProvider)
          .command(path, key, body: body, version: version);
      if (!mounted || ref.read(authProvider).principal?.session_id != session) {
        return null;
      }
      pendingKeys.remove(signature);
      await load();
      if (!mounted || ref.read(authProvider).principal?.session_id != session) {
        return null;
      }
      return result;
    } catch (e) {
      if (mounted && ref.read(authProvider).principal?.session_id == session) {
        setState(() => error = householdError(e));
        if (e is ApiFailure && [401, 403, 404, 409].contains(e.status)) {
          pendingKeys.remove(signature);
          await load(quiet: true);
          if (mounted) setState(() => error = householdError(e));
        }
      }
      return null;
    } finally {
      if (mounted && ref.read(authProvider).principal?.session_id == session) {
        setState(() => busy = false);
      }
    }
  }

  Future<bool> confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            PawdayButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> accept() async {
    final session = ref.read(authProvider).principal?.session_id;
    final controller = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('加入家庭照顾'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('粘贴主人提供的一次性邀请凭证。邀请仅授权宠物档案查看及约定的照顾协作。'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLength: 43,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: '邀请凭证'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          PawdayButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('接受邀请'),
          ),
        ],
      ),
    );
    // The controller remains alive through the dialog exit animation.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (token == null ||
        !mounted ||
        ref.read(authProvider).principal?.session_id != session) {
      return;
    }
    await write('/accept', body: {'invite_token': token});
  }

  Future<void> invite() async {
    final pet = current, session = ref.read(authProvider).principal?.session_id;
    String role = 'VIEWER';
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('邀请照顾成员'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '成员可查看姓名、生日、品种、过敏观察、忌口和照顾记录。不会获得私人照片、订单、地址、付款、客服或AI授权。凭证24小时有效，仅首位接受者使用。',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: role,
                items: const [
                  DropdownMenuItem(value: 'VIEWER', child: Text('仅查看')),
                  DropdownMenuItem(
                    value: 'CAREGIVER',
                    child: Text(
                      '共同照顾',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: (v) => update(() => role = v!),
                decoration: const InputDecoration(labelText: '成员权限'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            PawdayButton(
              onPressed: () => Navigator.pop(ctx, role),
              child: const Text('创建邀请'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null ||
        pet == null ||
        !mounted ||
        current != pet ||
        ref.read(authProvider).principal?.session_id != session) {
      return;
    }
    final result = await write(
      '/pets/$current/invites',
      body: {'role': chosen},
    );
    if (result == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('邀请已创建'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请仅交给你信任且已登录的成员。不要将邀请放到公开页面或反馈截图中。'),
            const SizedBox(height: 16),
            SelectableText(result['invite_token'] as String),
            const SizedBox(height: 12),
            Text('有效至 ${result['expires_at']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: result['invite_token'] as String),
              );
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(const SnackBar(content: Text('已复制邀请凭证')));
              }
            },
            child: const Text('复制邀请'),
          ),
          PawdayButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  String today() {
    final day = DateTime.now().toUtc().add(const Duration(hours: 8));
    return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  }

  Future<void> compose(bool task) async {
    final pet = current, session = ref.read(authProvider).principal?.session_id;
    final text = TextEditingController(),
        date = TextEditingController(text: today());
    String kind = 'NOTE';
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(task ? '新增照顾任务' : '写下照顾记录'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!task)
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: '记录类型'),
                  items: const [
                    DropdownMenuItem(value: 'NOTE', child: Text('日常观察')),
                    DropdownMenuItem(value: 'FEEDING', child: Text('喂食')),
                    DropdownMenuItem(value: 'WALK', child: Text('散步')),
                    DropdownMenuItem(value: 'GROOMING', child: Text('清洁护理')),
                  ],
                  onChanged: (v) => update(() => kind = v!),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: text,
                maxLength: task ? 160 : 2000,
                minLines: task ? 1 : 3,
                maxLines: task ? 2 : 5,
                decoration: InputDecoration(
                  labelText: task ? '任务名称' : '记录内容',
                  helperText: task ? null : '只记录日常观察，不代替兽医诊断。',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: date,
                decoration: InputDecoration(
                  labelText: task ? '计划日期' : '记录日期',
                  hintText: 'YYYY-MM-DD',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            PawdayButton(
              onPressed: () {
                if (text.text.trim().isEmpty ||
                    !RegExp(r'^\d{4}-\d{2}-\d{2}$')
                        .hasMatch(date.text.trim())) {
                  return;
                }
                Navigator.pop(
                  ctx,
                  task
                      ? {'title': text.text.trim(), 'due_on': date.text.trim()}
                      : {
                          'kind': kind,
                          'note': text.text.trim(),
                          'recorded_on': date.text.trim(),
                        },
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    text.dispose();
    date.dispose();
    if (body == null ||
        !mounted ||
        pet == null ||
        current != pet ||
        ref.read(authProvider).principal?.session_id != session) {
      return;
    }
    await write('/pets/$current/${task ? 'tasks' : 'entries'}', body: body);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (before, after) {
      if (before?.principal?.session_id != after.principal?.session_id) {
        generation++;
        pendingKeys.clear();
        setState(() {
          pets = [];
          current = null;
          overview = null;
          error = null;
          busy = false;
        });
        load();
      }
    });
    final detail = overview,
        owner = detail?.pet.share_role == 'OWNER',
        canWrite = owner || detail?.pet.share_role == 'CAREGIVER';
    return Scaffold(
      appBar: AppBar(
        title: const Text('家庭照顾'),
        actions: [
          IconButton(
            tooltip: '刷新家庭照顾',
            onPressed: busy ? null : () => load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '一起照顾，记住每一份陪伴',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  const Text('家庭共享仅用于宠物档案查看和日常协作。购物与智能选品仍使用你自己的宠物档案。'),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      PawdayButton(
                        onPressed: busy ? null : accept,
                        child: const Text('接受邀请'),
                      ),
                      if (owner)
                        PawdayButton(
                          onPressed: busy ? null : invite,
                          child: const Text('邀请成员'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (error != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(error!),
                            TextButton(
                              onPressed: busy ? null : () => load(),
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (loading)
                    const Center(child: CircularProgressIndicator())
                  else if (pets.isEmpty && error == null)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('还没有可共同照顾的宠物。先在“我的宠物”创建档案，或接受家人的邀请。'),
                      ),
                    ),
                  if (pets.isNotEmpty)
                    DropdownButtonFormField<String>(
                      key: ValueKey(current),
                      isExpanded: true,
                      initialValue: current,
                      decoration: const InputDecoration(labelText: '家庭照顾当前宠物'),
                      items: pets
                          .map(
                            (p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                '${p.name} · ${p.share_role == 'OWNER'
                                    ? '主人'
                                    : p.share_role == 'CAREGIVER'
                                    ? '共同照顾'
                                    : '仅查看'}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (id) {
                              setState(() {
                                current = id;
                                overview = null;
                              });
                              load();
                            },
                    ),
                  const SizedBox(height: 24),
                  if (detail != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              detail.pet.name,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '生日：${detail.pet.birth_date ?? '未填写'} · ${detail.pet.life_stage_unknown ? '年龄阶段信息不足' : '年龄阶段已记录'}',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '主人填写品种：${detail.pet.custom_breed_name ?? '未填写'}',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '忌口：${detail.pet.avoidance_notes.isEmpty ? '未记录' : detail.pet.avoidance_notes.join('、')}',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '过敏观察：${detail.pet.allergens.length}项，请以主人档案和可信诊断依据为准。',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '照顾任务（最近100项）',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if (canWrite)
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          PawdayButton(
                            onPressed: busy ? null : () => compose(true),
                            child: const Text('新增照顾任务'),
                          ),
                          PawdayButton(
                            onPressed: busy ? null : () => compose(false),
                            child: const Text('写照顾记录'),
                          ),
                        ],
                      ),
                    if (detail.tasks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('还没有任务，可以从今日喂食或散步开始。'),
                      ),
                    ...detail.tasks.map(
                      (t) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${t.due_on} · ${t.status == 'OPEN'
                                    ? '待完成'
                                    : t.status == 'DONE'
                                    ? '已完成'
                                    : '已取消'}',
                              ),
                              Text(
                                '创建人：${t.created_by}${t.completed_by == null ? '' : ' · 完成人：${t.completed_by}'}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (canWrite && t.status == 'OPEN')
                                Wrap(
                                  spacing: 12,
                                  children: [
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () async {
                                              if (await confirm(
                                                '完成照顾任务？',
                                                '请确认已经完成“${t.title}”。完成后保留来源记录。',
                                              )) {
                                                await write(
                                                  '/pets/$current/tasks/${t.id}/finish',
                                                  body: {'status': 'DONE'},
                                                  version: t.version,
                                                );
                                              }
                                            },
                                      child: const Text('标记完成'),
                                    ),
                                    if (owner ||
                                        t.created_by ==
                                            ref
                                                .read(authProvider)
                                                .principal
                                                ?.user_id)
                                      TextButton(
                                        onPressed: busy
                                            ? null
                                            : () async {
                                                if (await confirm(
                                                  '取消任务？',
                                                  '任务保留为已取消记录。',
                                                )) {
                                                  await write(
                                                    '/pets/$current/tasks/${t.id}/finish',
                                                    body: {
                                                      'status': 'CANCELLED',
                                                    },
                                                    version: t.version,
                                                  );
                                                }
                                              },
                                        child: const Text('取消任务'),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '日常记录（最近100项）',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (detail.entries.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('暂无照顾记录。记录一经保存将保留历史。'),
                      ),
                    ...detail.entries.map(
                      (e) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${e.recorded_on} · ${{'NOTE': '日常观察', 'FEEDING': '喂食', 'WALK': '散步', 'GROOMING': '清洁护理'}[e.kind]}',
                              ),
                              const SizedBox(height: 8),
                              Text(e.note),
                              const SizedBox(height: 8),
                              Text(
                                '记录人：${e.actor_user_id}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('照顾成员', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    ...detail.members
                        .where((m) => m.status == 'ACTIVE')
                        .map(
                          (m) => Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.user_id),
                                  Text(m.role == 'CAREGIVER' ? '共同照顾' : '仅查看'),
                                  if (owner)
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () async {
                                              if (await confirm(
                                                '撤销成员权限？',
                                                '撤销后立即失去共享访问，同时关闭尚未使用的邀请。',
                                              )) {
                                                await write(
                                                  '/pets/$current/members/${m.user_id}/revoke',
                                                  version: m.version,
                                                );
                                              }
                                            },
                                      child: const Text('撤销成员'),
                                    ),
                                  if (m.user_id ==
                                      ref.read(authProvider).principal?.user_id)
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () async {
                                              if (await confirm(
                                                '退出家庭照顾？',
                                                '退出后需新的邀请才能再次加入。',
                                              )) {
                                                await write(
                                                  '/pets/$current/leave',
                                                  version: m.version,
                                                );
                                              }
                                            },
                                      child: const Text('退出共享'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    if (owner) ...[
                      const SizedBox(height: 20),
                      Text(
                        '邀请记录（最近50项）',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      ...detail.invites.map(
                        (i) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${i.role == 'VIEWER' ? '仅查看' : '共同照顾'} · ${{'PENDING': '待接受', 'ACCEPTED': '已接受', 'REVOKED': '已撤销', 'EXPIRED': '已过期'}[i.status]}',
                                ),
                                Text('有效至 ${i.expires_at}'),
                                if (i.status == 'PENDING')
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () async {
                                            if (await confirm(
                                              '撤销邀请？',
                                              '该邀请将不能再被接受。',
                                            )) {
                                              await write(
                                                '/pets/$current/invites/${i.id}/revoke',
                                              );
                                            }
                                          },
                                    child: const Text('撤销邀请'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
