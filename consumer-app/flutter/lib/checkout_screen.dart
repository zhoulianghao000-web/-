import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/generated/dto.dart';
import 'checkout_repository.dart';
import 'repositories.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});
  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  Cart? cart;
  List<CheckoutAddress> addresses = [];
  final Set<String> selected = {};
  String? address, error;
  PricingQuote? quote;
  CheckoutBenefits? benefits;
  final Set<String> coupons = {};
  bool membership = false;
  bool busy = false;
  int generation = 0;
  int quoteNonce = 0;
  Timer? expiry;
  final Map<String, String> keys = {};
  String? get user => ref.read(authProvider).principal?.user_id;
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void dispose() {
    generation++;
    expiry?.cancel();
    super.dispose();
  }

  String key(Object payload) =>
      keys.putIfAbsent(jsonEncode(payload), checkoutCommandKey);
  Future<void> load() async {
    final epoch = ++generation, owner = user;
    if (owner == null) return;
    setState(() {
      busy = true;
      error = null;
      quote = null;
    });
    expiry?.cancel();
    bool valid() => mounted && epoch == generation && owner == user;
    try {
      ref.read(guestCartProvider.notifier).begin(owner);
      final intent = ref.read(guestCartProvider);
      if (intent.items.isNotEmpty) {
        await ref
            .read(checkoutRepositoryProvider)
            .merge(intent.items, intent.key);
        if (!valid()) return;
        ref.read(guestCartProvider.notifier).clear();
      }
      final c = await ref.read(checkoutRepositoryProvider).cart();
      final a = await ref.read(checkoutRepositoryProvider).addresses();
      final availableBenefits = await ref
          .read(checkoutRepositoryProvider)
          .benefits();
      if (valid()) {
        setState(() {
          benefits = availableBenefits;
          coupons.removeWhere(
            (id) => !availableBenefits.coupons.any((c) => c.id == id),
          );
          if (!availableBenefits.membership_eligible) membership = false;
          cart = c;
          addresses = a;
          selected.removeWhere((id) => !c.items.any((i) => i.id == id));
          if (!a.any((i) => i.id == address)) {
            address = a.isEmpty ? null : a.first.id;
          }
        });
      }
    } catch (e) {
      if (valid()) setState(() => error = checkoutError(e));
    } finally {
      if (valid()) setState(() => busy = false);
    }
  }

  Future<void> command(Future<void> Function() work) async {
    if (busy) return;
    final owner = user, epoch = generation;
    setState(() {
      busy = true;
      error = null;
      quote = null;
    });
    expiry?.cancel();
    try {
      await work();
      if (mounted && owner == user && epoch == generation) await load();
    } catch (e) {
      if (mounted && owner == user && epoch == generation) {
        setState(() => error = checkoutError(e));
      }
    } finally {
      if (mounted && owner == user) setState(() => busy = false);
    }
  }

  Future<void> price() async {
    if (busy || selected.isEmpty || address == null) return;
    final owner = user, epoch = ++generation, ids = selected.toList()..sort();
    setState(() {
      busy = true;
      error = null;
      quote = null;
    });
    expiry?.cancel();
    try {
      final q = await ref
          .read(checkoutRepositoryProvider)
          .quote(
            ids,
            address!,
            key({
              'items': ids,
              'address': address,
              'cart_version': cart?.version,
              'quote_nonce': quoteNonce,
              'coupons': coupons.toList()..sort(),
              'membership': membership,
            }),
            coupons: coupons.toList()..sort(),
            membership: membership,
          );
      if (mounted && owner == user && epoch == generation) {
        setState(() {
          quote = q;
          quoteNonce++;
        });
        final duration = DateTime.parse(q.expires_at)
            .difference(DateTime.now());
        expiry = Timer(duration.isNegative ? Duration.zero : duration, () {
          if (mounted && owner == user && epoch == generation) {
            setState(() => quote = null);
          }
        });
      }
    } catch (e) {
      if (mounted && owner == user && epoch == generation) {
        setState(() => error = checkoutError(e));
      }
    } finally {
      if (mounted && owner == user && epoch == generation) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> verifyQuote() async {
    final current = quote;
    if (current == null || busy) return;
    final owner = user, epoch = generation;
    setState(() => busy = true);
    try {
      final q = await ref
          .read(checkoutRepositoryProvider)
          .getQuote(current.quote_id);
      if (mounted && owner == user && epoch == generation) {
        setState(() {
          quote = q;
          error = q.status == 'ACTIVE' ? null : '试算已失效，请重新试算并确认';
        });
      }
    } catch (e) {
      if (mounted && owner == user && epoch == generation) {
        setState(() => error = checkoutError(e));
      }
    } finally {
      if (mounted && owner == user && epoch == generation) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> editAddress([CheckoutAddress? previous]) async {
    final owner = user;
    final values = [
      previous?.recipient ?? '',
      previous?.phone ?? '',
      previous?.province_code ?? '',
      previous?.city_code ?? '',
      previous?.district_code ?? '',
      previous?.detail ?? '',
    ].map((text) => TextEditingController(text: text)).toList();
    String? province = previous?.province_code;
    final form = GlobalKey<FormState>();
    final result = await showDialog<CheckoutAddressInput>(
      context: context,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          if (ref.watch(authProvider).principal?.user_id != owner) {
            return AlertDialog(
              title: const Text('登录状态已变化'),
              content: const Text('请关闭后重新操作'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('关闭'),
                ),
              ],
            );
          }
          return AlertDialog(
            title: Text(previous == null ? '添加收货地址' : '修改收货地址'),
            content: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: province,
                      decoration: const InputDecoration(
                        labelText: '省份 / 自治区 / 直辖市',
                      ),
                      items: [
                        for (final entry in mainlandProvinces.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: (value) => province = value,
                      validator: (value) => value == null ? '请选择省份' : null,
                    ),
                    for (final i in [0, 1, 5])
                      TextFormField(
                        controller: values[i],
                        decoration: InputDecoration(
                          labelText: {0: '收件人', 1: '联系电话', 5: '市、区县、街道及门牌号'}[i],
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请填写';
                          }
                          if (i == 1 &&
                              !RegExp(r'^\+?[0-9]{7,15}$').hasMatch(value)) {
                            return '请输入有效联系电话';
                          }
                          return null;
                        },
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (form.currentState!.validate()) {
                    Navigator.pop(
                      ctx,
                      CheckoutAddressInput(
                        recipient: values[0].text.trim(),
                        phone: values[1].text.trim(),
                        province_code: province!,
                        city_code: province == previous?.province_code
                            ? previous?.city_code
                            : null,
                        district_code: province == previous?.province_code
                            ? previous?.district_code
                            : null,
                        detail: values[5].text.trim(),
                      ),
                    );
                  }
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    // Controllers live until the dialog transition finishes.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final v in values) {
      v.dispose();
    }
    if (result != null && mounted && owner == user) {
      await command(() async {
        await ref
            .read(checkoutRepositoryProvider)
            .saveAddress(
              result,
              key({
                'address': result.toJson(),
                'previous': previous?.id,
                'version': previous?.version,
              }),
              previous: previous,
            );
      });
    }
  }

  String money(int fen) => '¥${(fen / 100).toStringAsFixed(2)}';
  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (before, after) {
      if (before?.principal?.user_id != after.principal?.user_id) {
        generation++;
        expiry?.cancel();
        keys.clear();
        setState(() {
          cart = null;
          addresses = [];
          selected.clear();
          address = null;
          quote = null;
          error = null;
          busy = false;
        });
        if (after.principal != null) Future.microtask(load);
      }
    });
    final owner = ref.watch(authProvider).principal?.user_id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('购物车'),
        actions: [
          IconButton(
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新购物车',
          ),
        ],
      ),
      body: owner == null
          ? const Center(child: Text('请登录后查看购物车'))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (busy) const LinearProgressIndicator(),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (cart != null && cart!.items.isEmpty)
                  const Text('购物车还是空的，去分类页挑选商品吧'),
                for (final item in cart?.items ?? <CartItem>[])
                  Card(
                    child: Column(
                      children: [
                        CheckboxListTile(
                          value: selected.contains(item.id),
                          title: Text(item.name ?? '商品已失效'),
                          subtitle: Text(
                            item.availability == 'AVAILABLE'
                                ? '${item.merchant_name ?? ''} · ${money(item.sale_price_fen!)} · 数量 ${item.quantity}'
                                : '当前不可售，请移除或刷新',
                          ),
                          onChanged: busy || item.availability != 'AVAILABLE'
                              ? null
                              : (value) => setState(() {
                                  quote = null;
                                  if (value == true) {
                                    selected.add(item.id);
                                  } else {
                                    selected.remove(item.id);
                                  }
                                }),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: '减少数量',
                              onPressed: busy || item.quantity <= 1
                                  ? null
                                  : () => command(() async {
                                      await ref
                                          .read(checkoutRepositoryProvider)
                                          .quantity(
                                            item,
                                            item.quantity - 1,
                                            key({
                                              'item': item.id,
                                              'version': item.version,
                                              'quantity': item.quantity - 1,
                                            }),
                                          );
                                    }),
                              icon: const Icon(Icons.remove),
                            ),
                            Text('${item.quantity}'),
                            IconButton(
                              tooltip: '增加数量',
                              onPressed: busy || item.quantity >= 999
                                  ? null
                                  : () => command(() async {
                                      await ref
                                          .read(checkoutRepositoryProvider)
                                          .quantity(
                                            item,
                                            item.quantity + 1,
                                            key({
                                              'item': item.id,
                                              'version': item.version,
                                              'quantity': item.quantity + 1,
                                            }),
                                          );
                                    }),
                              icon: const Icon(Icons.add),
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => command(() async {
                                      await ref
                                          .read(checkoutRepositoryProvider)
                                          .remove(
                                            item,
                                            key({
                                              'remove': item.id,
                                              'version': item.version,
                                            }),
                                          );
                                    }),
                              child: const Text('移除'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                const Divider(),
                const Text('收货地址'),
                for (final a in addresses)
                  ListTile(
                    leading: Icon(
                      address == a.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    onTap: busy
                        ? null
                        : () => setState(() {
                            address = a.id;
                            quote = null;
                          }),
                    title: Text('${a.recipient} · ${a.detail}'),
                    subtitle: Text(a.phone),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: '修改地址',
                          onPressed: busy ? null : () => editAddress(a),
                          icon: const Icon(Icons.edit),
                        ),
                        IconButton(
                          tooltip: '删除地址',
                          onPressed: busy
                              ? null
                              : () => command(() async {
                                  await ref
                                      .read(checkoutRepositoryProvider)
                                      .removeAddress(
                                        a,
                                        key({
                                          'delete_address': a.id,
                                          'version': a.version,
                                        }),
                                      );
                                }),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                OutlinedButton(
                  onPressed: busy ? null : editAddress,
                  child: const Text('添加收货地址'),
                ),
                if (benefits?.membership_eligible == true)
                  CheckboxListTile(
                    title: const Text('使用有效会员价'),
                    value: membership,
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            membership = v ?? false;
                            quote = null;
                          }),
                  ),
                if (benefits != null)
                  for (final c in benefits!.coupons)
                    CheckboxListTile(
                      title: Text(
                        '${c.scope == 'MERCHANT'
                            ? c.merchant_name ?? '商家券'
                            : c.scope == 'SHIPPING'
                            ? '运费券'
                            : '平台券'} · 优惠 ${money(c.amount_fen)}',
                      ),
                      subtitle: Text('符合范围金额满 ${money(c.threshold_fen)} 可用'),
                      value: coupons.contains(c.id),
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              quote = null;
                              if (v == true) {
                                coupons.add(c.id);
                              } else {
                                coupons.remove(c.id);
                              }
                            }),
                    ),
                FilledButton(
                  onPressed: busy || selected.isEmpty || address == null
                      ? null
                      : price,
                  child: const Text('试算所选商品'),
                ),
                if (quote case final q?)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('结账试算'),
                          Text('商品 ${money(q.goods_amount_fen)}'),
                          Text('运费 ${money(q.shipping_amount_fen)}'),
                          Text('优惠 −${money(q.discount_amount_fen)}'),
                          Text(
                            '应付 ${money(q.payable_amount_fen)}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          for (final group in q.merchant_groups)
                            Text(
                              '${group.merchant_name} · 商品 ${money(group.goods_payable_fen)} · 运费 ${money(group.shipping_payable_fen)}',
                            ),
                          Text('有效至 ${DateTime.parse(q.expires_at).toLocal()}'),
                          Text(
                            q.status == 'ACTIVE'
                                ? '未锁定库存，购买前需要重新校验'
                                : '此试算已失效，请重新确认',
                          ),
                          OutlinedButton(
                            onPressed: busy ? null : verifyQuote,
                            child: const Text('核对试算有效性'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// Province-level GB/T 2260 names/codes; district codes remain unknown until sourced.
// Source: https://www.gov.cn/zhengce/2001-11/01/content_5720217.htm (province-level table only).
const mainlandProvinces = {
  '110000': '北京市',
  '120000': '天津市',
  '130000': '河北省',
  '140000': '山西省',
  '150000': '内蒙古自治区',
  '210000': '辽宁省',
  '220000': '吉林省',
  '230000': '黑龙江省',
  '310000': '上海市',
  '320000': '江苏省',
  '330000': '浙江省',
  '340000': '安徽省',
  '350000': '福建省',
  '360000': '江西省',
  '370000': '山东省',
  '410000': '河南省',
  '420000': '湖北省',
  '430000': '湖南省',
  '440000': '广东省',
  '450000': '广西壮族自治区',
  '460000': '海南省',
  '500000': '重庆市',
  '510000': '四川省',
  '520000': '贵州省',
  '530000': '云南省',
  '540000': '西藏自治区',
  '610000': '陕西省',
  '620000': '甘肃省',
  '630000': '青海省',
  '640000': '宁夏回族自治区',
  '650000': '新疆维吾尔自治区',
};
