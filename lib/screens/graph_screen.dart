import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/sensor_data.dart';
import '../models/sensor_risk_sample.dart';
import 'health_history_screen.dart';

class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  bool _showTable = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DzozState>();
    final rawHistory = state.sensorHistory.isEmpty
        ? [state.currentSensor]
        : state.sensorHistory;
    final history = _takeLast(rawHistory, 80);
    final rawSampleHistory = state.sensorRiskHistory.isEmpty
        ? [
            SensorRiskSample(
                sensorData: state.currentSensor, riskResult: state.currentRisk)
          ]
        : state.sensorRiskHistory;
    final sampleHistory = _takeLast(rawSampleHistory, 80);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Health Data',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 16),
        _ChartCard(
            title: 'Heart Rate',
            yAxisTitle: 'BPM',
            spots: _spots(history, (s) => s.heartRate.toDouble()),
            timestamps: _sensorTimes(history)),
        _ChartCard(
            title: 'SpO2',
            yAxisTitle: 'SpO2 (%)',
            spots: _spots(history, (s) => s.spo2.toDouble()),
            timestamps: _sensorTimes(history)),
        _ChartCard(
            title: 'GSR',
            yAxisTitle: 'GSR',
            spots: _spots(history, (s) => s.gsr),
            timestamps: _sensorTimes(history)),
        _ChartCard(
            title: 'Temperature',
            yAxisTitle: 'Temp (C)',
            spots: _spots(history, (s) => s.temperature),
            timestamps: _sensorTimes(history)),
        _ChartCard(
            title: 'Stress Level',
            yAxisTitle: 'Stress',
            spots: _spots(history, (s) => s.stressLevel.toDouble()),
            timestamps: _sensorTimes(history)),
        _ChartCard(
            title: 'Alert Level Trend',
            yAxisTitle: 'Level',
            spots: _alertSpots(sampleHistory),
            timestamps: _sampleTimes(sampleHistory)),
        OutlinedButton.icon(
          onPressed: () => setState(() => _showTable = !_showTable),
          icon: const Icon(Icons.table_chart_outlined),
          label: Text(
              _showTable ? 'Hide sensor data table' : 'Show sensor data table'),
        ),
        if (_showTable) ...[
          const SizedBox(height: 12),
          _SensorTable(samples: sampleHistory),
        ],
        const SizedBox(height: 18),
        const Divider(color: Color(0xFF232833)),
        const SizedBox(height: 10),
        const HealthHistorySection(),
      ],
    );
  }

  List<FlSpot> _spots(
      List<SensorData> items, double Function(SensorData s) value) {
    return List.generate(items.length, (index) {
      final item = items[index];
      return FlSpot(index.toDouble(), value(item));
    });
  }

  List<FlSpot> _alertSpots(List<SensorRiskSample> samples) {
    return List.generate(samples.length, (index) {
      final sample = samples[index];
      return FlSpot(index.toDouble(), sample.riskResult.levelValue.toDouble());
    });
  }

  List<DateTime> _sensorTimes(List<SensorData> items) {
    return items.map((item) => item.timestamp).toList();
  }

  List<DateTime> _sampleTimes(List<SensorRiskSample> samples) {
    return samples.map((sample) => sample.sensorData.timestamp).toList();
  }

  List<T> _takeLast<T>(List<T> items, int count) {
    if (items.length <= count) return items;
    return items.sublist(items.length - count);
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.yAxisTitle,
    required this.spots,
    required this.timestamps,
  });

  final String title;
  final String yAxisTitle;
  final List<FlSpot> spots;
  final List<DateTime> timestamps;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      height: compact ? 240 : 260,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF232833)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Expanded(
            child: LineChart(
              LineChartData(
                minX: _minX(spots),
                maxX: _maxX(spots),
                gridData: const FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 20,
                  getDrawingHorizontalLine: _gridLine,
                ),
                borderData: FlBorderData(
                  show: true,
                  border: const Border(
                    left: BorderSide(color: Color(0xFF343B4A)),
                    bottom: BorderSide(color: Color(0xFF343B4A)),
                  ),
                ),
                titlesData: _axisTitles(spots, timestamps, compact, yAxisTitle),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    dotData: const FlDotData(show: false),
                    color: const Color(0xFFEF4444),
                    barWidth: 3,
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFFEF4444).withValues(alpha: 0.12),
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

FlLine _gridLine(double value) {
  return const FlLine(color: Color(0xFF232833), strokeWidth: 1);
}

FlTitlesData _axisTitles(
  List<FlSpot> spots,
  List<DateTime> timestamps,
  bool compact,
  String yAxisTitle,
) {
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      axisNameWidget: _AxisName(yAxisTitle),
      axisNameSize: compact ? 18 : 20,
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: compact ? 34 : 42,
        interval: _yInterval(spots),
        getTitlesWidget: (value, meta) => _AxisLabel(_formatAxisValue(value)),
      ),
    ),
    bottomTitles: AxisTitles(
      axisNameWidget: const _AxisName('Time (hour)'),
      axisNameSize: 18,
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 38,
        interval: _xInterval(spots),
        getTitlesWidget: (value, meta) {
          if (value < _minX(spots) || value > _maxX(spots)) {
            return const SizedBox.shrink();
          }
          final label = _sampleTimeLabel(value, timestamps);
          if (label == null) return const SizedBox.shrink();
          return _AxisLabel(label);
        },
      ),
    ),
  );
}

