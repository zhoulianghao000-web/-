import 'favorites_screen.dart';
import 'reference_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api/generated/dto.dart';
import 'nearby_repository.dart';
import 'pilot.dart';
import 'checkout_repository.dart';

const nearbyCategories = {
  'PET_STORE': '宠物店',
  'VET': '宠物医院',
  'GROOMING': '美容洗护',
  'BOARDING': '寄养',
};
const nearbyServices = {
  'SUPPLIES': '宠物用品',
  'GROOMING': '美容洗护',
  'BOARDING': '寄养',
  'CONSULTATION': '医院咨询',
  'EMERGENCY': '急诊联系',
  'PET_FRIENDLY': '宠物友好',
};

class NearbyScreen extends ConsumerStatefulWidget {
  final String? storeId;
  const NearbyScreen({super.key, this.storeId});
  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen> {
  final city = TextEditingController();
  Coordinates? position;
  String? category, next, error, locationMessage;
  LocationIssue? issue;
  List<NearbyResult> rows = [];
  bool busy = false, searched = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    if (widget.storeId != null) Future.microtask(() => detail(widget.storeId!));
  }

  @override
  void didUpdateWidget(covariant NearbyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.storeId != null && widget.storeId != oldWidget.storeId) {
      Future.microtask(() => detail(widget.storeId!));
    }
  }

  @override
  void dispose() {
    generation++;
    city.dispose();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (position == null && city.text.trim().isEmpty) {
      setState(() {
        error = '输入城市，或主动选择定位。';
      });
      return;
    }
    final g = ++generation;
    setState(() {
      busy = true;
      error = null;
      if (!more) {
        rows = [];
        next = null;
      }
    });
    try {
      final response = await ref
          .read(nearbyRepositoryProvider)
          .places(
            city: position == null ? city.text.trim() : null,
            category: category,
            position: position,
            offset: more ? int.parse(next!) : 0,
          );
      if (!mounted || g != generation) return;
      setState(() {
        rows = more
            ? [
                ...rows,
                ...response.data.where(
                  (row) => !rows.any((old) => old.id == row.id),
                ),
              ]
            : response.data;
        next = response.page.next_cursor;
        searched = true;
      });
    } catch (e) {
      if (mounted && g == generation) setState(() => error = checkoutError(e));
    } finally {
      if (mounted && g == generation) setState(() => busy = false);
    }
  }

  Future<void> locate() async {
    final g = ++generation;
    setState(() {
      busy = true;
      error = null;
      issue = null;
      locationMessage = null;
      position = null;
      rows = [];
      next = null;
      searched = false;
    });
    try {
      final p = await ref.read(locationProvider).locate();
      if (!mounted || g != generation) return;
      setState(() {
        position = p;
        city.clear();
        locationMessage = '使用本次位置，按直线距离排序（约 10 公里）。';
        busy = false;
      });
      await load();
    } on LocationFailure catch (e) {
      if (mounted && g == generation) {
        setState(() {
          issue = e.issue;
          locationMessage = switch (e.issue) {
            LocationIssue.denied => '未授权位置，仍可输入城市浏览。',
            LocationIssue.deniedForever => '位置权限已关闭，可前往设置开启，或按城市浏览。',
            LocationIssue.disabled => '设备定位服务未开启，可开启后重试，或按城市浏览。',
            LocationIssue.timeout => '定位超时，可重试或按城市浏览。',
            LocationIssue.unavailable => '暂时无法获取位置，可重试或按城市浏览。',
          };
          busy = false;
        });
      }
    }
  }

  Future<void> detail(String storeId) async {
    try {
      final place = await ref.read(nearbyRepositoryProvider).place(storeId);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Text('${nearbyCategories[place.category]} · ${place.city}'),
                  const SizedBox(height: 16),
                  Text(place.address),
                  const SizedBox(height: 16),
                  Text('电话：${place.phone}'),
                  const SizedBox(height: 16),
                  Text('营业信息：${place.business_hours}'),
                  const SizedBox(height: 16),
                  Text(
                    '可用服务：${place.services.map((s) => nearbyServices[s]).join('、')}',
                  ),
                  Text(
                    '来源：商家提交 · 已核实认领${place.pawday_certified ? ' · 平台已认证' : ''}',
                  ),
                  const Text('服务与营业时间请联系门店确认。医院仅提供地点与联系方式，不提供诊断或治疗排行。'),
                  FavoriteButton(kind: 'STORE', target: place.id),
                  const SizedBox(height: 16),
                  PawdayButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await navigate(place.id);
                    },
                    child: const Text(pilotMode ? '预览测试目的地' : '交给高德导航'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      this.context.go(
                        Uri(
                          path: '/support',
                          queryParameters: {'store_id': place.id},
                        ).toString(),
                      );
                    },
                    child: const Text('联系门店客服'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = checkoutError(e));
    }
  }

  Future<void> navigate(String id) async {
    if (pilotMode) {
      setState(() => locationMessage = '模拟导航：仅预览门店目的地，不打开外部应用。');
      return;
    }
    try {
      final intent = await ref.read(nearbyRepositoryProvider).navigation(id);
      if (!mounted) return;
      final opened = await ref.read(navigationLauncherProvider).open(intent);
      if (mounted && !opened) setState(() => error = '无法打开高德，请根据门店地址手动搜索。');
    } catch (e) {
      if (mounted) setState(() => error = checkoutError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
                const Text(
                  'AROUND YOU',
                  style: TextStyle(
                    color: PawdayDesign.green,
                    fontSize: 11,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '发现身边的宠物服务',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '从日常用品到洗护寄养，找到下一站。',
                  style: TextStyle(color: PawdayDesign.muted, height: 1.6),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: PawdayDesign.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: PawdayDesign.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, box) {
                          final cityField = TextField(
                            controller: city,
                            decoration: InputDecoration(
                              labelText: '浏览城市',
                              hintText: pilotMode ? '例如：重庆' : '例如：上海',
                              prefixIcon: const Icon(
                                Icons.location_city_outlined,
                              ),
                            ),
                            onChanged: (_) {
                              generation++;
                              setState(() {
                                position = null;
                                busy = false;
                                next = null;
                                rows = [];
                                searched = false;
                              });
                            },
                          );
                          final categoryField = DropdownButtonFormField<String>(
                            initialValue: category,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '地点类别',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('全部'),
                              ),
                              for (final entry in nearbyCategories.entries)
                                DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                            ],
                            onChanged: busy
                                ? null
                                : (value) {
                                    setState(() => category = value);
                                    if (searched) voidLoad();
                                  },
                          );
                          return box.maxWidth >= 620
                              ? Row(
                                  children: [
                                    Expanded(flex: 3, child: cityField),
                                    const SizedBox(width: 20),
                                    Expanded(flex: 2, child: categoryField),
                                  ],
                                )
                              : Column(
                                  children: [
                                    cityField,
                                    const SizedBox(height: 20),
                                    categoryField,
                                  ],
                                );
                        },
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            '快捷城市',
                            style: TextStyle(
                              fontSize: 12,
                              color: PawdayDesign.muted,
                            ),
                          ),
                          for (final name
                              in (pilotMode
                                  ? ['重庆']
                                  : ['上海', '北京', '广州', '深圳']))
                            ActionChip(
                              label: Text(name),
                              onPressed: busy
                                  ? null
                                  : () {
                                      setState(() {
                                        position = null;
                                        city.text = name;
                                      });
                                      voidLoad();
                                    },
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          PawdayButton(
                            onPressed: busy ? null : () => load(),
                            child: const Text('按城市浏览'),
                          ),
                          OutlinedButton(
                            onPressed: busy ? null : locate,
                            child: const Text('使用本次位置'),
                          ),
                          if (issue == LocationIssue.deniedForever)
                            TextButton(
                              onPressed: () async {
                                final opened = await ref
                                    .read(locationProvider)
                                    .settings();
                                if (!opened && mounted) {
                                  setState(
                                    () => locationMessage =
                                        '请在浏览器或系统设置中开启位置权限，然后点击定位重试。',
                                  );
                                }
                              },
                              child: const Text('打开应用设置'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '仅在你选择定位时获取一次位置。拒绝后仍可按城市浏览。',
                        style: TextStyle(
                          color: PawdayDesign.muted,
                          fontSize: 12,
                          height: 1.7,
                        ),
                      ),
                      if (locationMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              locationMessage!,
                              style: const TextStyle(
                                color: PawdayDesign.green,
                                height: 1.6,
                              ),
                            ),
                          ),
                        ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              error!,
                              style: const TextStyle(
                                color: Color(0xff9c3725),
                                height: 1.6,
                              ),
                            ),
                          ),
                        ),
                      if (busy)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: LinearProgressIndicator(),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                if (!searched && !busy)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xffeaf0e1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.travel_explore,
                          color: PawdayDesign.green,
                          size: 30,
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '先选择城市，开启附近探索',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                '查看门店地址、可用服务和营业信息。定位结果按直线距离排序，出发前请与门店确认。',
                                style: TextStyle(
                                  height: 1.8,
                                  color: PawdayDesign.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (searched)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      position == null ? '城市内的公开门店' : '本次位置附近 · 按直线距离排序',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (searched && rows.isEmpty && !busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '该范围暂无已公开门店。可以切换城市、类别或重试定位。',
                      style: TextStyle(height: 1.8, color: PawdayDesign.muted),
                    ),
                  ),
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Material(
                      color: PawdayDesign.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: PawdayDesign.line),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Semantics(
                        button: true,
                        child: InkWell(
                          onTap: () => detail(row.id),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xffeaf0e1),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.storefront_outlined,
                                    color: PawdayDesign.green,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        row.name,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${nearbyCategories[row.category]} · ${row.distance_m == null ? row.city : '约 ${row.distance_m} 米直线距离'}',
                                        style: const TextStyle(
                                          color: PawdayDesign.green,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        row.address,
                                        style: const TextStyle(
                                          color: PawdayDesign.muted,
                                          height: 1.6,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          for (final service in row.services)
                                            Chip(
                                              label: Text(
                                                nearbyServices[service] ??
                                                    service,
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: PawdayDesign.green,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (next != null)
                  TextButton(
                    onPressed: busy ? null : () => load(more: true),
                    child: const Text('更多门店'),
                  ),
                if (pilotMode) ...[
                  const SizedBox(height: 24),
                  const Text(
                    '重庆合成门店；认领、营业时间和服务均为测试预设，非实际核验。',
                    style: TextStyle(
                      color: PawdayDesign.muted,
                      fontSize: 12,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('测试场景工具', style: TextStyle(fontSize: 14)),
                    subtitle: const Text(
                      '模拟定位与导航异常，不调用真实设备或外部导航',
                      style: TextStyle(fontSize: 12),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final scenario in [
                              'ALLOWED',
                              'DENIED',
                              'DISABLED',
                            ])
                              OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () {
                                        (ref.read(locationProvider).device
                                                    as PilotGeolocation)
                                                .scenario =
                                            scenario;
                                        locate();
                                      },
                                child: Text('模拟定位：$scenario'),
                              ),
                            TextButton(
                              onPressed: () => setState(
                                () => locationMessage =
                                    '预设导航失败：未调用高德或外部应用，请核对合成目的地。',
                              ),
                              child: const Text('模拟导航失败'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
  void voidLoad() {
    load();
  }
}
