import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

import 'api/generated/dto.dart';
import 'publishing_repository.dart';
import 'repositories.dart';
import 'catalog_screen.dart';

class PublicationMediaView extends ConsumerStatefulWidget {
  final PublicationMedia media;
  const PublicationMediaView({super.key, required this.media});
  @override
  ConsumerState<PublicationMediaView> createState() => _PublicationMediaState();
}

class _PublicationMediaState extends ConsumerState<PublicationMediaView> {
  Uint8List? bytes;
  VideoPlayerController? player;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant PublicationMediaView old) {
    super.didUpdateWidget(old);
    if (old.media.content_url != widget.media.content_url ||
        old.media.available != widget.media.available) {
      load();
    }
  }

  void clear() {
    generation++;
    bytes = null;
    final old = player;
    player = null;
    if (old != null) {
      old.pause();
      old.dispose();
    }
  }

  Future<void> load() async {
    clear();
    final own = generation, media = widget.media;
    error = null;
    if (!media.available) return;
    try {
      final api = ref.read(consumerApiProvider),
          anonymous = media.content_url.startsWith('/api/v1/public/');
      if (media.mime == 'video/mp4') {
        final source = api.mediaSource(media.content_url, anonymous: anonymous),
            p = VideoPlayerController.networkUrl(
              source.uri,
              httpHeaders: source.headers,
            );
        player = p;
        await p.initialize();
        if (!mounted || own != generation) {
          if (player == p) player = null;
          await p.dispose();
          return;
        }
      } else {
        final value = await api.mediaBytes(
          media.content_url,
          anonymous: anonymous,
        );
        if (!mounted || own != generation) return;
        bytes = value;
      }
      if (mounted && own == generation) setState(() {});
    } catch (_) {
      if (mounted && own == generation) setState(() => error = '资源暂时不可读取');
    }
  }

  @override
  void dispose() {
    clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (a, b) {
      if (a?.principal?.session_id != b.principal?.session_id) load();
    });
    if (!widget.media.available) return const Text('资源不可用');
    if (error != null) return TextButton(onPressed: load, child: Text(error!));
    if (bytes != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Image.memory(
          bytes!,
          height: 200,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Text('图片无法显示'),
        ),
      );
    }
    final p = player;
    if (p != null && p.value.isInitialized) {
      return Column(
        children: [
          AspectRatio(aspectRatio: p.value.aspectRatio, child: VideoPlayer(p)),
          TextButton(
            onPressed: () {
              p.value.isPlaying ? p.pause() : p.play();
              setState(() {});
            },
            child: Text(p.value.isPlaying ? '暂停视频' : '播放视频'),
          ),
        ],
      );
    }
    return const Padding(
      padding: EdgeInsets.all(12),
      child: LinearProgressIndicator(),
    );
  }
}

class ReviewsScreen extends ConsumerStatefulWidget {
  final String? spuId;
  final bool own;
  const ReviewsScreen({super.key, this.spuId, this.own = false});
  @override
  ConsumerState<ReviewsScreen> createState() => _ReviewsState();
}

