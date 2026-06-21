import 'package:flutter/material.dart';

class AlertLevelBadge extends StatelessWidget {
  const AlertLevelBadge({super.key, required this.level});

  final String level;

  Color get color => switch (level) {
        'Safe' => const Color(0xFF1B9A59),
        'Watch' => const Color(0xFFF2C94C),
        'Warning' => const Color(0xFFF2994A),
        'Emergency' => const Color(0xFFEB5757),
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        level,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
