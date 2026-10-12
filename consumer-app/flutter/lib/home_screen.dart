import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'catalog_repository.dart';
import 'catalog_screen.dart';
import 'reference_ui.dart';
import 'repositories.dart';

final homeProductsProvider = FutureProvider.autoDispose((ref) {
  ref.watch(authProvider.select((auth) => auth.principal?.user_id));
  return ref.watch(catalogRepositoryProvider).browse();
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pet = ref.watch(currentPetProvider);
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, bounds) {
          final mobile = bounds.maxWidth <= 620;
          final padding = mobile ? 14.0 : 28.0;
          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (bounds.maxWidth < 900)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 4,
                          ),
                          child: Row(
                            children: [
                              const PawdayBrand(),
                              const Spacer(),
                              IconButton(
                                tooltip: '购物车',
                                onPressed: () => context.push('/cart'),
                                icon: const Icon(Icons.shopping_cart_outlined),
                              ),
                              IconButton(
                                tooltip: '我的爪日',
                                onPressed: () => context.go('/me'),
                                icon: const Icon(Icons.person_outline),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(height: mobile ? 2 : 42),
                      const _HomeHero(),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: mobile ? 20 : 28,
                        ),
                        child: const Row(
                          children: [
                            _Benefit(
                              icon: Icons.fact_check_outlined,
                              title: '资料透明',
                              subtitle: '查看来源与适配依据',
                            ),
                            _Benefit(
                              icon: Icons.pets_outlined,
                              title: '了解它的需要',
                              subtitle: '宠物档案 · 认真照顾',
                            ),
                            _Benefit(
                              icon: Icons.chat_bubble_outline,
                              title: '贴心答疑',
                              subtitle: '人工客服 · 随时沟通',
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      SizedBox(height: mobile ? 55 : 76),
                      const _SectionTitle(
                        kicker: 'FIND THEIR FAVORITES',
                        title: '今天想给谁挑礼物？',
                        description: '从日常所需，到玩心大发的小惊喜',
                      ),
                      const SizedBox(height: 25),
                      LayoutBuilder(
                        builder: (context, box) {
                          final columns = box.maxWidth > 850 ? 4 : 2;
                          final gap = mobile ? 10.0 : 15.0;
                          return Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: [
                              for (final item in const [
                                (
                                  '猫咪用品',
                                  '给柔软的小主子',
                                  'category-cat',
                                  Color(0xffeee7d9),
                                ),
                                (
                                  '狗狗用品',
                                  '给活力满满的伙伴',
                                  'category-dog',
                                  Color(0xffe2e9dd),
                                ),
                                (
                                  '玩具零食',
                                  '玩耍时间到',
                                  'category-play',
                                  Color(0xfff2e0d2),
                                ),
                                (
                                  '喂养护理',
                                  '认真吃饭每一天',
                                  'category-feed',
                                  Color(0xffe8e3ee),
                                ),
                              ])
                                SizedBox(
                                  width:
                                      (box.maxWidth - gap * (columns - 1)) /
                                      columns,
                                  height: mobile ? 128 : 170,
                                  child: _CategoryCard(
                                    title: item.$1,
                                    subtitle: item.$2,
                                    image: item.$3,
                                    color: item.$4,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      SizedBox(height: mobile ? 62 : 88),
                      Row(
                        children: [
                          const Expanded(
                            child: _SectionTitle(
                              kicker: 'THE LITTLE THINGS THEY LOVE',
                              title: '发现日常好物',
                              description: '商品与报价来自当前在售资料',
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.go('/categories'),
                            child: const Text('查看全部 →'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      ref
                          .watch(homeProductsProvider)
                          .when(
                            loading: () => const LinearProgressIndicator(),
                            error: (_, _) => Row(
                              children: [
                                const Expanded(child: Text('好物暂时无法加载，请稍后重试。')),
                                TextButton(
                                  onPressed: () =>
                                      ref.invalidate(homeProductsProvider),
                                  child: const Text('重试'),
                                ),
                              ],
                            ),
                            data: (page) {
                              final items = page.data.take(4).toList();
                              if (items.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text('暂无在售商品，稍后再来看看。'),
                                );
                              }
                              return LayoutBuilder(
                                builder: (context, box) {
                                  final columns = box.maxWidth > 850 ? 4 : 2;
                                  return GridView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: items.length,
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: columns,
                                          crossAxisSpacing: mobile ? 10 : 17,
                                          mainAxisSpacing: 17,
                                          mainAxisExtent: mobile ? 320 : 355,
                                        ),
                                    itemBuilder: (context, index) =>
                                        ReferenceProductCard(
                                          item: items[index],
                                          imageIndex: index,
                                          onOpen: () => Navigator.push(
                                            context,
                                            MaterialPageRoute<void>(
                                              builder: (_) => ProductScreen(
                                                sku: items[index].id,
                                              ),
                                            ),
                                          ),
                                        ),
                                  );
                                },
                              );
                            },
                          ),
                      SizedBox(height: mobile ? 65 : 100),
                      const _BrandStory(),
                      SizedBox(height: mobile ? 55 : 75),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(mobile ? 23 : 40),
                        decoration: BoxDecoration(
                          color: PawdayDesign.green,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'A NOTE FROM PAWDAY',
                              style: TextStyle(
                                color: PawdayDesign.lime,
                                letterSpacing: 1.5,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              pet == null
                                  ? '让每一份照顾，更了解它。'
                                  : '今天，也认真照顾${pet.name}。',
                              style: const TextStyle(
                                fontSize: 25,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                OutlinedButton(
                                  onPressed: () => context.go('/pets'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                  ),
                                  child: Text(pet?.name ?? '选择宠物，了解它的需要'),
                                ),
                                OutlinedButton(
                                  onPressed: () => context.go('/ai'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('AI 商品资料解释'),
                                ),
                                OutlinedButton(
                                  onPressed: () => context.go('/content'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('食品与养宠知识'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 44),
                      const Divider(),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          '每一天，认真照顾。\n参考图片用于品牌与氛围展示，商品事实以来源资料为准。',
                          style: TextStyle(
                            fontSize: 11,
                            color: PawdayDesign.muted,
                            height: 1.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final mobile = box.maxWidth <= 620;
      final copy = Padding(
        padding: EdgeInsets.fromLTRB(
          mobile
              ? 27
              : box.maxWidth < 1000
              ? 40
              : 88,
          mobile ? 38 : 92,
          mobile ? 27 : 0,
          mobile ? 28 : 84,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '—  MADE FOR LITTLE COMPANIONS',
              style: TextStyle(
                color: PawdayDesign.green,
                letterSpacing: 1.2,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 23),
            Text.rich(
              TextSpan(
                children: const [
                  TextSpan(text: '把爱，装进\n'),
                  TextSpan(
                    text: '每天的陪伴里。',
                    style: TextStyle(color: PawdayDesign.orange),
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: mobile
                    ? 43
                    : (MediaQuery.sizeOf(context).width * .052).clamp(42, 68),
                fontWeight: FontWeight.w800,
                height: 1.15,
                letterSpacing: mobile ? -2.8 : -4,
              ),
            ),
            const SizedBox(height: 17),
            Text(
              '从一顿好好吃饭，到一场尽情玩耍。\n为毛孩子的每个日常，认真挑选安心又可爱的好物。',
              style: TextStyle(
                fontSize: mobile ? 12 : 15,
                height: 1.9,
                color: Color(0xff647067),
              ),
            ),
            const SizedBox(height: 30),
            Wrap(
              spacing: 14,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PawdayButton(
                  onPressed: () => context.go('/categories'),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('发现今日好物'),
                      SizedBox(width: 12),
                      Icon(Icons.arrow_forward, size: 15),
                    ],
                  ),
                ),
                ReferenceTextLink(
                  label: '按宠物选购',
                  onPressed: () => context.go('/pets'),
                ),
              ],
            ),
          ],
        ),
      );
      final photo = SizedBox(
        height: mobile ? 280 : 500,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              PawdayDesign.image('hero-dogs'),
              fit: BoxFit.cover,
              semanticLabel: '一起散步的狗狗',
            ),
            if (!mobile)
              Positioned(
                left: -90,
                top: -25,
                bottom: -25,
                child: Container(
                  width: 190,
                  decoration: BoxDecoration(
                    color: const Color(0xffe7eadb),
                    borderRadius: const BorderRadius.all(
                      Radius.elliptical(95, 275),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: mobile ? 15 : 35,
              top: mobile ? 13 : 50,
              child: Transform.rotate(
                angle: .14,
                child: Container(
                  width: mobile ? 82 : 106,
                  height: mobile ? 82 : 106,
                  decoration: const BoxDecoration(
                    color: PawdayDesign.orange,
                    shape: BoxShape.circle,
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '好奇心',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '每天都要有',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: mobile ? 12 : 24,
              bottom: mobile ? 12 : 25,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 15, 10),
                decoration: BoxDecoration(
                  color: PawdayDesign.white.withValues(alpha: .94),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipOval(
                      child: Image.asset(
                        PawdayDesign.image('note-cat'),
                        width: 37,
                        height: 37,
                        fit: BoxFit.cover,
                        excludeFromSemantics: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '给每一天，加一点可爱',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '和你一起慢慢挑好物',
                          style: TextStyle(
                            fontSize: 10,
                            color: PawdayDesign.muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
      return ClipRRect(
        borderRadius: BorderRadius.circular(mobile ? 21 : 28),
        child: ColoredBox(
          color: const Color(0xffe7eadb),
          child: mobile
              ? Column(children: [copy, photo])
              : Row(
                  children: [
                    Expanded(flex: 20, child: copy),
                    Expanded(flex: 21, child: photo),
                  ],
                ),
        ),
      );
    },
  );
}

class _Benefit extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const _Benefit({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 22, color: PawdayDesign.orange),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 9, color: PawdayDesign.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  final String kicker, title, description;
  const _SectionTitle({
    required this.kicker,
    required this.title,
    required this.description,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        kicker,
        style: const TextStyle(
          color: PawdayDesign.orange,
          fontSize: 10,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        title,
        style: const TextStyle(
          fontSize: 28,
          height: 1.3,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        description,
        style: const TextStyle(fontSize: 11, color: PawdayDesign.muted),
      ),
    ],
  );
}

class _CategoryCard extends StatelessWidget {
  final String title, subtitle, image;
  final Color color;
  const _CategoryCard({
    required this.title,
    required this.subtitle,
    required this.image,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => ReferenceHover(
    lift: 4,
    milliseconds: 250,
    child: const SizedBox.shrink(),
    builder: (hovered) => Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        onTap: () => context.go('/categories'),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: ColoredBox(
            color: color,
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: 150,
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Colors.transparent, Colors.black],
                      stops: [0, .35],
                    ).createShader(bounds),
                    blendMode: BlendMode.dstIn,
                    child: ReferencePhoto(
                      image: image,
                      active: hovered,
                      scale: 1.06,
                      milliseconds: 400,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 10,
                          color: PawdayDesign.muted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: PawdayDesign.white,
                    ),
                    child: const Icon(Icons.arrow_forward, size: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _BrandStory extends StatelessWidget {
  const _BrandStory();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final photo = Image.asset(
        PawdayDesign.image('story-dog'),
        height: 320,
        fit: BoxFit.cover,
        width: double.infinity,
        semanticLabel: '和宠物一起度过的温暖时光',
      );
      final copy = Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A LITTLE MORE LOVE',
              style: TextStyle(
                color: PawdayDesign.orange,
                fontSize: 10,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '好物不必很多，\n刚好适合它就好。',
              style: TextStyle(
                fontSize: 30,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '认真看资料、了解它的需要，也把每一次陪伴放在心上。适配结果以可信来源和宠物档案为依据。',
              style: TextStyle(
                color: PawdayDesign.muted,
                fontSize: 12,
                height: 1.9,
              ),
            ),
            const SizedBox(height: 16),
            ReferenceTextLink(
              label: '认识日常好物',
              onPressed: () => context.go('/categories'),
            ),
          ],
        ),
      );
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ColoredBox(
          color: const Color(0xffe9e2d5),
          child: box.maxWidth <= 620
              ? Column(children: [photo, copy])
              : Row(
                  children: [
                    Expanded(child: photo),
                    Expanded(child: copy),
                  ],
                ),
        ),
      );
    },
  );
}