class _ReviewsState extends ConsumerState<ReviewsScreen> {
  List<PublicReview> publicRows = [];
  List<ReviewDetail> ownRows = [];
  String? cursor, error;
  bool busy = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> load({bool more = false}) async {
    if (busy) return;
    final own = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(publishingRepositoryProvider);
      if (widget.own) {
        final result = await repo.own(cursor: more ? cursor : null);
        if (!mounted || own != generation) return;
        setState(() {
          ownRows = more ? [...ownRows, ...result.data] : result.data;
          cursor = result.page.next_cursor;
        });
      } else {
        if (widget.spuId == null || widget.spuId!.isEmpty) {
          throw StateError('请选择商品');
        }
        final result = await repo.reviews(
          widget.spuId!,
          cursor: more ? cursor : null,
        );
        if (!mounted || own != generation) return;
        setState(() {
          publicRows = more ? [...publicRows, ...result.data] : result.data;
          cursor = result.page.next_cursor;
        });
      }
    } catch (e) {
      if (mounted && own == generation) setState(() => error = e.toString());
    } finally {
      if (mounted && own == generation) setState(() => busy = false);
    }
  }

  Widget card(PublicReview r, {ReviewDetail? detail}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('商品 ${r.rating}/5 · 履约服务 ${r.service_rating ?? '未评分'}/5'),
          const Text('已验证购买'),
          Text(r.body),
          if (r.pet_label != null)
            Text(
              '${r.pet_label!.species_name} · ${r.pet_label!.breed_name ?? '品种未填写'} · ${r.pet_label!.age_label ?? '年龄未填写'}',
            ),
          for (final m in r.media)
            PublicationMediaView(
              key: ValueKey('${r.revision_id}:${m.asset_id}'),
              media: m,
            ),
          if (detail != null) ...[
            Text('${detail.draft_status} · ${detail.visibility}'),
            TextButton(
              onPressed: () => context.push(
                '/review-edit?id=${detail.id}&item_id=${detail.order_item_id}',
              ),
              child: const Text('编辑评价与宠物授权'),
            ),
          ],
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (a, b) {
      if (a?.principal?.session_id != b.principal?.session_id) {
        generation++;
        setState(() {
          ownRows = [];
          publicRows = [];
          busy = false;
          error = null;
          cursor = null;
        });
        if (!widget.own || b.principal != null) Future.microtask(load);
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.own ? '我的评价' : '真实购买评价'),
        actions: [
          IconButton(
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          if (!busy && ownRows.isEmpty && publicRows.isEmpty)
            const Text('暂无评价'),
          for (final r in publicRows) card(r),
          for (final r in ownRows)
            card(PublicReview.fromJson({...r.toJson()}), detail: r),
          if (cursor != null)
            TextButton(
              onPressed: busy ? null : () => load(more: true),
              child: const Text('更多评价'),
            ),
        ],
      ),
    );
  }
}

class ReviewEditorScreen extends ConsumerStatefulWidget {
  final String itemId;
  final String? reviewId;
  const ReviewEditorScreen({super.key, required this.itemId, this.reviewId});
  @override
  ConsumerState<ReviewEditorScreen> createState() => _EditorState();
}

