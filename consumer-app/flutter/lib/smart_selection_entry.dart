import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'reference_ui.dart';

class SmartSelectionEntry extends StatelessWidget {
  const SmartSelectionEntry({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: math.min(256, MediaQuery.sizeOf(context).width - 32),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2026342d),
            blurRadius: 24,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: TextButton(
        key: const Key('smart-selection-entry'),
        onPressed: () => context.go('/ai'),
        style: TextButton.styleFrom(
          backgroundColor: PawdayDesign.white,
          foregroundColor: PawdayDesign.ink,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          minimumSize: const Size(0, 64),
          shape: const StadiumBorder(),
        ),
        child: Row(
          children: [
            ClipOval(
              child: Image.asset(
                PawdayDesign.image('note-cat'),
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '智能选品',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 3),
                  Text(
                    '和你一起慢慢挑好物',
                    style: TextStyle(fontSize: 11, color: PawdayDesign.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward, size: 18),
          ],
        ),
      ),
    ),
  );
}
