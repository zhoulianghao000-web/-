import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api/generated/dto.dart';
import 'api/client.dart';
import 'catalog_repository.dart';
import 'repositories.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});
  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final query = TextEditingController();
  final List<ConsumerProduct> items = [];
  final Set<String> selected = {};
  String? category, cursor, error;
  bool loading = false, hasMore = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    Future.microtask(() => load(reset: true));
  }

  @override
  void dispose() {
    generation++;
    query.dispose();
    super.dispose();
  }

  Future<void> load({bool reset = false}) async {
    final epoch = ++generation;
    setState(() {
      loading = true;
      error = null;
      if (reset) {
        items.clear();
        selected.clear();
        cursor = null;
      }
    });
    try {
      final page = await ref
          .read(catalogRepositoryProvider)
          .browse(category: category, cursor: cursor, query: query.text.trim());
      if (!mounted || epoch != generation) return;
      setState(() {
        items.addAll(page.data);
        cursor = page.page.next_cursor;
        hasMore = page.page.has_more;
      });
    } catch (e) {
      if (mounted && epoch == generation) setState(() => error = e.toString());
    } finally {
      if (mounted && epoch == generation) setState(() => loading = false);
    }
  }

  Future<void> compare() async {
    if (ref.read(authProvider).principal == null) {
      context.go('/auth/login?returnTo=%2Fcategories');
      return;
    }
    final pet = ref.read(currentPetProvider),
        user = ref.read(authProvider).principal?.user_id;
    setState(() => loading = true);
    try {
      final result = await ref
          .read(catalogRepositoryProvider)
          .compare(selected.toList(), pet?.id);
      if (!mounted ||
          user != ref.read(authProvider).principal?.user_id ||
          pet?.id != ref.read(currentPetProvider)?.id) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('标准与适配对比'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in result.items) ...[
                    Text(
                      '${item.standard.name} · ${item.standard.sku_code}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('配料：${item.standard.ingredients.join('、')}'),
                    Text('来源：${item.standard.source_refs.join('；')}'),
                    Text('适配：${item.fit?.display_label ?? '未选择宠物，不生成适配结论'}'),
                    if (item.fit != null)
                      Text(
                        item.fit!.hard_conflicts
                            .map((x) => x.message)
                            .join('；'),
                      ),
                    const Divider(),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (before, after) {
      if (before?.principal?.user_id != after.principal?.user_id) {
        selected.clear();
      }
    });
    return Scaffold(
      appBar: AppBar(title: const Text('商品与适配')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: query,
            decoration: const InputDecoration(labelText: '商品名、品牌或 SKU'),
            onSubmitted: loading ? null : (_) => load(reset: true),
          ),
          DropdownButton<String>(
            value: category,
            hint: const Text('全部宠物分类'),
            items: [
              const DropdownMenuItem<String>(value: null, child: Text('全部')),
              ...{
                'CAT': '猫',
                'DOG': '狗',
                'AQUATIC': '水族',
                'BIRD': '鸟',
                'SMALL_PET': '小宠',
              }.entries.map(
                (x) => DropdownMenuItem(value: x.key, child: Text(x.value)),
              ),
            ],
            onChanged: loading
                ? null
                : (v) {
                    category = v;
                    load(reset: true);
                  },
          ),
          FilledButton(
            onPressed: loading ? null : () => load(reset: true),
            child: const Text('查询 / 刷新'),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (loading) const LinearProgressIndicator(),
          if (!loading && items.isEmpty) const Text('本页暂无符合条件的在售商品，可继续翻页或刷新。'),
          for (final item in items)
            Card(
              child: ListTile(
                title: Text(item.name),
                subtitle: Text(
                  '${item.brand} · ${item.sku_code}\n¥${(item.offers.map((x) => x.sale_price_fen).reduce((a, b) => a < b ? a : b) / 100).toStringAsFixed(2)} 起',
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ProductScreen(sku: item.id),
                  ),
                ),
                trailing: Checkbox(
                  value: selected.contains(item.id),
                  onChanged: loading
                      ? null
                      : (value) => setState(() {
                          if (value == true && selected.length < 4) {
                            selected.add(item.id);
                          } else {
                            selected.remove(item.id);
                          }
                        }),
                ),
              ),
            ),
          if (hasMore)
            OutlinedButton(
              onPressed: loading ? null : () => load(),
              child: const Text('下一页'),
            ),
          OutlinedButton(
            onPressed: !loading && selected.length >= 2 ? compare : null,
            child: Text('比较已选商品（${selected.length}/4）'),
          ),
          const Text('适配依据平台来源与宠物档案；商品报价中的运费、优惠与结账实付待确认。'),
        ],
      ),
    );
  }
}

