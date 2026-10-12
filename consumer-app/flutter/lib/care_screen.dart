import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api/generated/dto.dart';
import 'care_repository.dart';
import 'repositories.dart';
import 'pet_repository.dart';
import 'reference_ui.dart';

String careDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class PetFoodScreen extends ConsumerWidget {
  final String petId;
  const PetFoodScreen({super.key, required this.petId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(foodPlanProvider(petId));
    final pets = ref.watch(petsProvider).asData?.value ?? <Pet>[];
    final matches = pets.where((p) => p.id == petId);
    final name = matches.isEmpty ? '宠物' : matches.first.name;
    Future<void> edit(PetFoodPlan? existing) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FoodForm(petId: petId, existing: existing),
    );
    return Scaffold(
      appBar: AppBar(title: Text('$name的当前粮')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'FOOD JOURNAL',
                style: TextStyle(
                  letterSpacing: 2,
                  color: PawdayDesign.green,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '把补粮时间，记得更从容',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text('填写实际用量，估算余量与用完日期。多只宠物共用一袋时，请在这里填写该袋的总用量。'),
              const SizedBox(height: 24),
              plan.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Column(
                  children: [
                    Text(careError(e)),
                    TextButton(
                      onPressed: () => ref.invalidate(foodPlanProvider(petId)),
                      child: const Text('重新加载'),
                    ),
                  ],
                ),
                data: (p) => p == null || !p.active
                    ? Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.rice_bowl_outlined, size: 48),
                              const SizedBox(height: 16),
                              const Text('还没有正在记录的粮食'),
                              const SizedBox(height: 8),
                              const Text('开始记录后，可以随时校准余量或停止提醒。'),
                              const SizedBox(height: 20),
                              PawdayButton(
                                onPressed: () => edit(p),
                                child: const Text('记录当前粮'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.food_name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  const SizedBox(height: 24),
                                  Wrap(
                                    spacing: 40,
                                    runSpacing: 20,
                                    children: [
                                      _FoodMetric(
                                        '估算余量',
                                        '${p.estimated_remaining_g} 克',
                                      ),
                                      _FoodMetric(
                                        '预计用完',
                                        p.estimated_finish_on.replaceAll(
                                          '-',
                                          ' / ',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    '每日记录用量 ${p.daily_amount_g} 克 · 包装 ${p.package_weight_g} 克',
                                  ),
                                  const SizedBox(height: 8),
                                  Text('估算截至 ${p.estimate_as_of}'),
                                  const SizedBox(height: 16),
                                  Text(p.estimate_notice),
                                  const SizedBox(height: 16),
                                  Text(
                                    p.reminder_enabled
                                        ? '用完前 ${p.remind_before_days} 天提醒一次；校准后重新计算。'
                                        : '吃粮提醒已关闭',
                                  ),
                                  const SizedBox(height: 24),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      PawdayButton(
                                        onPressed: () => showDialog<void>(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (_) => FoodForm(
                                            petId: petId,
                                            existing: p,
                                            calibration: true,
                                          ),
                                        ),
                                        child: const Text('校准余量'),
                                      ),
                                      TextButton(
                                        onPressed: () => edit(p),
                                        child: const Text('更换粮食 / 调整记录'),
                                      ),
                                      TextButton(
                                        onPressed: () async {
                                          final ok = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('停止记录这袋粮？'),
                                              content: const Text(
                                                '保留已有记录，并停止后续补粮提醒。',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, false),
                                                  child: const Text('取消'),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, true),
                                                  child: const Text('停止记录'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (ok != true || !context.mounted) {
                                            return;
                                          }
                                          final session = ref
                                              .read(authProvider)
                                              .principal
                                              ?.session_id;
                                          try {
                                            await ref
                                                .read(careRepositoryProvider)
                                                .stop(p, careKey());
                                            if (context.mounted &&
                                                ref
                                                        .read(authProvider)
                                                        .principal
                                                        ?.session_id ==
                                                    session) {
                                              ref.invalidate(
                                                foodPlanProvider(petId),
                                              );
                                            }
                                          } catch (e) {
                                            if (context.mounted &&
                                                ref
                                                        .read(authProvider)
                                                        .principal
                                                        ?.session_id ==
                                                    session) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(careError(e)),
                                                ),
                                              );
                                            }
                                          }
                                        },
                                        child: const Text('停止记录'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text('先核对家中的余量，再确认是否补购。提醒不会自动下单或扣款。'),
                          const SizedBox(height: 16),
                          PawdayButton(
                            onPressed: () => context.push('/categories'),
                            child: const Text('去选购粮食'),
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

class _FoodMetric extends StatelessWidget {
  final String label, value;
  const _FoodMetric(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 8),
      Text(
        value,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: PawdayDesign.green,
        ),
      ),
    ],
  );
}

class FoodForm extends ConsumerStatefulWidget {
  final String petId;
  final PetFoodPlan? existing;
  final bool calibration;
  const FoodForm({
    super.key,
    required this.petId,
    this.existing,
    this.calibration = false,
  });
  @override
  ConsumerState<FoodForm> createState() => _FoodFormState();
}

class _FoodFormState extends ConsumerState<FoodForm> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      weight = TextEditingController(),
      daily = TextEditingController(),
      before = TextEditingController();
  late DateTime date;
  bool reminder = true, busy = false;
  String? error;
  String command = careKey();
  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    name.text = p?.food_name ?? '';
    weight.text = widget.calibration
        ? '${p?.estimated_remaining_g ?? 0}'
        : '${p?.package_weight_g ?? 1000}';
    daily.text = '${p?.daily_amount_g ?? 50}';
    before.text = '${p?.remind_before_days ?? 7}';
    reminder = p?.reminder_enabled ?? true;
    date = DateTime.now();
  }

  @override
  void dispose() {
    name.dispose();
    weight.dispose();
    daily.dispose();
    before.dispose();
    super.dispose();
  }

  String? grams(String? raw, int min, int max) {
    final n = int.tryParse(raw ?? '');
    return n == null || n < min || n > max ? '请输入 $min–$max 的整数' : null;
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    final session = ref.read(authProvider).principal?.session_id;
    if (session == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(careRepositoryProvider);
      if (widget.calibration) {
        await repo.calibrate(
          widget.existing!,
          int.parse(weight.text),
          careDate(date),
          command,
        );
      } else {
        await repo.start(
          widget.petId,
          PetFoodInput(
            sku_id: null,
            food_name: name.text.trim(),
            package_weight_g: int.parse(weight.text),
            daily_amount_g: int.parse(daily.text),
            started_on: careDate(date),
            reminder_enabled: reminder,
            remind_before_days: int.parse(before.text),
          ),
          widget.existing?.version ?? 0,
          command,
        );
      }
      if (!mounted || ref.read(authProvider).principal?.session_id != session) {
        return;
      }
      ref.invalidate(foodPlanProvider(widget.petId));
      Navigator.pop(context);
    } catch (e) {
      if (mounted && ref.read(authProvider).principal?.session_id == session) {
        setState(() {
          error = careError(e);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (a, b) {
      if (a?.principal?.session_id != b.principal?.session_id) {
        if (mounted) Navigator.pop(context);
      }
    });
    Widget number(TextEditingController c, String label, int min, int max) =>
        TextFormField(
          controller: c,
          enabled: !busy,
          decoration: InputDecoration(labelText: label),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (v) => grams(v, min, max),
          onChanged: (_) => command = careKey(),
        );
    return AlertDialog(
      title: Text(widget.calibration ? '校准实际余量' : '记录当前粮'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.calibration) ...[
                  TextFormField(
                    controller: name,
                    enabled: !busy,
                    maxLength: 160,
                    decoration: const InputDecoration(labelText: '粮食名称'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请填写粮食名称' : null,
                    onChanged: (_) => command = careKey(),
                  ),
                  const SizedBox(height: 20),
                ],
                number(
                  weight,
                  widget.calibration ? '实际剩余（克）' : '包装重量（克）',
                  widget.calibration ? 0 : 1,
                  widget.calibration
                      ? widget.existing!.package_weight_g
                      : 100000000,
                ),
                const SizedBox(height: 20),
                if (!widget.calibration) ...[
                  number(daily, '每日用量（克，由你填写）', 1, 1000000),
                  const SizedBox(height: 20),
                ],
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: date,
                            firstDate: widget.calibration
                                ? DateTime.parse(widget.existing!.baseline_on)
                                : DateTime(1900),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null && mounted) {
                            setState(() {
                              date = picked;
                              command = careKey();
                            });
                          }
                        },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    '${widget.calibration ? '校准日期' : '开始日期'}：${careDate(date).replaceAll('-', ' / ')}',
                  ),
                ),
                if (!widget.calibration) ...[
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('开启吃粮提醒'),
                    value: reminder,
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            reminder = v;
                            command = careKey();
                          }),
                  ),
                  const SizedBox(height: 12),
                  number(before, '预计用完前几天提醒', 0, 30),
                ],
                const SizedBox(height: 16),
                const Text('估算仅用于记录，不构成喂食建议。更换粮食会建立新的余量基线。'),
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
          child: Text(busy ? '保存中…' : '保存'),
        ),
      ],
    );
  }
}
