import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api/generated/dto.dart';
import 'nearby_repository.dart';
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
  const NearbyScreen({super.key});
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

  Future<void> detail(NearbyResult row) async {
    try {
      final place = await ref.read(nearbyRepositoryProvider).place(row.id);
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
                  Text('${nearbyCategories[place.category]} · ${place.city}'),
                  Text(place.address),
                  Text('电话：${place.phone}'),
                  Text('营业信息：${place.business_hours}'),
                  Text(
                    '可用服务：${place.services.map((s) => nearbyServices[s]).join('、')}',
                  ),
                  Text(
                    '来源：商家提交 · 已核实认领${place.pawday_certified ? ' · 平台已认证' : ''}',
                  ),
                  const Text('服务与营业时间请联系门店确认。医院仅提供地点与联系方式，不提供诊断或治疗排行。'),
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await navigate(place.id);
                    },
                    child: const Text('交给高德导航'),
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
    appBar: AppBar(title: const Text('附近')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('发现身边的宠物服务', style: Theme.of(context).textTheme.headlineSmall),
        const Text('仅在你选择定位时获取一次位置。拒绝后仍可按城市浏览。'),
        const SizedBox(height: 16),
        TextField(
          controller: city,
          decoration: const InputDecoration(
            labelText: '浏览城市',
            hintText: '例如：上海',
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
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final name in ['上海', '北京', '广州', '深圳'])
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
        DropdownButtonFormField<String>(
          initialValue: category,
          decoration: const InputDecoration(labelText: '地点类别'),
          items: [
            const DropdownMenuItem(value: null, child: Text('全部')),
            for (final entry in nearbyCategories.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: busy
              ? null
              : (value) {
                  setState(() => category = value);
                  if (searched) voidLoad();
                },
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
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
                  final opened = await ref.read(locationProvider).settings();
                  if (!opened && mounted) {
                    setState(
                      () => locationMessage = '请在浏览器或系统设置中开启位置权限，然后点击定位重试。',
                    );
                  }
                },
                child: const Text('打开应用设置'),
              ),
          ],
        ),
        if (locationMessage != null) Text(locationMessage!),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)),
        if (busy) const LinearProgressIndicator(),
        if (searched && rows.isEmpty && !busy)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('该范围暂无已公开门店。可以切换城市、类别或重试定位。'),
          ),
        for (final row in rows)
          Card(
            child: ListTile(
              title: Text(row.name),
              subtitle: Text(
                '${nearbyCategories[row.category]} · ${row.distance_m == null ? row.city : '约 ${row.distance_m} 米直线距离'}\n${row.address}\n${row.services.map((s) => nearbyServices[s]).join('、')}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => detail(row),
            ),
          ),
        if (next != null)
          TextButton(
            onPressed: busy ? null : () => load(more: true),
            child: const Text('更多门店'),
          ),
      ],
    ),
  );
  void voidLoad() {
    load();
  }
}