class ProductScreen extends ConsumerStatefulWidget {
  final String sku;
  const ProductScreen({super.key, required this.sku});
  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  ConsumerStandard? standard;
  List<ConsumerOffer> offers = [];
  ProductFit? fit;
  String? error;
  bool loading = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<void> load() async {
    final epoch = ++generation,
        pet = ref.read(currentPetProvider),
        user = ref.read(authProvider).principal?.user_id;
    setState(() {
      loading = true;
      fit = null;
      standard = null;
      offers = [];
      error = null;
    });
    try {
      final repo = ref.read(catalogRepositoryProvider),
          s = await repo.standard(widget.sku),
          o = await repo.offers(widget.sku);
      final f = pet != null && user != null
          ? await repo.fit(widget.sku, pet.id)
          : null;
      if (!mounted ||
          epoch != generation ||
          pet?.id != ref.read(currentPetProvider)?.id ||
          user != ref.read(authProvider).principal?.user_id) {
        return;
      }
      if (f != null &&
          f.catalog_standard_version_id != s.catalog_standard_version_id) {
        throw const ApiFailure(409, 'STANDARD_CHANGED_REFRESH_REQUIRED');
      }
      setState(() {
        standard = s;
        offers = o;
        fit = f;
      });
    } catch (e) {
      if (mounted && epoch == generation) setState(() => error = e.toString());
    } finally {
      if (mounted && epoch == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentPetProvider, (_, _) => Future.microtask(load));
    ref.listen(authProvider, (a, b) {
      if (a?.principal?.user_id != b.principal?.user_id) Future.microtask(load);
    });
    final s = standard;
    return Scaffold(
      appBar: AppBar(title: const Text('商品详情')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (loading) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          if (s != null) ...[
            Text(s.name, style: Theme.of(context).textTheme.headlineSmall),
            Text('${s.brand} · ${s.sku_code} · ${s.weight_g}g'),
            Text('配料：${s.ingredients.join('、')}'),
            Text(
              '过敏原：${!s.allergens_known
                  ? '资料未知'
                  : s.allergens.isEmpty
                  ? '来源未声明过敏原'
                  : s.allergens.map((x) => x.name).join('、')}',
            ),
            for (final n in s.nutrients)
              Text(
                '${n.name} ${n.value_milli / 1000} ${n.unit} · ${n.basis} · ${n.qualifier}',
              ),
            Text('来源更新时间：${s.source_updated_on}'),
            for (final source in s.source_refs) SelectableText(source),
            const Divider(),
            Text(fit?.display_label ?? '选择自己的宠物后查看适配'),
            if (fit != null) ...[
              for (final c in fit!.hard_conflicts)
                Text(
                  c.message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              for (final u in fit!.uncertainties) Text(uncertaintyLabel(u)),
              Text('结论依据当前宠物档案和平台商品资料'),
            ],
            const Divider(),
            const Text('当前在售商家报价'),
            if (offers.isEmpty) const Text('暂无在售报价'),
            for (final o in offers)
              Card(
                child: ListTile(
                  title: Text(o.merchant_name),
                  subtitle: Text(
                    '¥${(o.sale_price_fen / 100).toStringAsFixed(2)} · ${o.in_stock ? '有库存' : '缺货'}\n${o.fulfillment_sla}',
                  ),
                ),
              ),
            const Text('报价不含尚未确认的运费与优惠。'),
          ],
          OutlinedButton(
            onPressed: loading ? null : load,
            child: const Text('刷新当前数据'),
          ),
        ],
      ),
    );
  }
}

String uncertaintyLabel(String code) =>
    const {
      'PRODUCT_ALLERGENS_UNKNOWN': '商品过敏原资料未知',
      'PET_ALLERGIES_UNKNOWN': '宠物过敏情况尚未完成评估',
      'PET_ALLERGEN_ASSESSMENT_INCOMPLETE': '部分商品过敏原尚未评估',
      'LIFE_STAGE_INSUFFICIENT': '缺少可靠年龄或商品适用阶段资料',
      'PRODUCT_LIFE_STAGE_EVIDENCE_STALE_OR_OTHER_SPECIES': '商品年龄阶段资料需要重新核对',
      'AVOIDANCE_NOTES_REQUIRE_REVIEW': '档案中有忌口说明，需要人工核对',
    }[code] ??
    '资料需要进一步核对';
