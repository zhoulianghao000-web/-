import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api/generated/dto.dart';
import 'care_repository.dart';
import 'catalog_screen.dart';
import 'catalog_repository.dart';
import 'repositories.dart';
import 'reference_ui.dart';

class FavoriteButton extends ConsumerStatefulWidget {
  final String kind, target;
  const FavoriteButton({super.key, required this.kind, required this.target});
  @override
  ConsumerState<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends ConsumerState<FavoriteButton> {
  bool busy = false, saved = false;
  String command = careKey();
  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (a, b) {
      if (a?.principal?.session_id != b.principal?.session_id && mounted) {
        setState(() {
          saved = false;
          busy = false;
          command = careKey();
        });
      }
    });
    return TextButton.icon(
      icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
      label: Text(
        saved
            ? '已收藏'
            : widget.kind == 'STORE'
            ? '收藏门店'
            : '收藏商品',
      ),
      onPressed: busy || saved
          ? null
          : () async {
              final session = ref.read(authProvider).principal?.session_id;
              if (session == null) {
                context.push('/auth/login?returnTo=%2Ffavorites');
                return;
              }
              setState(() => busy = true);
              try {
                await ref
                    .read(careRepositoryProvider)
                    .favorite(widget.kind, widget.target, command);
                if (mounted &&
                    ref.read(authProvider).principal?.session_id == session) {
                  setState(() {
                    saved = true;
                    busy = false;
                  });
                }
              } catch (e) {
                if (mounted &&
                    ref.read(authProvider).principal?.session_id == session) {
                  setState(() => busy = false);
                  ScaffoldMessenger.of(this.context)
                      .showSnackBar(SnackBar(content: Text(careError(e))));
                }
              }
            },
    );
  }
}

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});
  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesState();
}

class _FavoritesState extends ConsumerState<FavoritesScreen> {
  List<Favorite> rows = [];
  String? cursor, error;
  bool busy = false;
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

  Future<void> load({bool more = false}) async {
    final session = ref.read(authProvider).principal?.session_id;
    if (session == null) return;
    final g = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await ref
          .read(careRepositoryProvider)
          .favorites(cursor: more ? cursor : null);
      if (!mounted ||
          g != generation ||
          ref.read(authProvider).principal?.session_id != session) {
        return;
      }
      setState(() {
        rows = more ? [...rows, ...result.data] : result.data;
        cursor = result.page.next_cursor;
        busy = false;
      });
    } catch (e) {
      if (mounted &&
          g == generation &&
          ref.read(authProvider).principal?.session_id == session) {
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
        generation++;
        if (mounted) {
          setState(() {
            rows = [];
            cursor = null;
            error = null;
            busy = false;
          });
        }
        if (b.principal != null) Future.microtask(load);
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏'),
        actions: [
          IconButton(
            tooltip: '刷新收藏',
            onPressed: busy ? null : () => load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                '留住喜欢的好物与门店',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text('商品价格、库存及门店服务以查看时的最新信息为准。'),
              const SizedBox(height: 24),
              if (busy) const LinearProgressIndicator(),
              if (error != null) ...[
                Text(error!),
                TextButton(onPressed: () => load(), child: const Text('重试')),
              ],
              if (!busy && error == null && rows.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        const Icon(Icons.favorite_border, size: 48),
                        const SizedBox(height: 16),
                        const Text('还没有收藏，去发现喜欢的商品与门店。'),
                        const SizedBox(height: 20),
                        PawdayButton(
                          onPressed: () => context.push('/categories'),
                          child: const Text('发现好物'),
                        ),
                      ],
                    ),
                  ),
                ),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                row.kind == 'STORE'
                                    ? Icons.storefront
                                    : Icons.shopping_bag_outlined,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  row.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            row.available
                                ? (row.kind == 'STORE' ? '已公开门店' : '已发布商品')
                                : '该内容已下架或不再公开',
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              if (row.available)
                                PawdayButton(
                                  onPressed: () async {
                                    final session = ref
                                        .read(authProvider)
                                        .principal
                                        ?.session_id;
                                    try {
                                      if (row.kind == 'STORE') {
                                        context.push(
                                          '/nearby?store_id=${row.target_id}',
                                        );
                                      } else {
                                        final p = await ref
                                            .read(catalogRepositoryProvider)
                                            .product(row.target_id);
                                        if (!context.mounted ||
                                            ref
                                                    .read(authProvider)
                                                    .principal
                                                    ?.session_id !=
                                                session) {
                                          return;
                                        }
                                        if (p.skus.isNotEmpty) {
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute<void>(
                                              builder: (_) => ProductScreen(
                                                sku: p.skus.first.id,
                                              ),
                                            ),
                                          );
                                        }
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
                                          SnackBar(content: Text(careError(e))),
                                        );
                                      }
                                    }
                                  },
                                  child: Text(
                                    row.kind == 'STORE' ? '查看附近门店' : '查看商品',
                                  ),
                                ),
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () async {
                                        final session = ref
                                            .read(authProvider)
                                            .principal
                                            ?.session_id;
                                        setState(() => busy = true);
                                        try {
                                          await ref
                                              .read(careRepositoryProvider)
                                              .remove(row.id, careKey());
                                          if (mounted &&
                                              ref
                                                      .read(authProvider)
                                                      .principal
                                                      ?.session_id ==
                                                  session) {
                                            await load();
                                          }
                                        } catch (e) {
                                          if (mounted &&
                                              ref
                                                      .read(authProvider)
                                                      .principal
                                                      ?.session_id ==
                                                  session) {
                                            setState(() {
                                              error = careError(e);
                                              busy = false;
                                            });
                                          }
                                        }
                                      },
                                child: const Text('取消收藏'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (cursor != null && !busy)
                TextButton(
                  onPressed: () => load(more: true),
                  child: const Text('加载更多'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