class _EditorState extends ConsumerState<ReviewEditorScreen> {
  final text = TextEditingController();
  int rating = 5, service = 5, generation = 0;
  bool busy = false, share = false;
  String? petId, error, notice;
  ReviewDetail? existing;
  ReviewEligibility? eligibility;
  List<String> assets = [];
  final keys = <String, String>{};
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
    Future.microtask(recoverSelection);
  }

  Future<void> recoverSelection() async {
    try {
      final lost = await ImagePicker().retrieveLostData();
      if (mounted && !lost.isEmpty) {
        setState(() => notice = '上次选择因应用重启中断，请重新选择附件。');
      }
    } catch (_) {
      /* Gallery recovery is unavailable on some platforms. */
    }
  }

  Future<void> load() async {
    final own = ++generation;
    setState(() => busy = true);
    try {
      final repo = ref.read(publishingRepositoryProvider);
      final e = await repo.eligibility(widget.itemId);
      final id = widget.reviewId ?? e.existing_review_id;
      final r = id == null ? null : await repo.review(id);
      if (!mounted || own != generation) return;
      setState(() {
        eligibility = e;
        existing = r;
        if (r != null) {
          text.text = r.body;
          rating = r.rating;
          service = r.service_rating ?? 5;
          share = r.share_pet_label;
          petId = r.pet_id;
          assets = r.media.map((m) => m.asset_id).toList();
        }
      });
    } catch (e) {
      if (mounted && own == generation) setState(() => error = e.toString());
    } finally {
      if (mounted && own == generation) setState(() => busy = false);
    }
  }

  Future<void> upload(bool video) async {
    if (busy || assets.length >= 6) return;
    final own = generation,
        identity = ref.read(authProvider).principal?.session_id;
    setState(() => busy = true);
    try {
      final picker = ImagePicker(),
          file = video
              ? await picker.pickVideo(
                  source: ImageSource.gallery,
                  maxDuration: const Duration(seconds: 120),
                )
              : await picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      if (!mounted ||
          own != generation ||
          identity != ref.read(authProvider).principal?.session_id) {
        return;
      }
      if (await file.length() > 5242880) throw StateError('附件不能超过 5 MiB');
      final ext = file.name.toLowerCase();
      final mime = video
          ? 'video/mp4'
          : ext.endsWith('.png')
          ? 'image/png'
          : ext.endsWith('.jpg') || ext.endsWith('.jpeg')
          ? 'image/jpeg'
          : '';
      if (mime.isEmpty) throw StateError('请选择 PNG、JPEG 或 MP4');
      final bytes = await file.readAsBytes();
      if (!mounted ||
          own != generation ||
          identity != ref.read(authProvider).principal?.session_id) {
        return;
      }
      final a = await ref
          .read(publishingRepositoryProvider)
          .upload(bytes, mime);
      if (mounted && own == generation) {
        setState(() {
          assets.add(a.asset_id);
          notice = '附件已上传，提交后进入审核';
        });
      }
    } catch (e) {
      if (mounted && own == generation) setState(() => error = e.toString());
    } finally {
      if (mounted && own == generation) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy) return;
    final own = generation, current = ref.read(currentPetProvider);
    if (share && petId == null && current == null) {
      setState(() => error = '请先选择自己的宠物');
      return;
    }
    final b = ReviewInput(
      rating: rating,
      service_rating: service,
      body: text.text,
      asset_ids: assets,
      pet_id: share ? petId ?? current?.id : null,
      share_pet_label: share,
    );
    final payload = '${existing?.version}:${jsonEncode(b.toJson())}',
        key = keys.putIfAbsent(payload, () => const Uuid().v4());
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await ref
          .read(publishingRepositoryProvider)
          .save(widget.itemId, b, key, existing: existing);
      if (mounted && own == generation) {
        setState(() {
          existing = r;
          notice = '评价已提交审核；撤销的宠物展示授权立即生效';
        });
      }
    } catch (e) {
      if (mounted && own == generation) setState(() => error = e.toString());
    } finally {
      if (mounted && own == generation) setState(() => busy = false);
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
    ref.listen(authProvider, (a, b) {
      if (a?.principal?.session_id != b.principal?.session_id) {
        generation++;
        text.clear();
        setState(() {
          existing = null;
          eligibility = null;
          assets = [];
          petId = null;
          share = false;
          busy = false;
          keys.clear();
          error = null;
          notice = null;
        });
      }
    });
    final pet = ref.watch(currentPetProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('购买评价')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          if (notice != null) Text(notice!),
          if (eligibility != null && !eligibility!.eligible && existing == null)
            const Text('该订单项尚不可评价：需已付款、已收货且无处理中售后。'),
          if (existing != null || eligibility?.eligible == true) ...[
            Text(
              '同一订单评价奖励 ${eligibility?.reward_policy.base_points ?? 0} 分，媒体增量 ${eligibility?.reward_policy.media_bonus_points ?? 0} 分；审核通过后按冻结规则领取，退款可能追回。',
            ),
            DropdownButtonFormField<int>(
              initialValue: rating,
              decoration: const InputDecoration(labelText: '商品评分'),
              items: [
                for (var i = 1; i <= 5; i++)
                  DropdownMenuItem(value: i, child: Text('$i 分')),
              ],
              onChanged: busy ? null : (v) => setState(() => rating = v!),
            ),
            DropdownButtonFormField<int>(
              initialValue: service,
              decoration: const InputDecoration(labelText: '履约服务评分'),
              items: [
                for (var i = 1; i <= 5; i++)
                  DropdownMenuItem(value: i, child: Text('$i 分')),
              ],
              onChanged: busy ? null : (v) => setState(() => service = v!),
            ),
            TextField(
              controller: text,
              maxLength: 2000,
              maxLines: 5,
              decoration: const InputDecoration(labelText: '分享实际使用体验'),
              enabled: !busy,
            ),
            SwitchListTile(
              value: share,
              title: const Text('同意公开宠物类型、品种与粗略年龄'),
              subtitle: Text('不公开名字、体重、过敏原或备注。当前宠物：${pet?.name ?? '未选择'}'),
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      share = v;
                      if (v) petId = pet?.id;
                    }),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: busy || assets.length >= 6
                      ? null
                      : () => upload(false),
                  child: const Text('添加图片'),
                ),
                OutlinedButton(
                  onPressed: busy || assets.length >= 6
                      ? null
                      : () => upload(true),
                  child: const Text('添加短视频'),
                ),
              ],
            ),
            const Text('最多 6 个附件，单个 5 MiB；视频为 H.264 MP4，最长 120 秒。'),
            for (final id in assets)
              ListTile(
                title: const Text('已上传附件'),
                subtitle: Text(id),
                trailing: IconButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => assets.remove(id)),
                  icon: const Icon(Icons.close),
                ),
              ),
            FilledButton(
              onPressed: busy ? null : save,
              child: const Text('提交评价审核'),
            ),
          ],
        ],
      ),
    );
  }
}

