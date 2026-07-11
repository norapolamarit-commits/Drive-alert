import 'package:flutter/material.dart';

import 'alert_level_badge.dart';

class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.status,
    required this.alertLevel,
    required this.recommendation,
    this.cause = '',
    this.disclaimer = '',
  });

  final String status;
  final String alertLevel;
  final String recommendation;
  final String cause; // สาเหตุที่ตรวจพบ (จาก AI advice, ถ้ามี)
  final String disclaimer; // ข้อความปฏิเสธความรับผิด (จาก AI advice, ถ้ามี)

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 20),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF232833)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.health_and_safety_outlined,
                size: compact ? 26 : 32,
              ),
              SizedBox(width: compact ? 10 : 12),
              Expanded(
                child: Text(
                  status,
                  style:
                      (compact ? textTheme.titleLarge : textTheme.headlineSmall)
                          ?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              AlertLevelBadge(level: alertLevel),
            ],
          ),
          SizedBox(height: compact ? 10 : 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1622),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E3A2F)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.tips_and_updates_outlined,
                        size: 18, color: Color(0xFF34D399)),
                    SizedBox(width: 6),
                    Text(
                      'คำแนะนำ',
                      style: TextStyle(
                        color: Color(0xFF34D399),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                if (cause.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    cause,
                    style: const TextStyle(
                      color: Color(0xFFA7B0C0),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  recommendation,
                  style: (compact ? textTheme.bodyMedium : textTheme.bodyLarge)
                      ?.copyWith(color: Colors.white, height: 1.3),
                ),
              ],
            ),
          ),
          if (disclaimer.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              disclaimer,
              style: const TextStyle(
                color: Color(0xFF6B7484),
                fontSize: 11,
                fontStyle: FontStyle.italic,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