double _minX(List<FlSpot> spots) => spots.isEmpty ? 0 : spots.first.x;

double _maxX(List<FlSpot> spots) {
  if (spots.isEmpty) return 0;
  return spots.last.x == spots.first.x ? spots.last.x + 1 : spots.last.x;
}

double _xInterval(List<FlSpot> spots) {
  final labels = _timeLabelValues(spots).toList()..sort();
  if (labels.length < 2) return 1;
  return (labels[1] - labels[0]).abs().clamp(1, double.infinity);
}

double _yInterval(List<FlSpot> spots) {
  if (spots.isEmpty) return 1;
  final values = spots.map((spot) => spot.y);
  final minY = values.reduce((a, b) => a < b ? a : b);
  final maxY = values.reduce((a, b) => a > b ? a : b);
  final range = (maxY - minY).abs();
  if (range <= 5) return 1;
  if (range <= 20) return 5;
  if (range <= 60) return 10;
  return (range / 4).ceilToDouble();
}

String _formatAxisValue(double value) {
  if (value.abs() >= 100 || value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}

String _formatTime(DateTime value) {
  return '${value.hour}.00น.';
}

String? _sampleTimeLabel(double value, List<DateTime> timestamps) {
  if (timestamps.isEmpty) return null;
  final index = value.round();
  if (index < 0 || index >= timestamps.length) return null;
  if (!_timeLabelIndexes(timestamps.length).contains(index)) return null;
  return _formatTime(timestamps[index]);
}

Set<int> _timeLabelIndexes(int length) {
  if (length <= 0) return {};
  if (length <= 4) return List.generate(length, (index) => index).toSet();
  final last = length - 1;
  return {
    0,
    (last * 0.25).round(),
    (last * 0.5).round(),
    (last * 0.75).round(),
    last,
  };
}

Set<double> _timeLabelValues(List<FlSpot> spots) {
  if (spots.isEmpty) return {};
  return _timeLabelIndexes(spots.length)
      .map((index) => spots[index.clamp(0, spots.length - 1)].x)
      .toSet();
}

class _AxisName extends StatelessWidget {
  const _AxisName(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFFA7B0C0),
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _AxisLabel extends StatelessWidget {
  const _AxisLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: Color(0xFFA7B0C0), fontSize: 10),
    );
  }
}

class _SensorTable extends StatelessWidget {
  const _SensorTable({required this.samples});

  final List<SensorRiskSample> samples;

  @override
  Widget build(BuildContext context) {
    final rows = samples.reversed.take(25);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        dataTextStyle: const TextStyle(color: Colors.white),
        columns: const [
          DataColumn(label: Text('Time')),
          DataColumn(label: Text('Heart Rate')),
          DataColumn(label: Text('SpO2')),
          DataColumn(label: Text('GSR')),
          DataColumn(label: Text('Stress Level')),
          DataColumn(label: Text('Temperature')),
          DataColumn(label: Text('Risk Class')),
          DataColumn(label: Text('Alert Level')),
        ],
        rows: rows
            .map(
              (sample) => DataRow(
                cells: [
                  DataCell(Text(DateFormat('HH:mm:ss')
                      .format(sample.sensorData.timestamp))),
                  DataCell(Text('${sample.sensorData.heartRate}')),
                  DataCell(Text('${sample.sensorData.spo2}')),
                  DataCell(Text(sample.sensorData.gsr.toStringAsFixed(0))),
                  DataCell(Text('${sample.sensorData.stressLevel}')),
                  DataCell(
                      Text(sample.sensorData.temperature.toStringAsFixed(1))),
                  DataCell(Text(sample.riskResult.riskClass)),
                  DataCell(Text(sample.riskResult.alertLevel)),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}