class ContentScreen extends ConsumerStatefulWidget {
  final String? id;
  const ContentScreen({super.key, this.id});
  @override
  ConsumerState<ContentScreen> createState() => _ContentState();
}

class _ContentState extends ConsumerState<ContentScreen> {
  List<PublicArticle> rows = [];
  PublicArticle? article;
  String? cursor, category, error;
  bool busy = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> load({bool more = false}) async {
    if (busy) return;
    final own = ++generation, pet = ref.read(currentPetProvider)?.id;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(publishingRepositoryProvider);
      if (widget.id != null) {
        final a = await repo.article(
          widget.id!,
          pet: ref.read(authProvider).principal == null ? null : pet,
        );
        if (mounted && own == generation) setState(() => article = a);
      } else {
        final page = await repo.articles(
          cursor: more ? cursor : null,
          category: category,
        );
        if (mounted && own == generation) {
          setState(() {
            rows = more ? [...rows, ...page.data] : page.data;
            cursor = page.page.next_cursor;
          });
        }
      }
    } catch (e) {
      if (mounted && own == generation) setState(() => error = e.toString());
    } finally {
      if (mounted && own == generation) setState(() => busy = false);
    }
  }

  void reload() {
    generation++;
    setState(() {
      article = null;
      rows = [];
      cursor = null;
      busy = false;
      error = null;
    });
    Future.microtask(load);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentPetProvider, (a, b) {
      if (a?.id != b?.id) reload();
    });
    ref.listen(authProvider, (a, b) {
      if (a?.principal?.session_id != b.principal?.session_id) reload();
    });
    final a = article;
    return Scaffold(
      appBar: AppBar(
        title: const Text('食品与养宠知识'),
        actions: [
          IconButton(
            onPressed: busy ? null : () => load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          if (widget.id == null) ...[
            DropdownButton<String>(
              value: category,
              hint: const Text('全部内容'),
              items: const [
                DropdownMenuItem(value: 'FOOD_KNOWLEDGE', child: Text('食品知识')),
                DropdownMenuItem(value: 'BRAND_KNOWLEDGE', child: Text('品牌知识')),
                DropdownMenuItem(value: 'PET_CARE', child: Text('养宠知识')),
              ],
              onChanged: busy
                  ? null
                  : (v) {
                      category = v;
                      reload();
                    },
            ),
            for (final row in rows)
              Card(
                child: ListTile(
                  title: Text(row.title),
                  subtitle: Text(row.sponsored ? '商业推广' : '知识文章'),
                  onTap: () => context.push('/content?id=${row.id}'),
                ),
              ),
            if (!busy && rows.isEmpty) const Text('暂无已发布文章'),
            if (cursor != null)
              TextButton(
                onPressed: busy ? null : () => load(more: true),
                child: const Text('更多文章'),
              ),
          ],
          if (a != null) ...[
            if (a.sponsored) const Chip(label: Text('商业推广')),
            Text(a.title, style: Theme.of(context).textTheme.headlineSmall),
            SelectableText(a.body),
            for (final m in a.media)
              PublicationMediaView(
                key: ValueKey('${a.revision_id}:${m.asset_id}'),
                media: m,
              ),
            const Text('信息来源'),
            for (final source in a.source_refs) SelectableText(source),
            for (final p in a.products)
              Card(
                child: ListTile(
                  title: Text(p.name ?? '商品已不可用'),
                  subtitle: Text(
                    !p.available
                        ? '商品资料已下架'
                        : '${p.in_stock ? '当前有库存' : '暂无库存'} · ${p.fit?.display_label ?? '选择宠物查看适配'}',
                  ),
                  onTap: !p.available
                      ? null
                      : () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => FractionallySizedBox(
                            heightFactor: .9,
                            child: ProductScreen(sku: p.sku_id),
                          ),
                        ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
