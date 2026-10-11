import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repositories.dart';
import 'pilot.dart';

final pilotImageProvider = FutureProvider.autoDispose.family<Uint8List, String>(
  (ref, sku) {
    final session = ref.watch(authProvider).principal;
    if (!pilotMode || session == null) throw StateError('登录后查看测试图片');
    return ref.watch(consumerApiProvider).pilotProductMedia(sku);
  },
);

class PilotProductMedia extends ConsumerWidget {
  final String sku;
  const PilotProductMedia({super.key, required this.sku});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    children: [
      const Text('合成占位图片，仅供测试；非商家授权图片'),
      ref
          .watch(pilotImageProvider(sku))
          .when(
            data: (bytes) => Image.memory(
              bytes,
              width: 96,
              height: 96,
              gaplessPlayback: false,
              errorBuilder: (_, _, _) => const Text('测试图片无法显示'),
            ),
            loading: () => const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(),
            ),
            error: (_, _) => const Text('测试图片暂不可用，请重新登录或刷新'),
          ),
    ],
  );
}
