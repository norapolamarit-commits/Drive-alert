import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../models/alert_record.dart';
import '../widgets/alert_level_badge.dart';
import '../widgets/status_card.dart';

// EN: Show recorded alerts and actions for the latest unanswered alert.
// TH: แสดงประวัติ alert และปุ่มตอบรับเฉพาะ alert ล่าสุดที่ยังไม่มีคำตอบ
class AlertHistoryScreen extends StatelessWidget {
  const AlertHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // EN: Rebuild after alerts are added or acknowledged.
    // TH: วาดหน้าใหม่เมื่อมี alert หรือมีการตอบรับ
    final state = context.watch<DozState>();
    final alerts = state.alerts;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Risk Alert Log',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        StatusCard(
          status: state.currentRisk.riskClass,
          alertLevel: state.currentRisk.alertLevel,
          recommendation: state.currentRisk.recommendation,
        ),
        const SizedBox(height: 12),
        _AlertTrend(state: state),
        const SizedBox(height: 12),
        _RiskTypeSummary(alerts: alerts),
        const SizedBox(height: 12),
        // EN: Do not let a second tap overwrite a completed response.
        // TH: ไม่เปิดปุ่มให้กดซ้ำเพื่อเขียนทับคำตอบที่บันทึกแล้ว
        if (alerts.isNotEmpty && alerts.first.userResponse.isEmpty)
          _LatestResponseButtons(),
        const SizedBox(height: 12),
        Text(
          'Alert History',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        if (alerts.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 32),
            child: Center(child: Text('No alert history yet.')),
          )
        else
          ...alerts.map((alert) => _AlertCard(alertId: alert.id)),
      ],
    );
  }
}

// EN: Plot stored alert levels; Unknown is represented separately as -1.
// TH: วาดระดับ alert ที่เก็บไว้ โดย Unknown แยกเป็นค่า -1
class _AlertTrend extends StatelessWidget {
  const _AlertTrend({required this.state});

  final DozState state;

  @override
  Widget build(BuildContext context) {
    final samples = state.sensorRiskHistory;
    return Container(
      height: 190,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF232833)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Alert Level Trend'),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: samples.isEmpty
                        ? [FlSpot(0, state.currentRisk.levelValue.toDouble())]
                        : List.generate(
                            samples.length,
                            (index) => FlSpot(
                              index.toDouble(),
                              samples[index].riskResult.levelValue.toDouble(),
                            ),
                          ),
                    color: const Color(0xFFEF4444),
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
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

// EN: Count alert records by their recorded risk class.
// TH: นับประวัติแจ้งเตือนตามคลาสความเสี่ยงที่บันทึก
class _RiskTypeSummary extends StatelessWidget {
  const _RiskTypeSummary({required this.alerts});

  final List<AlertRecord> alerts;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final alert in alerts) {
      final riskClass = alert.riskResult.riskClass;
      counts[riskClass] = (counts[riskClass] ?? 0) + 1;
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF232833)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Detected Risk Types'),
          const SizedBox(height: 8),
          if (counts.isEmpty)
            const Text('No detected risk types yet.')
          else
            ...counts.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(entry.key)),
                    Text('${entry.value}'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// EN: Offer actions only while the latest alert awaits a response.
// TH: แสดงตัวเลือกเฉพาะตอน alert ล่าสุดยังรอการตอบรับ
class _LatestResponseButtons extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        const _ResponseButton(label: 'I am safe'),
        const _ResponseButton(label: 'I stopped safely'),
        _EmergencyContactButton(
          onPressed: () => _callEmergencyContact(context),
        ),
      ],
    );
  }
}

/// EN: Open the dialer before recording an emergency-contact response.
/// TH: เปิดหน้ากดโทรก่อนบันทึกการตอบรับแบบติดต่อฉุกเฉิน
Future<void> _callEmergencyContact(BuildContext context) async {
  const label = 'Contact emergency person';
  final state = context.read<DozState>();
  final phone = state.emergencyContactPhone.trim();

  // EN: Refuse a call action when the profile has no contact number.
  // TH: ไม่เริ่มโทรเมื่อโปรไฟล์ไม่มีหมายเลขติดต่อ
  if (phone.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No emergency contact number set. Add one in Profile first.',
        ),
      ),
    );
    return;
  }

  final uri = Uri(scheme: 'tel', path: phone);
  final launched = await launchUrl(uri);
  if (!context.mounted) return;
  // EN: Keep the alert unanswered if the phone dialer could not open.
  // TH: คง alert เป็นยังไม่ตอบรับหากเปิดหน้ากดโทรไม่สำเร็จ
  if (!launched) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the phone dialer.')),
    );
    return;
  }
  await state.respondToLatestAlert(label);
}

// EN: Present the dialer action without claiming the call was completed.
// TH: แสดงปุ่มเปิดหน้ากดโทร โดยไม่อ้างว่าโทรสำเร็จแล้ว
class _EmergencyContactButton extends StatelessWidget {
  const _EmergencyContactButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.call, size: 16),
      label: const Text('Contact emergency person'),
    );
  }
}

// EN: Render one persisted alert and its response status.
// TH: แสดง alert ที่บันทึกไว้หนึ่งรายการพร้อมสถานะการตอบรับ
class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alertId});

  final String alertId;

  @override
  Widget build(BuildContext context) {
    final alert = context
        .watch<DozState>()
        .alerts
        .firstWhere((item) => item.id == alertId);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF232833)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  alert.riskResult.riskClass,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              AlertLevelBadge(level: alert.riskResult.alertLevel),
            ],
          ),
          const SizedBox(height: 8),
          Text(DateFormat('dd MMM yyyy HH:mm:ss').format(alert.timestamp)),
          const SizedBox(height: 8),
          Text(alert.riskResult.detectedSigns.join(', ')),
          const SizedBox(height: 8),
          Text(alert.riskResult.recommendation),
          const SizedBox(height: 8),
          Text(
              'User Response: ${alert.userResponse.isEmpty ? 'Pending' : alert.userResponse}'),
        ],
      ),
    );
  }
}

// EN: Save the selected response for the latest alert.
// TH: บันทึกคำตอบที่เลือกสำหรับ alert ล่าสุด
class _ResponseButton extends StatelessWidget {
  const _ResponseButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () => context.read<DozState>().respondToLatestAlert(label),
      child: Text(label),
    );
  }
}
