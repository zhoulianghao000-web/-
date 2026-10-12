import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/generated/dto.dart';
import 'pet_repository.dart';
import 'reference_ui.dart';

/// Accept human date separators, but never DateTime's overflowing day/month normalization.
String? normalizePetBirthday(String input, {DateTime? today}) {
  final match = RegExp(r'^\s*(\d{4})[-/年\s]+(\d{1,2})[-/月\s]+(\d{1,2})日?\s*$')
      .firstMatch(input);
  if (match == null) return null;
  final y = int.parse(match[1]!),
      m = int.parse(match[2]!),
      d = int.parse(match[3]!);
  final date = DateTime(y, m, d), now = today ?? DateTime.now();
  if (y < 1900 ||
      date.year != y ||
      date.month != m ||
      date.day != d ||
      date.isAfter(DateTime(now.year, now.month, now.day))) {
    return null;
  }
  return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
}

String petAgeLabel(Pet pet, {DateTime? today}) {
  final now = today ?? DateTime.now();
  int? months = pet.age_estimate_months;
  if (pet.birth_date != null) {
    final birth = DateTime.tryParse(pet.birth_date!);
    if (birth != null) {
      if (birth.isAfter(DateTime(now.year, now.month, now.day))) return '年龄待补充';
      months =
          (now.year - birth.year) * 12 +
          now.month -
          birth.month -
          (now.day < birth.day ? 1 : 0);
      if (months < 1) return '未满 1 个月';
    }
  }
  if (months == null) return '年龄待补充';
  final years = months ~/ 12, rest = months % 12;
  return '${pet.birth_date == null ? '约 ' : ''}${years > 0 ? '$years 岁' : ''}${years > 0 && rest > 0 ? ' ' : ''}${rest > 0 || years == 0 ? '$rest 个月' : ''}';
}

// Convenience owner-entered labels, never IDs or verified breed/health classifications.
const ownerBreedSuggestions = <String, List<String>>{
  'CAT': ['中华田园猫', '英国短毛猫', '美国短毛猫', '布偶猫', '暹罗猫', '波斯猫', '缅因猫', '混种猫'],
  'DOG': [
    '中华田园犬',
    '金毛寻回犬',
    '拉布拉多寻回犬',
    '贵宾犬',
    '比熊犬',
    '柯基犬',
    '柴犬',
    '边境牧羊犬',
    '德国牧羊犬',
    '博美犬',
    '雪纳瑞',
    '哈士奇',
    '混种犬',
  ],
  'SMALL_PET': ['兔', '仓鼠', '豚鼠', '龙猫', '刺猬'],
  'BIRD': ['虎皮鹦鹉', '玄凤鹦鹉', '文鸟', '金丝雀'],
  'AQUATIC': ['金鱼', '锦鲤', '孔雀鱼', '斗鱼', '观赏虾'],
};

class PetPhoto extends ConsumerWidget {
  final String? asset;
  const PetPhoto({super.key, required this.asset});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget fallback() => const ColoredBox(
      color: PawdayDesign.green,
      child: Center(
        child: Icon(Icons.pets_outlined, size: 80, color: Color(0x55ffffff)),
      ),
    );
    if (asset == null) return fallback();
    return ref
        .watch(petPhotoProvider(asset!))
        .when(
          loading: () => fallback(),
          error: (e, s) => fallback(),
          data: (bytes) => Image.memory(
            bytes,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: (c, e, s) => fallback(),
          ),
        );
  }
}

class ProfileSection extends StatelessWidget {
  final String title, description;
  final Widget child;
  const ProfileSection({
    super.key,
    required this.title,
    required this.description,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Text(
        description,
        style: const TextStyle(color: PawdayDesign.muted, fontSize: 13),
      ),
      const SizedBox(height: 18),
      child,
    ],
  );
}
