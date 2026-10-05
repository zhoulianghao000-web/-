import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'repositories.dart';
import 'api/client.dart';
import 'api/generated/dto.dart';
import 'pet_screen.dart';
import 'catalog_screen.dart';

class TabShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const TabShell({super.key, required this.shell});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: shell,
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (index) =>
          shell.goBranch(index, initialLocation: index == shell.currentIndex),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: '首页'),
        NavigationDestination(
          icon: Icon(Icons.grid_view_outlined),
          label: '分类',
        ),
        NavigationDestination(icon: Icon(Icons.pets_outlined), label: '宠物'),
        NavigationDestination(icon: Icon(Icons.place_outlined), label: '附近'),
        NavigationDestination(icon: Icon(Icons.person_outline), label: '我的'),
      ],
    ),
  );
}

class TabScreen extends ConsumerWidget {
  final String path;
  const TabScreen({super.key, required this.path});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (path == '/pets') return const PetsScreen();
    if (path == '/categories') return const CatalogScreen();
    final auth = ref.watch(authProvider), pet = ref.watch(currentPetProvider);
    final title = {
      '/home': '爪日 Pawday',
      '/categories': '发现适合它的好物',
      '/pets': '我的宠物',
      '/nearby': '发现身边的友好',
      '/me': '我的爪日',
    }[path]!;
    final loggedIn = auth.principal != null;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        key: PageStorageKey(path),
        padding: const EdgeInsets.all(24),
        children: [
          if (path == '/home') ...[
            const Text(
              '每一天，认真照顾。',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text('从一份合适的食物，到一次安心的陪伴。'),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.pets),
                title: Text(pet?.name ?? '选择宠物，了解它的需要'),
                subtitle: const Text('你的当前宠物会在首页和宠物页共享'),
                onTap: () => context.go('/pets'),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '陪伴，各有不同',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              children: [
                for (final name in ['猫', '狗', '水族 / 水宠', '鸟', '小宠'])
                  ActionChip(
                    label: Text(name),
                    onPressed: () => context.go('/categories'),
                  ),
              ],
            ),
          ],
          if (path == '/categories') ...[
            const Text('为不同的伙伴，找到不同的照顾。'),
            const SizedBox(height: 20),
            for (final name in ['猫', '狗', '水族 / 水宠', '鸟', '小宠'])
              Card(
                child: ListTile(
                  leading: const Icon(Icons.pets_outlined),
                  title: Text(name),
                  subtitle: const Text('商品分类即将开放'),
                ),
              ),
          ],
          if (path == '/pets') ...[
            if (pet != null)
              Card(
                child: ListTile(
                  title: Text(pet.name),
                  subtitle: const Text('当前宠物'),
                ),
              ),
            const Icon(Icons.pets, size: 72),
            const SizedBox(height: 20),
            const Text(
              '让每一份照顾，更了解它',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22),
            ),
            const SizedBox(height: 12),
            const Text('宠物档案功能即将开放。', textAlign: TextAlign.center),
          ],
          if (path == '/nearby') ...[
            const Icon(Icons.place_outlined, size: 72),
            const SizedBox(height: 24),
            const Text('一起发现身边的宠物友好地点', style: TextStyle(fontSize: 22)),
            const SizedBox(height: 12),
            const Text('附近地点功能即将开放，无需现在授权位置。'),
          ],
          if (path == '/me') ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(loggedIn ? '已登录' : '欢迎来到爪日'),
                subtitle: Text(loggedIn ? '你的照顾日常，从这里开始。' : '登录后管理你的宠物与账号。'),
              ),
            ),
            if (!loggedIn)
              FilledButton(
                onPressed: () => context.push('/auth/login?returnTo=%2Fme'),
                child: const Text('手机号登录'),
              ),
            if (loggedIn) ...[
              ListTile(
                title: const Text('我的订单'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/orders'),
              ),
              ListTile(
                title: const Text('购物车'),
                trailing: const Icon(Icons.shopping_cart_outlined),
                onTap: () => context.push('/cart'),
              ),
              ListTile(
                leading: const Icon(Icons.devices),
                title: const Text('登录设备'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/sessions'),
              ),
              OutlinedButton(
                onPressed: () async {
                  try {
                    await ref.read(authProvider.notifier).logout();
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('本机已退出，请稍后检查其他设备会话。')),
                      );
                    }
                  }
                },
                child: const Text('退出登录'),
              ),
            ],
            if (auth.error != null)
              Text(auth.error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  final String returnTo;
  const LoginScreen({super.key, required this.returnTo});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final phone = TextEditingController(), code = TextEditingController();
  bool busy = false, agreed = false;
  String? message;
  DateTime? nextCodeAt;
  String normalizedPhone() {
    final value = phone.text.trim();
    return value.startsWith('+') ? value : '+86$value';
  }

  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    if (!agreed) {
      setState(() => message = '请先确认同意登录及账号数据处理。');
      return;
    }
    if (!RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(normalizedPhone())) {
      setState(() => message = '请输入有效手机号。');
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => message = error is ApiFailure ? '登录请求失败：$error' : '连接失败，请稍后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> sendCode() => perform(() async {
    if (nextCodeAt != null && DateTime.now().isBefore(nextCodeAt!)) {
      setState(() => message = '请稍后再发送验证码。');
      return;
    }
    await ref.read(consumerRepositoryProvider).requestCode(normalizedPhone());
    nextCodeAt = DateTime.now().add(const Duration(seconds: 60));
    if (mounted) setState(() => message = '验证码请求已受理，请留意短信。');
  });
  Future<void> login() => perform(() async {
    if (!RegExp(r'^\d{6}$').hasMatch(code.text)) {
      setState(() => message = '请输入 6 位验证码。');
      return;
    }
    await ref.read(authProvider.notifier).login(normalizedPhone(), code.text);
    code.clear();
    if (mounted) context.go(widget.returnTo);
  });
  @override
  void dispose() {
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('手机号登录'),
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => context.go('/home'),
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(28),
          children: [
            const Text(
              '欢迎来到爪日',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text('让每一天的照顾，都更安心。'),
            const SizedBox(height: 28),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: const InputDecoration(
                labelText: '手机号',
                hintText: '支持 +86 国际格式',
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: code,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 6,
              decoration: const InputDecoration(labelText: '验证码'),
            ),
            TextButton(
              onPressed: busy ? null : sendCode,
              child: const Text('发送验证码'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: agreed,
              onChanged: busy
                  ? null
                  : (value) => setState(() => agreed = value ?? false),
              title: const Text(
                '同意使用手机号创建或登录账号，并处理必要的账号与设备数据。',
                style: TextStyle(fontSize: 12),
              ),
            ),
            if (message != null)
              Text(
                message!,
                key: const Key('login-message'),
                style: const TextStyle(color: Color(0xffa23d2d)),
              ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: busy ? null : login,
              child: Text(busy ? '正在处理…' : '登录'),
            ),
          ],
        ),
      ),
    ),
  );
}

class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});
  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  late Future<List<Session>> items;
  @override
  void initState() {
    super.initState();
    items = ref.read(consumerRepositoryProvider).sessions();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('登录设备'),
      leading: BackButton(onPressed: () => context.go('/me')),
    ),
    body: FutureBuilder<List<Session>>(
      future: items,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('读取设备失败：${snapshot.error}'),
                TextButton(
                  onPressed: () => setState(
                    () =>
                        items = ref.read(consumerRepositoryProvider).sessions(),
                  ),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }
        if (snapshot.data!.isEmpty) return const Center(child: Text('暂无设备记录。'));
        return ListView(
          children: [
            for (final item in snapshot.data!)
              ListTile(
                leading: const Icon(Icons.devices),
                title: Text(
                  item.id == ref.read(authProvider).principal?.session_id
                      ? '当前设备'
                      : '其他设备',
                ),
                subtitle: Text(
                  '${item.device_id}\n${item.revoked_at == null ? '有效至 ${item.expires_at}' : '已注销'}',
                ),
              ),
          ],
        );
      },
    ),
  );
}
