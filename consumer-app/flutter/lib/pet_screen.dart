import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'pet_repository.dart';
import 'repositories.dart';

String petError(Object error) => error is ApiFailure && error.versionConflict
    ? '档案已被更新，请刷新后重新编辑。'
    : error is ApiFailure
    ? '操作失败：$error'
    : '连接失败，请稍后重试。';

class PetsScreen extends ConsumerWidget {
  const PetsScreen({super.key});
  Future<void> edit(BuildContext context, WidgetRef ref, Pet? pet) async {
    await showDialog<void>(
      context: context,
      builder: (_) => PetForm(existing: pet),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(petsProvider),
        current = ref.watch(currentPetProvider);
    ref.listen(petsProvider, (_, next) {
      final owned = next.asData?.value;
      if (owned == null) return;
      final selected = ref.read(currentPetProvider);
      if (selected == null) return;
      final user = ref.read(authProvider).principal?.user_id;
      if (user == null || !owned.any((p) => p.id == selected.id)) {
        ref.read(currentPetProvider.notifier).clear();
      } else {
        final contexts = owned
            .map((p) => PetContext(id: p.id, ownerUserId: user, name: p.name))
            .toList();
        ref
            .read(currentPetProvider.notifier)
            .select(contexts.firstWhere((p) => p.id == selected.id), contexts);
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的宠物'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => ref.invalidate(petsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('添加宠物'),
      ),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(petError(e)),
              TextButton(
                onPressed: () => ref.invalidate(petsProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (pets) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          children: [
            if (pets.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('添加第一只宠物，记录属于它的照顾日常。'),
              ),
            for (final pet in pets)
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.pets),
                      title: Text(pet.name),
                      subtitle: Text(
                        pet.life_stage_unknown ? '年龄阶段：信息不足' : '已有可信年龄阶段规则',
                      ),
                      trailing: current?.id == pet.id
                          ? const Chip(label: Text('当前宠物'))
                          : TextButton(
                              onPressed: () {
                                final user = ref
                                    .read(authProvider)
                                    .principal
                                    ?.user_id;
                                if (user == null) return;
                                final owned = pets
                                    .map(
                                      (p) => PetContext(
                                        id: p.id,
                                        ownerUserId: user,
                                        name: p.name,
                                      ),
                                    )
                                    .toList();
                                ref
                                    .read(currentPetProvider.notifier)
                                    .select(
                                      owned.firstWhere((p) => p.id == pet.id),
                                      owned,
                                    );
                              },
                              child: const Text('设为当前'),
                            ),
                    ),
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: () => edit(context, ref, pet),
                          child: const Text('编辑档案'),
                        ),
                        TextButton(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => WeightDialog(pet: pet),
                          ),
                          child: const Text('体重记录'),
                        ),
                        TextButton(
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text('删除 ${pet.name} 的档案？'),
                                content: const Text('删除后将从你的宠物列表移除。'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('取消'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('确认删除'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                            try {
                              await ref
                                  .read(petRepositoryProvider)
                                  .delete(pet, newPetCommandKey());
                              ref.invalidate(petsProvider);
                              if (ref.read(currentPetProvider)?.id == pet.id) {
                                ref.read(currentPetProvider.notifier).clear();
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(petError(e))),
                                );
                              }
                              ref.invalidate(petsProvider);
                            }
                          },
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PetForm extends ConsumerStatefulWidget {
  final Pet? existing;
  const PetForm({super.key, this.existing});
  @override
  ConsumerState<PetForm> createState() => _PetFormState();
}

class _PetFormState extends ConsumerState<PetForm> {
  late final TextEditingController name, birthday, estimate, notes;
  String? species, breed;
  String sex = 'UNKNOWN', neutered = 'UNKNOWN';
  List<Map<String, dynamic>> allergies = [];
  bool busy = false;
  String? error;
  String commandKey = newPetCommandKey();
  String? lastPayload;
  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    name = TextEditingController(text: p?.name);
    birthday = TextEditingController(text: p?.birth_date);
    estimate = TextEditingController(text: p?.age_estimate_months?.toString());
    notes = TextEditingController(text: p?.avoidance_notes?.join('\n'));
    species = p?.species_id;
    breed = p?.breed_id;
    sex = p?.sex ?? 'UNKNOWN';
    neutered = p?.neutered_status ?? 'UNKNOWN';
    allergies = p?.allergens?.map((a) => a.toJson()).toList() ?? [];
  }

  @override
  void dispose() {
    for (final c in [name, birthday, estimate, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    if (name.text.trim().isEmpty || species == null) {
      setState(() => error = '请填写名字并选择物种。');
      return;
    }
    if (birthday.text.isNotEmpty && estimate.text.isNotEmpty) {
      setState(() => error = '生日与估算年龄请选择一种填写。');
      return;
    }
    final months = estimate.text.isEmpty ? null : int.tryParse(estimate.text);
    if (estimate.text.isNotEmpty && (months == null || months < 0)) {
      setState(() => error = '估算年龄须为非负整数月。');
      return;
    }
    final body = <String, dynamic>{
      'name': name.text.trim(),
      'species_id': species,
      'breed_id': breed,
      'birth_date': birthday.text.isEmpty ? null : birthday.text,
      'age_estimate_months': months,
      'sex': sex,
      'neutered_status': neutered,
      'allergens': allergies,
      'avoidance_notes': notes.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    };
    // Preserve a retry's command key; editing the payload starts a new command.
    final fingerprint = body.toString();
    if (lastPayload != fingerprint) {
      commandKey = newPetCommandKey();
      lastPayload = fingerprint;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(petRepositoryProvider)
          .save(body, existing: widget.existing, key: commandKey);
      ref.invalidate(petsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = petError(e));
      if (e is ApiFailure && e.versionConflict) ref.invalidate(petsProvider);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final taxonomy = ref.watch(taxonomyProvider),
        dictionary = ref.watch(allergenDictionaryProvider);
    final breeds = species == null ? null : ref.watch(breedsProvider(species!));
    return AlertDialog(
      title: Text(widget.existing == null ? '添加宠物' : '编辑宠物档案'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                enabled: !busy,
                maxLength: 160,
                decoration: const InputDecoration(labelText: '宠物名字'),
              ),
              taxonomy.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => TextButton(
                  onPressed: () => ref.invalidate(taxonomyProvider),
                  child: const Text('分类加载失败，点击重试'),
                ),
                data: (items) => DropdownButtonFormField<String>(
                  initialValue: items.any((s) => s.id == species)
                      ? species
                      : null,
                  decoration: const InputDecoration(labelText: '物种'),
                  items: items
                      .map(
                        (s) =>
                            DropdownMenuItem(value: s.id, child: Text(s.name)),
                      )
                      .toList(),
                  onChanged: busy
                      ? null
                      : (value) => setState(() {
                          species = value;
                          breed = null;
                        }),
                ),
              ),
              if (breeds != null)
                breeds.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => TextButton(
                    onPressed: () => ref.invalidate(breedsProvider(species!)),
                    child: const Text('品种加载失败，点击重试'),
                  ),
                  data: (items) => DropdownButtonFormField<String>(
                    key: ValueKey(species),
                    initialValue: items.any((b) => b.id == breed)
                        ? breed
                        : null,
                    decoration: const InputDecoration(labelText: '品种（可留空）'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('未知 / 不填写'),
                      ),
                      ...items.map(
                        (b) =>
                            DropdownMenuItem(value: b.id, child: Text(b.name)),
                      ),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() => breed = v == '' ? null : v),
                  ),
                ),
              TextField(
                controller: birthday,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: '生日（YYYY-MM-DD，可留空）',
                ),
              ),
              TextField(
                controller: estimate,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '或估算年龄（月）'),
              ),
              DropdownButtonFormField<String>(
                initialValue: sex,
                decoration: const InputDecoration(labelText: '性别'),
                items: const [
                  DropdownMenuItem(value: 'UNKNOWN', child: Text('未知')),
                  DropdownMenuItem(value: 'MALE', child: Text('雄性')),
                  DropdownMenuItem(value: 'FEMALE', child: Text('雌性')),
                ],
                onChanged: busy ? null : (v) => setState(() => sex = v!),
              ),
              DropdownButtonFormField<String>(
                initialValue: neutered,
                decoration: const InputDecoration(labelText: '绝育状态'),
                items: const [
                  DropdownMenuItem(value: 'UNKNOWN', child: Text('未知')),
                  DropdownMenuItem(value: 'YES', child: Text('已绝育')),
                  DropdownMenuItem(value: 'NO', child: Text('未绝育')),
                ],
                onChanged: busy ? null : (v) => setState(() => neutered = v!),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('过敏信息未知不代表无过敏；主人观察与兽医诊断分别记录。'),
              ),
              dictionary.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => TextButton(
                  onPressed: () => ref.invalidate(allergenDictionaryProvider),
                  child: const Text('过敏原词典加载失败，点击重试'),
                ),
                data: (items) => Column(
                  children: [
                    for (final item in items)
                      Row(
                        children: [
                          Expanded(child: Text(item.name)),
                          DropdownButton<String>(
                            value:
                                allergies
                                        .where(
                                          (a) => a['allergen_id'] == item.id,
                                        )
                                        .firstOrNull?['status']
                                    as String? ??
                                'UNKNOWN',
                            items: const [
                              DropdownMenuItem(
                                value: 'UNKNOWN',
                                child: Text('未知'),
                              ),
                              DropdownMenuItem(value: 'YES', child: Text('有')),
                              DropdownMenuItem(value: 'NO', child: Text('明确无')),
                            ],
                            onChanged: busy
                                ? null
                                : (v) => setState(() {
                                    final old = allergies
                                        .where(
                                          (a) => a['allergen_id'] == item.id,
                                        )
                                        .firstOrNull;
                                    allergies.removeWhere(
                                      (a) => a['allergen_id'] == item.id,
                                    );
                                    allergies.add({
                                      ...?old,
                                      'allergen_id': item.id,
                                      'status': v,
                                      'source':
                                          old?['source'] ?? 'OWNER_OBSERVATION',
                                    });
                                  }),
                          ),
                          DropdownButton<String>(
                            value:
                                allergies
                                        .where(
                                          (a) => a['allergen_id'] == item.id,
                                        )
                                        .firstOrNull?['source']
                                    as String? ??
                                'OWNER_OBSERVATION',
                            items: const [
                              DropdownMenuItem(
                                value: 'OWNER_OBSERVATION',
                                child: Text('主人观察'),
                              ),
                              DropdownMenuItem(
                                value: 'VET_DIAGNOSIS',
                                child: Text('兽医诊断'),
                              ),
                            ],
                            onChanged: busy
                                ? null
                                : (v) => setState(() {
                                    final old = allergies
                                        .where(
                                          (a) => a['allergen_id'] == item.id,
                                        )
                                        .firstOrNull;
                                    allergies.removeWhere(
                                      (a) => a['allergen_id'] == item.id,
                                    );
                                    allergies.add({
                                      ...?old,
                                      'allergen_id': item.id,
                                      'status': old?['status'] ?? 'UNKNOWN',
                                      'source': v,
                                    });
                                  }),
                          ),
                        ],
                      ),
                    if (items.isEmpty) const Text('暂无平台已维护的过敏原；空列表表示尚未记录。'),
                  ],
                ),
              ),
              TextField(
                controller: notes,
                enabled: !busy,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '忌口备注（每行一条）'),
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? '保存中…' : '保存'),
        ),
      ],
    );
  }
}

