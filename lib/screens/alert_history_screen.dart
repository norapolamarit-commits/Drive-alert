import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/alert_record.dart';
import '../widgets/alert_level_badge.dart';
import '../widgets/status_card.dart';

class AlertHistoryScreen extends StatelessWidget {
  const AlertHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
        if (alerts.isNotEmpty) _LatestResponseButtons(),
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

class _LatestResponseButtons extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ResponseButton(label: 'I am safe'),
        _ResponseButton(label: 'I stopped safely'),
        _ResponseButton(label: 'Contact emergency person'),
      ],
    );
  }
}

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
