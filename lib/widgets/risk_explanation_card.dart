import 'package:flutter/material.dart';

import '../models/risk_result.dart';

class RiskExplanationCard extends StatelessWidget {
  const RiskExplanationCard({super.key, required this.risk});

  final RiskResult risk;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF232833)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'สัญญาณที่ตรวจพบ',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          ...risk.detectedSigns.map(
            (sign) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• '),
                  Expanded(child: Text(sign)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