class WeightDialog extends ConsumerStatefulWidget {
  final Pet pet;
  const WeightDialog({super.key, required this.pet});
  @override
  ConsumerState<WeightDialog> createState() => _WeightDialogState();
}

class _WeightDialogState extends ConsumerState<WeightDialog> {
  final grams = TextEditingController(),
      date = TextEditingController(
        text: DateTime.now().toIso8601String().substring(0, 10),
      );
  bool busy = false;
  String? error;
  String keyValue = newPetCommandKey(), fingerprint = '';
  @override
  void dispose() {
    grams.dispose();
    date.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final value = int.tryParse(grams.text);
    if (value == null || value <= 0) {
      setState(() => error = '请输入正整数克数。');
      return;
    }
    if (busy) return;
    final next = '$value:${date.text}';
    if (next != fingerprint) {
      keyValue = newPetCommandKey();
      fingerprint = next;
    }
    setState(() => busy = true);
    try {
      await ref
          .read(petRepositoryProvider)
          .recordWeight(widget.pet, value, date.text, keyValue);
      ref.invalidate(petsProvider);
      ref.invalidate(weightsProvider(widget.pet));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = petError(e));
      ref.invalidate(petsProvider);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(weightsProvider(widget.pet));
    return AlertDialog(
      title: Text('${widget.pet.name} · 体重'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: grams,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '体重（克）'),
              ),
              TextField(
                controller: date,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: '记录日期（YYYY-MM-DD）',
                ),
              ),
              const Text('新增记录来源：主人观察'),
              if (error != null) Text(error!),
              history.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => TextButton(
                  onPressed: () => ref.invalidate(weightsProvider(widget.pet)),
                  child: const Text('历史加载失败，点击重试'),
                ),
                data: (rows) => Column(
                  children: [
                    for (final row in rows)
                      ListTile(
                        title: Text('${row.weight_g} 克'),
                        subtitle: Text(
                          '${row.recorded_on} · ${row.source == 'VET_DIAGNOSIS' ? '兽医诊断' : '主人观察'}',
                        ),
                      ),
                    if (rows.isEmpty) const Text('还没有体重记录。'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton(onPressed: busy ? null : save, child: const Text('记录体重')),
      ],
    );
  }
}
