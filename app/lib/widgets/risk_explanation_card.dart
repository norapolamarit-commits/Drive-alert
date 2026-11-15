import 'package:flutter/material.dart';

import '../models/risk_result.dart';
import '../ui_text.dart';

// EN: Display evidence from a risk result without computing a new prediction.
// TH: แสดงข้อมูลประกอบผลความเสี่ยง โดยไม่คำนวณคำทำนายใหม่
class RiskExplanationCard extends StatelessWidget {
  const RiskExplanationCard({super.key, required this.risk});

  final RiskResult
      risk; // EN: Result and provenance text to render. TH: ผลและข้อความอธิบายที่จะแสดง

  @override
  Widget build(BuildContext context) {
    // EN: Unknown changes the heading from detected signs to analysis status.
    // TH: เมื่อเป็น Unknown ให้หัวข้อสื่อว่าเป็นสถานะการวิเคราะห์
    final analysisUnavailable = risk.alertLevel == 'Unknown';
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
            uiText(
              context,
              english:
                  analysisUnavailable ? 'Analysis status' : 'Detected signs',
              thai:
                  analysisUnavailable ? 'สถานะการวิเคราะห์' : 'สัญญาณที่ตรวจพบ',
            ),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          // EN: Show each supplied sign as a separate readable item.
          // TH: แสดงสัญญาณแต่ละรายการแยกกันให้อ่านง่าย
          ...risk.detectedSigns.map(
            (sign) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• '),
                  Expanded(
                    child: Text(
                      // EN: Translate known signs and clarify that raw telemetry is not AI inference.
                      // TH: แปลข้อความที่รู้จักและย้ำว่าข้อมูลดิบไม่ใช่ผลวิเคราะห์ AI
                      localizedRiskSign(
                        context,
                        analysisUnavailable &&
                                sign ==
                                    'Connected to ESP32; raw sensor telemetry received.'
                            ? uiText(
                                context,
                                english:
                                    'Raw sensor data received; no risk analysis is available.',
                                thai:
                                    'รับข้อมูลดิบจากเซนเซอร์แล้ว แต่ยังไม่มีผลประเมินความเสี่ยง',
                              )
                            : sign,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
