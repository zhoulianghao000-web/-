import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'pet_repository.dart';
import 'pet_profile_ui.dart';
import 'repositories.dart';
import 'reference_ui.dart';

String petError(Object error) {
  if (error is! ApiFailure) return '连接失败，请稍后重试。';
  if (error.code == 'CONCURRENT_MODIFICATION') return '档案已被更新，请刷新后重新编辑。';
  return switch (error.code) {
    'VALIDATION_ERROR' => '请检查日期、年龄和填写内容后重试。',
    'BREED_SPECIES_MISMATCH' => '品种与物种不匹配，请重新选择品种。',
    'UPLOAD_TOO_LARGE' => '照片不能超过 5 MiB，请选择较小的图片。',
    'UPLOAD_MIME_NOT_ALLOWED' => '请选择 JPG 或 PNG 图片。',
    'MEDIA_NOT_READY' => '照片尚未就绪，请重新上传。',
    'RESOURCE_NOT_FOUND' => '档案或照片不可用，请刷新后重试。',
    _ => '暂时无法保存，请稍后重试。',
  };
}

class PetsScreen extends ConsumerWidget {
  const PetsScreen({super.key});
  Future<void> edit(BuildContext context, WidgetRef ref, Pet? pet) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PetForm(existing: pet),
    );
  }

  Future<void> remove(BuildContext context, WidgetRef ref, Pet pet) async {
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
          PawdayButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(petRepositoryProvider).delete(pet, newPetCommandKey());
      ref.invalidate(petsProvider);
      if (ref.read(currentPetProvider)?.id == pet.id) {
        ref.read(currentPetProvider.notifier).clear();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(petError(e))));
      }
      ref.invalidate(petsProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(petsProvider),
        current = ref.watch(currentPetProvider);
    final species = ref.watch(taxonomyProvider).asData?.value ?? <Species>[];
    ref.listen(petsProvider, (_, next) {
      final owned = next.asData?.value, selected = ref.read(currentPetProvider);
      if (owned == null || selected == null) return;
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
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Padding(
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 600 ? 20 : 40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 24,
                    runSpacing: 16,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PET JOURNAL',
                            style: TextStyle(
                              letterSpacing: 2,
                              fontSize: 11,
                              color: PawdayDesign.green,
                            ),
                          ),
                          SizedBox(height: 10),
                          Text(
                            '我的宠物',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text('留住它的模样，也记下每一份了解。'),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '刷新',
                            onPressed: () => ref.invalidate(petsProvider),
                            icon: const Icon(Icons.refresh),
                          ),
                          if (result.asData?.value.isNotEmpty ?? false)
                            PawdayButton(
                              onPressed: () => edit(context, ref, null),
                              child: const Text('添加宠物'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PawdayButton(
                      onPressed: () => context.push('/household'),
                      child: const Text('家庭照顾'),
                    ),
                  ),
                  const SizedBox(height: 32),
                  result.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, s) => Column(
                      children: [
                        Text(petError(e)),
                        TextButton(
                          onPressed: () => ref.invalidate(petsProvider),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                    data: (pets) {
                      if (pets.isEmpty) {
                        return _PetWelcome(
                          onAdd: () => edit(context, ref, null),
                        );
                      }
                      return LayoutBuilder(
                        builder: (context, box) {
                          final columns = box.maxWidth >= 1000
                              ? 3
                              : box.maxWidth >= 680
                              ? 2
                              : 1;
                          final width =
                              (box.maxWidth - 24 * (columns - 1)) / columns;
                          return Wrap(
                            spacing: 24,
                            runSpacing: 24,
                            children: [
                              for (final pet in pets)
                                SizedBox(
                                  width: width,
                                  child: ReferenceHover(
                                    lift: 3,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(24),
                                      child: Column(
                                        children: [
                                          SizedBox(
                                            height: 268,
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                PetPhoto(
                                                  asset: pet.photo_asset_id,
                                                ),
                                                const DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      begin:
                                                          Alignment.topCenter,
                                                      end: Alignment
                                                          .bottomCenter,
                                                      colors: [
                                                        Color(0x55000000),
                                                        Color(0xcc18261e),
                                                        Color(0xf218261e),
                                                      ],
                                                      stops: [0, .38, 1],
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  top: 16,
                                                  right: 16,
                                                  child: current?.id == pet.id
                                                      ? const Chip(
                                                          avatar: Icon(
                                                            Icons.check,
                                                            size: 16,
                                                          ),
                                                          label: Text('当前宠物'),
                                                        )
                                                      : FilledButton.tonal(
                                                          onPressed: () {
                                                            final user = ref
                                                                .read(
                                                                  authProvider,
                                                                )
                                                                .principal
                                                                ?.user_id;
                                                            if (user == null) {
                                                              return;
                                                            }
                                                            final owned = pets
                                                                .map(
                                                                  (
                                                                    p,
                                                                  ) => PetContext(
                                                                    id: p.id,
                                                                    ownerUserId:
                                                                        user,
                                                                    name:
                                                                        p.name,
                                                                  ),
                                                                )
                                                                .toList();
                                                            ref
                                                                .read(
                                                                  currentPetProvider
                                                                      .notifier,
                                                                )
                                                                .select(
                                                                  owned.firstWhere(
                                                                    (p) =>
                                                                        p.id ==
                                                                        pet.id,
                                                                  ),
                                                                  owned,
                                                                );
                                                          },
                                                          child: const Text(
                                                            '设为当前',
                                                          ),
                                                        ),
                                                ),
                                                Positioned(
                                                  left: 24,
                                                  right: 24,
                                                  bottom: 24,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        pet.name,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 26,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        '${species.where((s) => s.id == pet.species_id).firstOrNull?.name ?? '宠物'} · ${petAgeLabel(pet)}',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                      if (pet.custom_breed_name !=
                                                              null ||
                                                          pet.breed_id != null)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                top: 6,
                                                              ),
                                                          child: Text(
                                                            pet.custom_breed_name ??
                                                                ref
                                                                    .watch(
                                                                      breedsProvider(
                                                                        pet.species_id,
                                                                      ),
                                                                    )
                                                                    .asData
                                                                    ?.value
                                                                    .where(
                                                                      (b) =>
                                                                          b.id ==
                                                                          pet.breed_id,
                                                                    )
                                                                    .firstOrNull
                                                                    ?.name ??
                                                                '已记录品种',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontSize: 13,
                                                                ),
                                                          ),
                                                        ),
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        pet.life_stage_unknown
                                                            ? '年龄阶段：信息不足'
                                                            : '年龄阶段已按档案规则记录',
                                                        style: const TextStyle(
                                                          color: Color(
                                                            0xffe1eadd,
                                                          ),
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            width: double.infinity,
                                            color: PawdayDesign.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            child: Wrap(
                                              alignment:
                                                  WrapAlignment.spaceBetween,
                                              spacing: 4,
                                              children: [
                                                TextButton(
                                                  onPressed: () =>
                                                      edit(context, ref, pet),
                                                  child: const Text('编辑档案'),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      showDialog<void>(
                                                        context: context,
                                                        builder: (_) =>
                                                            WeightDialog(
                                                              pet: pet,
                                                            ),
                                                      ),
                                                  child: const Text('体重记录'),
                                                ),
                                                TextButton(
                                                  onPressed: () => context.push(
                                                    '/pet-food?pet_id=${pet.id}',
                                                  ),
                                                  child: const Text('当前粮'),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      remove(context, ref, pet),
                                                  child: const Text('删除'),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  const Wrap(
                    spacing: 32,
                    runSpacing: 16,
                    children: [
                      _PetTip(
                        icon: Icons.badge_outlined,
                        title: '专属档案',
                        body: '名字、生日与日常忌口，随时补充。',
                      ),
                      _PetTip(
                        icon: Icons.monitor_weight_outlined,
                        title: '成长记录',
                        body: '记录体重变化，保留每一次观察。',
                      ),
                      _PetTip(
                        icon: Icons.tune,
                        title: '当前宠物',
                        body: '切换宠物后，按对应档案查看商品适配。',
                      ),
                    ],
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

class _PetWelcome extends StatelessWidget {
  final VoidCallback onAdd;
  const _PetWelcome({required this.onAdd});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final photo = ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.asset(
          'assets/reference/category-cat.jpg',
          height: 300,
          width: double.infinity,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
        ),
      );
      final text = Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '从认识它开始',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            const Text(
              '添加第一只宠物，记录属于它的照顾日常。',
              style: TextStyle(fontSize: 16, height: 1.7),
            ),
            const SizedBox(height: 12),
            const Text(
              '上传喜欢的照片，建立一张专属档案卡。\n不确定的生日、品种和过敏信息，可以暂时留空。',
              style: TextStyle(color: PawdayDesign.muted, height: 1.8),
            ),
            const SizedBox(height: 24),
            PawdayButton(onPressed: onAdd, child: const Text('添加宠物')),
          ],
        ),
      );
      return Container(
        decoration: BoxDecoration(
          color: PawdayDesign.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: PawdayDesign.line),
        ),
        padding: const EdgeInsets.all(12),
        child: box.maxWidth > 760
            ? Row(
                children: [
                  Expanded(child: photo),
                  Expanded(child: text),
                ],
              )
            : Column(children: [text, photo]),
      );
    },
  );
}

class _PetTip extends StatelessWidget {
  final IconData icon;
  final String title, body;
  const _PetTip({required this.icon, required this.title, required this.body});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 300,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: PawdayDesign.green),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                body,
                style: const TextStyle(color: PawdayDesign.muted, height: 1.6),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class PetForm extends ConsumerStatefulWidget {
  final Pet? existing;
  const PetForm({super.key, this.existing});
  @override
  ConsumerState<PetForm> createState() => _PetFormState();
}

class _PetFormState extends ConsumerState<PetForm> {
  late final TextEditingController name,
      birthday,
      years,
      months,
      notes,
      breedText;
  String? species, breed, photo;
  String ageMode = 'UNKNOWN', sex = 'UNKNOWN', neutered = 'UNKNOWN';
  List<Map<String, dynamic>> allergies = [];
  bool busy = false;
  String? error;
  Uint8List? preview;
  final Set<String> uploads = {};
  String commandKey = newPetCommandKey();
  String? lastPayload;
  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    name = TextEditingController(text: p?.name);
    birthday = TextEditingController(text: p?.birth_date);
    years = TextEditingController(
      text: p?.age_estimate_months == null
          ? ''
          : (p!.age_estimate_months! ~/ 12).toString(),
    );
    months = TextEditingController(
      text: p?.age_estimate_months == null
          ? ''
          : (p!.age_estimate_months! % 12).toString(),
    );
    notes = TextEditingController(text: p?.avoidance_notes?.join('\n'));
    breedText = TextEditingController(text: p?.custom_breed_name);
    species = p?.species_id;
    breed = p?.breed_id;
    photo = p?.photo_asset_id;
    ageMode = p?.birth_date != null
        ? 'BIRTHDAY'
        : p?.age_estimate_months != null
        ? 'ESTIMATE'
        : 'UNKNOWN';
    sex = p?.sex ?? 'UNKNOWN';
    neutered = p?.neutered_status ?? 'UNKNOWN';
    allergies = p?.allergens?.map((a) => a.toJson()).toList() ?? [];
  }

  @override
  void dispose() {
    for (final c in [name, birthday, years, months, notes, breedText]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> choosePhoto() async {
    if (busy) return;
    final session = ref.read(authProvider).principal?.session_id;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      if (await file.length() > 5242880) {
        throw const ApiFailure(413, 'UPLOAD_TOO_LARGE');
      }
      final ext = file.name.toLowerCase(),
          mime = ext.endsWith('.png')
              ? 'image/png'
              : ext.endsWith('.jpg') || ext.endsWith('.jpeg')
              ? 'image/jpeg'
              : '';
      if (mime.isEmpty) throw const ApiFailure(400, 'UPLOAD_MIME_NOT_ALLOWED');
      final bytes = await file.readAsBytes();
      if (!mounted || ref.read(authProvider).principal?.session_id != session) {
        return;
      }
      final asset = await ref
          .read(petRepositoryProvider)
          .uploadPhoto(bytes, mime);
      if (!mounted || ref.read(authProvider).principal?.session_id != session) {
        return;
      }
      setState(() {
        photo = asset.asset_id;
        uploads.add(photo!);
        preview = bytes;
      });
    } catch (e) {
      if (mounted) setState(() => error = petError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cleanup({String? keep}) async {
    final repo = ref.read(petRepositoryProvider);
    for (final id in uploads.where((id) => id != keep)) {
      try {
        await repo.discardPhoto(id);
      } catch (_) {
        /* Best effort; owned unreferenced resources remain manageable. */
      }
    }
  }

  Future<void> cancel() async {
    if (busy) return;
    setState(() => busy = true);
    await cleanup();
    if (mounted) Navigator.pop(context);
  }

  Future<void> save() async {
    if (busy) return;
    String? fail;
    String? dob;
    int? estimated;
    if (name.text.trim().isEmpty || species == null) {
      fail = '请填写名字并选择物种。';
    } else if (ageMode == 'BIRTHDAY' &&
        (dob = normalizePetBirthday(birthday.text)) == null) {
      fail = '请选择有效生日，或按 2026-01-02 格式填写，不能晚于今天。';
    } else if (ageMode == 'ESTIMATE') {
      final y = int.tryParse(
            years.text.trim().isEmpty ? '0' : years.text.trim(),
          ),
          m = int.tryParse(
            months.text.trim().isEmpty ? '0' : months.text.trim(),
          );
      if ((years.text.trim().isEmpty && months.text.trim().isEmpty) ||
          y == null ||
          m == null ||
          y < 0 ||
          m < 0 ||
          m > 11 ||
          y * 12 + m > 2400) {
        fail = '请填写估算年龄：年为 0–200，月为 0–11，总计不超过 200 年。';
      } else {
        estimated = y * 12 + m;
      }
    }
    if (fail != null) {
      setState(() => error = fail);
      return;
    }
    final label = breedText.text.trim();
    if (label.length > 80) {
      setState(() => error = '品种名称不能超过 80 个字符。');
      return;
    }
    final body = <String, dynamic>{
      'name': name.text.trim(),
      'species_id': species,
      'breed_id': breed,
      'custom_breed_name': breed == null && label.isNotEmpty ? label : null,
      'photo_asset_id': photo,
      'birth_date': dob,
      'age_estimate_months': estimated,
      'sex': sex,
      'neutered_status': neutered,
      'allergens': allergies,
      'avoidance_notes': notes.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    };
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
      await cleanup(keep: photo);
      ref.invalidate(petsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = petError(e));
      if (e is ApiFailure && e.versionConflict) ref.invalidate(petsProvider);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseBreed(List<Breed> items, String category) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => _BreedPicker(items: items, category: category),
    );
    if (selected == null || !mounted) return;
    final exact = items.where((b) => b.id == selected).firstOrNull;
    setState(() {
      breed = exact?.id;
      breedText.text =
          exact?.name ?? (selected == '__UNKNOWN__' ? '' : selected);
    });
  }

  Widget spaced(List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: 20),
        children[i],
      ],
    ],
  );
  Widget pair(Widget a, Widget b) => LayoutBuilder(
    builder: (c, box) => box.maxWidth >= 420
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 16),
              Expanded(child: b),
            ],
          )
        : spaced([a, b]),
  );
  @override
  Widget build(BuildContext context) {
    final taxonomy = ref.watch(taxonomyProvider),
        dictionary = ref.watch(allergenDictionaryProvider);
    final breeds = species == null ? null : ref.watch(breedsProvider(species!));
    final breedItems = breeds?.asData?.value ?? <Breed>[];
    final category =
        taxonomy.asData?.value
            .where((s) => s.id == species)
            .firstOrNull
            ?.category ??
        '';
    final breedName =
        breedItems.where((b) => b.id == breed).firstOrNull?.name ??
        (breed != null ? '已保存品种（可重新选择）' : breedText.text);
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text(widget.existing == null ? '添加宠物' : '编辑宠物档案'),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: spaced([
              ProfileSection(
                title: '01 · 基本信息',
                description: '先认识它。品种和照片可以稍后补充。',
                child: spaced([
                  TextField(
                    controller: name,
                    enabled: !busy,
                    maxLength: 160,
                    decoration: const InputDecoration(
                      labelText: '宠物名字',
                      hintText: '例如：小爪',
                      counterText: '',
                    ),
                  ),
                  taxonomy.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, s) => TextButton(
                      onPressed: () => ref.invalidate(taxonomyProvider),
                      child: const Text('分类加载失败，点击重试'),
                    ),
                    data: (items) => DropdownButtonFormField<String>(
                      initialValue: items.any((s) => s.id == species)
                          ? species
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '物种'),
                      items: items
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(s.name),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              species = v;
                              breed = null;
                              breedText.clear();
                            }),
                    ),
                  ),
                  if (species != null)
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => chooseBreed(breedItems, category),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(16),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '品种 / 细分种类（选填）',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: PawdayDesign.muted,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  breedName.isEmpty ? '搜索、选择或自行填写' : breedName,
                                  maxLines: 2,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.search),
                        ],
                      ),
                    ),
                  if (breeds?.hasError ?? false)
                    TextButton(
                      onPressed: () => ref.invalidate(breedsProvider(species!)),
                      child: const Text('平台品种加载失败，重试或自行填写'),
                    ),
                  const Text(
                    '自行填写的名称仅作档案备注，不作为品种鉴定或年龄阶段依据。',
                    style: TextStyle(
                      fontSize: 12,
                      color: PawdayDesign.muted,
                      height: 1.6,
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          width: 96,
                          height: 112,
                          child: preview == null
                              ? PetPhoto(asset: photo)
                              : Image.memory(preview!, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OutlinedButton(
                              onPressed: busy ? null : choosePhoto,
                              child: Text(photo == null ? '上传宠物照片' : '更换照片'),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'JPG / PNG · 最大 5 MiB\n照片仅用于你的宠物档案。',
                              style: TextStyle(
                                fontSize: 12,
                                color: PawdayDesign.muted,
                                height: 1.6,
                              ),
                            ),
                            if (photo != null)
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => setState(() {
                                        photo = null;
                                        preview = null;
                                      }),
                                child: const Text('移除照片'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ]),
              ),
              const Divider(height: 16),
              ProfileSection(
                title: '02 · 年龄与状态',
                description: '生日和估算年龄选一种；不确定时选“暂不填写”。',
                child: spaced([
                  DropdownButtonFormField<String>(
                    initialValue: ageMode,
                    decoration: const InputDecoration(labelText: '年龄记录方式'),
                    items: const [
                      DropdownMenuItem(value: 'UNKNOWN', child: Text('暂不填写')),
                      DropdownMenuItem(value: 'BIRTHDAY', child: Text('已知生日')),
                      DropdownMenuItem(value: 'ESTIMATE', child: Text('估算年龄')),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() => ageMode = v!),
                  ),
                  if (ageMode == 'BIRTHDAY')
                    TextField(
                      controller: birthday,
                      enabled: !busy,
                      keyboardType: TextInputType.datetime,
                      decoration: InputDecoration(
                        labelText: '生日',
                        hintText: '2026-01-02',
                        helperText: '可直接选择日期，也支持粘贴 2026 01 02。',
                        suffixIcon: IconButton(
                          tooltip: '选择生日',
                          onPressed: busy
                              ? null
                              : () async {
                                  final now = DateTime.now(),
                                      parsed = DateTime.tryParse(
                                        normalizePetBirthday(birthday.text) ??
                                            '',
                                      );
                                  final chosen = await showDatePicker(
                                    context: context,
                                    initialDate: parsed ?? now,
                                    firstDate: DateTime(1900),
                                    lastDate: now,
                                  );
                                  if (chosen != null && mounted) {
                                    setState(
                                      () => birthday.text = chosen
                                          .toIso8601String()
                                          .substring(0, 10),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.calendar_month_outlined),
                        ),
                      ),
                    ),
                  if (ageMode == 'ESTIMATE')
                    pair(
                      TextField(
                        controller: years,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: '年龄 · 年',
                          hintText: '0',
                        ),
                      ),
                      TextField(
                        controller: months,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: '年龄 · 月',
                          hintText: '0–11',
                        ),
                      ),
                    ),
                  pair(
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
                      onChanged: busy
                          ? null
                          : (v) => setState(() => neutered = v!),
                    ),
                  ),
                ]),
              ),
              const Divider(height: 16),
              ProfileSection(
                title: '03 · 过敏与忌口',
                description: '未知不代表无过敏。请区分主人观察与兽医诊断。',
                child: spaced([
                  dictionary.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, s) => TextButton(
                      onPressed: () =>
                          ref.invalidate(allergenDictionaryProvider),
                      child: const Text('过敏原词典加载失败，点击重试'),
                    ),
                    data: (items) => spaced([
                      for (final item in items)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: PawdayDesign.paper,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: spaced([
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            pair(
                              DropdownButtonFormField<String>(
                                initialValue:
                                    allergies
                                            .where(
                                              (a) =>
                                                  a['allergen_id'] == item.id,
                                            )
                                            .firstOrNull?['status']
                                        as String? ??
                                    'UNKNOWN',
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: '过敏状态',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'UNKNOWN',
                                    child: Text('未知'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'YES',
                                    child: Text('有过敏'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'NO',
                                    child: Text('明确无'),
                                  ),
                                ],
                                onChanged: busy
                                    ? null
                                    : (v) => allergy(item.id, 'status', v!),
                              ),
                              DropdownButtonFormField<String>(
                                initialValue:
                                    allergies
                                            .where(
                                              (a) =>
                                                  a['allergen_id'] == item.id,
                                            )
                                            .firstOrNull?['source']
                                        as String? ??
                                    'OWNER_OBSERVATION',
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: '信息来源',
                                ),
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
                                    : (v) => allergy(item.id, 'source', v!),
                              ),
                            ),
                          ]),
                        ),
                      if (items.isEmpty)
                        const Text(
                          '暂无平台已维护的过敏原；空列表表示尚未记录。',
                          style: TextStyle(color: PawdayDesign.muted),
                        ),
                    ]),
                  ),
                  TextField(
                    controller: notes,
                    enabled: !busy,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: '忌口与照顾备注',
                      hintText: '每行记录一条，例如：避免某种食物。',
                      alignLabelWithHint: true,
                    ),
                  ),
                ]),
              ),
              if (error != null)
                Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xffffeee8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: Color(0xff9c3725),
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        actions: [
          TextButton(onPressed: busy ? null : cancel, child: const Text('取消')),
          PawdayButton(
            onPressed: busy ? null : save,
            child: Text(busy ? '处理中…' : '保存'),
          ),
        ],
      ),
    );
  }

  void allergy(String id, String field, String value) => setState(() {
    final old = allergies.where((a) => a['allergen_id'] == id).firstOrNull;
    allergies.removeWhere((a) => a['allergen_id'] == id);
    allergies.add({
      'allergen_id': id,
      'status': 'UNKNOWN',
      'source': 'OWNER_OBSERVATION',
      ...?old,
      field: value,
    });
  });
}

