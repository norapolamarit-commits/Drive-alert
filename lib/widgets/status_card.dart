import 'package:flutter/material.dart';

import 'alert_level_badge.dart';

class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.status,
    required this.alertLevel,
    required this.recommendation,
  });

  final String status;
  final String alertLevel;
  final String recommendation;

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
          Text(
            recommendation,
            style: (compact ? textTheme.bodyMedium : textTheme.bodyLarge)
                ?.copyWith(color: Colors.white, height: 1.25),
          ),
        ],
      ),
    );
  }
}
