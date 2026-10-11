import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repositories.dart';
import 'router.dart';
import 'pilot.dart';

void main() => runApp(const ProviderScope(child: PawdayApp()));

class PawdayApp extends ConsumerStatefulWidget {
  const PawdayApp({super.key});
  @override
  ConsumerState<PawdayApp> createState() => _PawdayAppState();
}

class _PawdayAppState extends ConsumerState<PawdayApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(authProvider.notifier).restore());
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: '爪日 Pawday',
    debugShowCheckedModeBanner: false,
    routerConfig: ref.watch(routerProvider),
    builder: (context, child) => !pilotMode
        ? child!
        : Column(
            children: [
              Material(
                color: const Color(0xfffff1b8),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      pilotLabel,
                      style: const TextStyle(
                        color: Color(0xff5b3b00),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: child!),
            ],
          ),
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff245d4d)),
      scaffoldBackgroundColor: const Color(0xfff5f6ef),
    ),
  );
}
