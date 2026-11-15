import 'package:flutter/material.dart';

import 'alert_level_badge.dart';
import '../ui_text.dart';

// EN: Display the current risk state and guidance supplied by the caller.
// TH: แสดงสถานะความเสี่ยงและคำแนะนำที่ผู้เรียกส่งมา โดยไม่ประเมินความเสี่ยงเอง
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.status,
    required this.alertLevel,
    required this.recommendation,
    this.cause = '',
    this.disclaimer = '',
  });

  final String
      status; // EN: User-facing status text. TH: ข้อความสถานะสำหรับผู้ใช้
  final String
      alertLevel; // EN: Canonical level for the badge. TH: ระดับมาตรฐานที่ใช้กับป้ายแจ้งเตือน
  final String
      recommendation; // EN: Advice or an unavailable-analysis message. TH: คำแนะนำหรือข้อความว่ายังวิเคราะห์ไม่ได้
  final String
      cause; // EN: Optional AI explanation. TH: สาเหตุจาก AI เมื่อมีข้อมูล
  final String
      disclaimer; // EN: Optional AI caution. TH: ข้อความกำกับจาก AI เมื่อมีข้อมูล

  @override
  Widget build(BuildContext context) {
    // EN: Use tighter spacing on narrow screens. TH: ลดระยะห่างเมื่อหน้าจอแคบ
    final compact = MediaQuery.sizeOf(context).width < 600;
    final textTheme = Theme.of(context).textTheme;
    // EN: Unknown means analysis is unavailable, never a safe result.
    // TH: Unknown หมายถึงยังวิเคราะห์ไม่ได้ ไม่ใช่ผลว่าปลอดภัย
    final analysisUnavailable = alertLevel.toLowerCase() == 'unknown';
    // EN: Match the main status color to the canonical alert level.
    // TH: ให้สีสถานะหลักตรงกับระดับแจ้งเตือนมาตรฐาน
    final statusAccent = switch (alertLevel.toLowerCase()) {
      'safe' => const Color(0xFF34D399),
      'watch' => const Color(0xFFF2C94C),
      'warning' => const Color(0xFFF2994A),
      'emergency' => const Color(0xFFEB5757),
      _ => const Color(0xFF9AA4B2),
    };
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 20),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusAccent.withValues(alpha: 0.45)),
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
                color: statusAccent,
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
              // EN: Render the passed alert level beside its status text.
              // TH: แสดงระดับแจ้งเตือนที่ได้รับข้างข้อความสถานะ
              AlertLevelBadge(level: alertLevel),
            ],
          ),
          SizedBox(height: compact ? 10 : 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1622),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusAccent.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      analysisUnavailable
                          ? Icons.info_outline_rounded
                          : Icons.tips_and_updates_outlined,
                      size: 18,
                      color: statusAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      uiText(context,
                          english: analysisUnavailable
                              ? 'Analysis status'
                              : 'Recommendation',
                          thai: analysisUnavailable
                              ? 'สถานะการวิเคราะห์'
                              : 'คำแนะนำ'),
                      style: TextStyle(
                        color: statusAccent,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                // EN: Show an explanation only when one was provided.
                // TH: แสดงสาเหตุเฉพาะเมื่อได้รับข้อความมา
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
          // EN: Keep optional AI cautions visible below the guidance.
          // TH: แสดงข้อความกำกับ AI ใต้คำแนะนำเมื่อมีข้อมูล
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