class _BreedPicker extends StatefulWidget {
  final List<Breed> items;
  final String category;
  const _BreedPicker({required this.items, required this.category});
  @override
  State<_BreedPicker> createState() => _BreedPickerState();
}

class _BreedPickerState extends State<_BreedPicker> {
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = search.text.trim(),
        official = widget.items
            .where((b) => b.name.toLowerCase().contains(q.toLowerCase()))
            .toList(),
        suggestions = (ownerBreedSuggestions[widget.category] ?? []).where(
          (s) => s.contains(q) && !widget.items.any((b) => b.name == s),
        );
    return AlertDialog(
      title: const Text('选择品种 / 细分种类'),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: search,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: '搜索或填写名称',
                prefixIcon: Icon(Icons.search),
                counterText: '',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    title: const Text('未知 / 暂不填写'),
                    onTap: () => Navigator.pop(context, '__UNKNOWN__'),
                  ),
                  for (final b in official)
                    ListTile(
                      title: Text(b.name),
                      subtitle: const Text('平台品种词典'),
                      onTap: () => Navigator.pop(context, b.id),
                    ),
                  for (final s in suggestions)
                    ListTile(
                      title: Text(s),
                      subtitle: const Text('常见名称 · 按主人填写保存'),
                      onTap: () => Navigator.pop(context, s),
                    ),
                  if (q.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: Text('使用“$q”'),
                      subtitle: const Text('自行填写 · 未经鉴定'),
                      onTap: () => Navigator.pop(context, q),
                    ),
                  if (official.isEmpty && suggestions.isEmpty && q.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('暂无可选名称，可以在上方自行填写。'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回'),
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
        PawdayButton(onPressed: busy ? null : save, child: const Text('记录体重')),
      ],
    );
  }
}
