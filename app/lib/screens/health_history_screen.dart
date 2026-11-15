import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/sensor_risk_sample.dart';
import '../ui_text.dart';

// EN: Host the device-only sensor history section as a full page.
// TH: แสดงส่วนประวัติเซนเซอร์จริงเป็นหน้าเต็ม
class HealthHistoryScreen extends StatelessWidget {
  const HealthHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [HealthHistorySection()],
    );
  }
}

// EN: Summarize only BLE packets that contain both optical channels.
// TH: สรุปเฉพาะ packet BLE ที่มีข้อมูลแสงทั้งสองช่อง
class HealthHistorySection extends StatefulWidget {
  const HealthHistorySection({super.key});

  @override
  State<HealthHistorySection> createState() => _HealthHistorySectionState();
}

class _HealthHistorySectionState extends State<HealthHistorySection> {
  String _selectedMetricId = 'redMean';

  static const _metrics = [
    _HistoryMetric(
      id: 'redMean',
      title: 'MAX30102 Red mean',
      unit: 'ADC',
      icon: Icons.favorite,
    ),
    _HistoryMetric(
      id: 'irMean',
      title: 'MAX30102 IR mean',
      unit: 'ADC',
      icon: Icons.air,
    ),
    _HistoryMetric(
      id: 'accelX',
      title: 'MPU6050 acceleration X',
      unit: 'm/s²',
      icon: Icons.swap_horiz,
    ),
    _HistoryMetric(
      id: 'accelY',
      title: 'MPU6050 acceleration Y',
      unit: 'm/s²',
      icon: Icons.swap_vert,
    ),
    _HistoryMetric(
      id: 'accelZ',
      title: 'MPU6050 acceleration Z',
      unit: 'm/s²',
      icon: Icons.open_in_full,
    ),
    _HistoryMetric(
      id: 'gyroX',
      title: 'MPU6050 gyroscope X',
      unit: '°/s',
      icon: Icons.screen_rotation_alt,
    ),
    _HistoryMetric(
      id: 'gyroY',
      title: 'MPU6050 gyroscope Y',
      unit: '°/s',
      icon: Icons.screen_rotation,
    ),
    _HistoryMetric(
      id: 'gyroZ',
      title: 'MPU6050 gyroscope Z',
      unit: '°/s',
      icon: Icons.rotate_90_degrees_ccw,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DozState>();
    // EN: Current BLE packets carry both ADC fields; exclude demo and unsupported vitals.
    // TH: packet BLE ปัจจุบันมี ADC สองช่อง จึงตัดค่าเดโมและค่าชีพจรที่ยังไม่รองรับ
    final samples = _takeLast(
      state.sensorRiskHistory
          .where((sample) =>
              sample.sensorData.rawRed != null &&
              sample.sensorData.rawIr != null)
          .toList(),
      120,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Header(),
        const SizedBox(height: 16),
        Text(
          uiText(
            context,
            english:
                'Only real BLE Red/IR and MPU6050 readings are shown. This firmware does not provide HR, SpO₂, ECG, GSR, or skin temperature.',
            thai:
                'แสดงเฉพาะค่า Red/IR และ MPU6050 ที่รับผ่าน BLE จริง เฟิร์มแวร์นี้ยังไม่ส่งค่า HR, SpO₂, ECG, GSR หรืออุณหภูมิผิวหนัง',
          ),
          style: const TextStyle(color: Color(0xFFA7B0C0), height: 1.4),
        ),
        const SizedBox(height: 12),
        if (samples.isEmpty)
          _EmptyHistory(
            message: uiText(
              context,
              english:
                  'No real BLE sensor history yet. Connect the device to begin.',
              thai:
                  'ยังไม่มีประวัติเซนเซอร์จาก BLE จริง เชื่อมต่ออุปกรณ์เพื่อเริ่มเก็บข้อมูล',
            ),
          )
        else
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.9,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              for (final metric in _metrics)
                _MetricSummaryCard(
                  metric: metric,
                  value: _summaryValue(metric.id, samples),
                  samples: samples,
                  selected: metric.id == _selectedMetricId,
                  onTap: () {
                    setState(() => _selectedMetricId = metric.id);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _HistoryDetailScreen(metric: metric),
                      ),
                    );
                  },
                ),
            ],
          ),
      ],
    );
  }

  String _summaryValue(String metricId, List<SensorRiskSample> samples) {
    final values = samples.map((item) => _metricValue(metricId, item));
    return values.average().toStringAsFixed(1);
  }

  List<T> _takeLast<T>(List<T> items, int count) {
    if (items.length <= count) return items;
    return items.sublist(items.length - count);
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Text(
      uiText(context,
          english: 'Sensor Data History', thai: 'ประวัติข้อมูลเซนเซอร์'),
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
    );
  }
}

// EN: Show the mean and a short trend for one supported physical measurement.
// TH: แสดงค่าเฉลี่ยและแนวโน้มสั้นของค่าที่อุปกรณ์วัดจริงหนึ่งชนิด
class _MetricSummaryCard extends StatelessWidget {
  const _MetricSummaryCard({
    required this.metric,
    required this.value,
    required this.samples,
    required this.selected,
    required this.onTap,
  });

  final _HistoryMetric metric;
  final String value;
  final List<SensorRiskSample> samples;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(compact ? 10 : 12),
          decoration: BoxDecoration(
            color: const Color(0xFF11141B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? Colors.white : const Color(0xFF232833),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    metric.icon,
                    color: const Color(0xFFEF4444),
                    size: compact ? 22 : 26,
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right,
                    color: selected ? Colors.white : const Color(0xFFA7B0C0),
                    size: 20,
                  ),
                ],
              ),
              SizedBox(height: compact ? 7 : 10),
              Text(
                _localizedMetricTitle(context, metric),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: (compact ? textTheme.labelMedium : textTheme.labelLarge)
                    ?.copyWith(
                  color: const Color(0xFFA7B0C0),
                  height: 1.15,
                ),
              ),
              SizedBox(height: compact ? 8 : 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      style: (compact
                              ? textTheme.titleMedium
                              : textTheme.titleLarge)
                          ?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                    if (metric.unit.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 1),
                        child: Text(
                          metric.unit,
                          style: const TextStyle(color: Color(0xFFA7B0C0)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: compact ? 8 : 10),
              Expanded(
                child: _MetricSparklineChart(
                  metric: metric,
                  samples: samples,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// EN: Draw a compact trend from at most 24 recent physical readings.
// TH: วาดแนวโน้มย่อจากค่าจริงล่าสุดไม่เกิน 24 รายการ
class _MetricSparklineChart extends StatelessWidget {
  const _MetricSparklineChart({
    required this.metric,
    required this.samples,
  });

  final _HistoryMetric metric;
  final List<SensorRiskSample> samples;

  @override
  Widget build(BuildContext context) {
    final chartSamples = samples.length > 24
        ? samples.sublist(samples.length - 24)
        : samples.toList();
    final spots = List.generate(
      chartSamples.length,
      (index) => FlSpot(
        index.toDouble(),
        _metricValue(metric.id, chartSamples[index]),
      ),
    );
    final values = spots.map((spot) => spot.y).toList();
    final minY = values.isEmpty ? 0.0 : values.reduce((a, b) => a < b ? a : b);
    final maxY = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    final yPadding = (maxY - minY).abs() < 1 ? 1.0 : (maxY - minY) * 0.15;

    if (spots.isEmpty) {
      return Center(
        child: Text(
          uiText(context, english: 'No graph data', thai: 'ยังไม่มีข้อมูลกราฟ'),
          style: const TextStyle(color: Color(0xFFA7B0C0), fontSize: 11),
        ),
      );
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: spots.length <= 1 ? 1 : (spots.length - 1).toDouble(),
        minY: minY - yPadding,
        maxY: maxY + yPadding,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: const Color(0xFFEF4444),
            barWidth: 2.5,
            isCurved: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFFEF4444).withValues(alpha: 0.14),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallStat extends StatelessWidget {
  const _SmallStat({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final double value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0D12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFFA7B0C0))),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _formatMetricValue(value, unit),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountStat extends StatelessWidget {
  const _CountStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0D12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFFA7B0C0))),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.time,
    required this.value,
    required this.subtitle,
  });

  final String time;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0D12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF232833)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFA7B0C0)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0D12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message ??
            uiText(context,
                english: 'No history data yet.', thai: 'ยังไม่มีข้อมูลประวัติ'),
        style: const TextStyle(color: Color(0xFFA7B0C0)),
      ),
    );
  }
}

// EN: Open a time-grouped detail page for a selected sensor channel.
// TH: เปิดหน้ารายละเอียดแยกตามช่วงเวลาของช่องเซนเซอร์ที่เลือก
class _HistoryDetailScreen extends StatefulWidget {
  const _HistoryDetailScreen({required this.metric});

  final _HistoryMetric metric;

  @override
  State<_HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<_HistoryDetailScreen> {
  String _range = 'Day';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DozState>();
    final samples = state.sensorRiskHistory
        .where((sample) =>
            sample.sensorData.rawRed != null && sample.sensorData.rawIr != null)
        .toList();
    final bars = _buildBarData(widget.metric, samples, _range);
    final values = bars.map((item) => item.value);
    final average = values.average();
    final maxValue =
        values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);

    return Scaffold(
      backgroundColor: const Color(0xFF050608),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _localizedMetricTitle(context, widget.metric),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Day', label: Text('Day')),
                ButtonSegment(value: 'Week', label: Text('Week')),
                ButtonSegment(value: 'Month', label: Text('Month')),
                ButtonSegment(value: 'Year', label: Text('Year')),
              ],
              selected: {_range},
              onSelectionChanged: (value) => setState(() {
                _range = value.first;
              }),
            ),
            const SizedBox(height: 16),
            _DetailStatRow(
              metric: widget.metric,
              average: average,
              maxValue: maxValue,
              count: bars.length,
            ),
            const SizedBox(height: 16),
            _HistoryBarChart(
              metric: widget.metric,
              bars: bars,
              range: _range,
            ),
            const SizedBox(height: 16),
            _HistoryValueList(metric: widget.metric, bars: bars),
          ],
        ),
      ),
    );
  }
}

class _DetailStatRow extends StatelessWidget {
  const _DetailStatRow({
    required this.metric,
    required this.average,
    required this.maxValue,
    required this.count,
  });

  final _HistoryMetric metric;
  final double average;
  final double maxValue;
  final int count;

  @override
  Widget build(BuildContext context) {
    final averageLabel = uiText(context, english: 'Average', thai: 'ค่าเฉลี่ย');
    final maxLabel = uiText(context, english: 'Maximum', thai: 'ค่าสูงสุด');
    return Row(
      children: [
        Expanded(
          child: _SmallStat(
            label: averageLabel,
            value: average,
            unit: metric.unit,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SmallStat(
            label: maxLabel,
            value: maxValue,
            unit: metric.unit,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
            child: _CountStat(
                label:
                    uiText(context, english: 'Samples', thai: 'จำนวนตัวอย่าง'),
                value: count)),
      ],
    );
  }
}

// EN: Plot mean readings by time bucket, including signed gyroscope values.
// TH: วาดค่าเฉลี่ยตามช่วงเวลา รวมค่าการหมุนที่อาจติดลบ
class _HistoryBarChart extends StatelessWidget {
  const _HistoryBarChart({
    required this.metric,
    required this.bars,
    required this.range,
  });

  final _HistoryMetric metric;
  final List<_HistoryBarData> bars;
  final String range;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    // EN: Include zero and both signed extremes so negative gyro bars remain visible.
    // TH: ให้แกนครอบคลุมศูนย์และค่าทั้งสองทิศเพื่อไม่ตัดแท่ง gyro ที่ติดลบ
    final values = bars.map((item) => item.value).toList();
    final minValue =
        values.isEmpty ? 0.0 : values.reduce((a, b) => a < b ? a : b);
    final maxValue =
        values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    final span = (maxValue - minValue).abs();
    final padding = span < 1 ? 1.0 : span * 0.18;
    final chartMinY = minValue < 0 ? minValue - padding : 0.0;
    final chartMaxY = maxValue > 0 ? maxValue + padding : 0.0;

    return Container(
      height: compact ? 320 : 380,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF232833)),
      ),
      child: bars.isEmpty
          ? const Center(child: _EmptyHistory())
          : BarChart(
              BarChartData(
                minY: chartMinY,
                maxY: chartMaxY <= chartMinY ? chartMinY + 1 : chartMaxY,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => const FlLine(
                    color: Color(0xFF232833),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: const Border(
                    left: BorderSide(color: Color(0xFF343B4A)),
                    bottom: BorderSide(color: Color(0xFF343B4A)),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    axisNameWidget:
                        _ChartAxisName(_metricAxisName(context, metric)),
                    axisNameSize: 20,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: compact ? 34 : 42,
                      getTitlesWidget: (value, meta) =>
                          _ChartAxisLabel(_formatShortMetric(value)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget:
                        _ChartAxisName(_rangeAxisName(context, range)),
                    axisNameSize: 22,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        final index = value.round();
                        if (index < 0 || index >= bars.length) {
                          return const SizedBox.shrink();
                        }
                        if (!_shouldShowBarLabel(index, bars.length)) {
                          return const SizedBox.shrink();
                        }
                        return _ChartAxisLabel(bars[index].label);
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var index = 0; index < bars.length; index++)
                    BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: bars[index].value,
                          color: const Color(0xFFEF4444),
                          width: compact ? 10 : 16,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

class _HistoryValueList extends StatelessWidget {
  const _HistoryValueList({
    required this.metric,
    required this.bars,
  });

  final _HistoryMetric metric;
  final List<_HistoryBarData> bars;

  @override
  Widget build(BuildContext context) {
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
          Text(
            uiText(context, english: 'Values', thai: 'ค่า'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          if (bars.isEmpty)
            const _EmptyHistory()
          else
            ...bars.reversed.map(
              (item) => _HistoryRow(
                time: item.fullLabel,
                value: _formatMetricValue(item.value, metric.unit),
                subtitle: uiText(context,
                    english:
                        'Average ${_localizedMetricTitle(context, metric)}',
                    thai:
                        'ค่าเฉลี่ย ${_localizedMetricTitle(context, metric)}'),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryBarData {
  const _HistoryBarData({
    required this.key,
    required this.label,
    required this.fullLabel,
    required this.value,
  });

  final String key;
  final String label;
  final String fullLabel;
  final double value;
}

List<_HistoryBarData> _buildBarData(
  _HistoryMetric metric,
  List<SensorRiskSample> samples,
  String range,
) {
  // EN: Group recent physical readings by the selected time granularity.
  // TH: รวมค่าจริงล่าสุดตามหน่วยช่วงเวลาที่เลือก
  final now = DateTime.now();
  final cutoff = switch (range) {
    'Day' => now.subtract(const Duration(hours: 24)),
    'Week' => now.subtract(const Duration(days: 7)),
    'Month' => now.subtract(const Duration(days: 30)),
    'Year' => DateTime(now.year - 1, now.month, now.day),
    _ => now.subtract(const Duration(hours: 24)),
  };
  final filtered = samples
      .where((sample) => !sample.sensorData.timestamp.isBefore(cutoff))
      .toList();
  final buckets = <String, List<double>>{};
  final labels = <String, String>{};
  final fullLabels = <String, String>{};

  for (final sample in filtered) {
    final timestamp = sample.sensorData.timestamp;
    final key = _bucketKey(timestamp, range);
    buckets.putIfAbsent(key, () => []).add(_metricValue(metric.id, sample));
    labels[key] = _bucketLabel(timestamp, range);
    fullLabels[key] = _bucketFullLabel(timestamp, range);
  }

  final keys = buckets.keys.toList()..sort();
  return [
    for (final key in keys)
      _HistoryBarData(
        key: key,
        label: labels[key] ?? key,
        fullLabel: fullLabels[key] ?? key,
        value: buckets[key]!.average(),
      ),
  ];
}

String _bucketKey(DateTime timestamp, String range) {
  return switch (range) {
    'Day' =>
      '${timestamp.year}${_two(timestamp.month)}${_two(timestamp.day)}${_two(timestamp.hour)}',
    'Week' => '${timestamp.year}${_two(timestamp.month)}${_two(timestamp.day)}',
    'Month' =>
      '${timestamp.year}${_two(timestamp.month)}${_two(timestamp.day)}',
    'Year' => '${timestamp.year}${_two(timestamp.month)}',
    _ =>
      '${timestamp.year}${_two(timestamp.month)}${_two(timestamp.day)}${_two(timestamp.hour)}',
  };
}

String _bucketLabel(DateTime timestamp, String range) {
  return switch (range) {
    'Day' => '${timestamp.hour}.00',
    'Week' => '${timestamp.day}/${timestamp.month}',
    'Month' => '${timestamp.day}',
    'Year' => _monthLabel(timestamp.month),
    _ => '${timestamp.hour}.00',
  };
}

String _bucketFullLabel(DateTime timestamp, String range) {
  final day = _two(timestamp.day);
  final month = _two(timestamp.month);
  return switch (range) {
    'Day' => '$day/$month ${_two(timestamp.hour)}.00น.',
    'Week' => '$day/$month/${timestamp.year}',
    'Month' => '$day/$month/${timestamp.year}',
    'Year' => '${_monthLabel(timestamp.month)} ${timestamp.year}',
    _ => '$day/$month ${_two(timestamp.hour)}.00น.',
  };
}

String _rangeAxisName(BuildContext context, String range) {
  final isThai = Localizations.localeOf(context).languageCode == 'th';
  return switch (range) {
    'Day' => isThai ? 'ชั่วโมง' : 'Hour',
    'Week' => isThai ? 'วัน' : 'Day',
    'Month' => isThai ? 'วัน' : 'Day',
    'Year' => isThai ? 'เดือน' : 'Month',
    _ => isThai ? 'เวลา' : 'Time',
  };
}

String _metricAxisName(BuildContext context, _HistoryMetric metric) {
  return metric.unit.isEmpty
      ? _localizedMetricTitle(context, metric)
      : metric.unit;
}

String _localizedMetricTitle(BuildContext context, _HistoryMetric metric) {
  final isThai = Localizations.localeOf(context).languageCode == 'th';
  return switch (metric.id) {
    'redMean' => isThai ? 'ค่าเฉลี่ย Red (MAX30102)' : 'MAX30102 Red mean',
    'irMean' => isThai ? 'ค่าเฉลี่ย IR (MAX30102)' : 'MAX30102 IR mean',
    'accelX' => isThai ? 'ความเร่งแกน X (MPU6050)' : 'MPU6050 acceleration X',
    'accelY' => isThai ? 'ความเร่งแกน Y (MPU6050)' : 'MPU6050 acceleration Y',
    'accelZ' => isThai ? 'ความเร่งแกน Z (MPU6050)' : 'MPU6050 acceleration Z',
    'gyroX' => isThai ? 'ไจโรสโคปแกน X (MPU6050)' : 'MPU6050 gyroscope X',
    'gyroY' => isThai ? 'ไจโรสโคปแกน Y (MPU6050)' : 'MPU6050 gyroscope Y',
    'gyroZ' => isThai ? 'ไจโรสโคปแกน Z (MPU6050)' : 'MPU6050 gyroscope Z',
    _ => metric.title,
  };
}

String _formatShortMetric(double value) {
  if (value.abs() >= 100 || value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}

bool _shouldShowBarLabel(int index, int length) {
  if (length <= 8) return true;
  if (index == 0 || index == length - 1) return true;
  final interval = (length / 5).ceil();
  return index % interval == 0;
}

String _monthLabel(int month) {
  const labels = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return labels[(month - 1).clamp(0, 11)];
}

String _two(int value) => value.toString().padLeft(2, '0');

class _ChartAxisName extends StatelessWidget {
  const _ChartAxisName(this.text);

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

class _ChartAxisLabel extends StatelessWidget {
  const _ChartAxisLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: Color(0xFFA7B0C0), fontSize: 10),
    );
  }
}

class _HistoryMetric {
  const _HistoryMetric({
    required this.id,
    required this.title,
    required this.unit,
    required this.icon,
  });

  final String id;
  final String title;
  final String unit;
  final IconData icon;
}

double _metricValue(String metricId, SensorRiskSample sample) {
  return switch (metricId) {
    'redMean' => sample.sensorData.rawRed?.toDouble() ?? 0,
    'irMean' => sample.sensorData.rawIr?.toDouble() ?? 0,
    'accelX' => sample.sensorData.accelX,
    'accelY' => sample.sensorData.accelY,
    'accelZ' => sample.sensorData.accelZ,
    'gyroX' => sample.sensorData.gyroX,
    'gyroY' => sample.sensorData.gyroY,
    'gyroZ' => sample.sensorData.gyroZ,
    _ => 0,
  };
}

String _formatMetricValue(num value, String unit) {
  final text =
      value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);
  return unit.isEmpty ? text : '$text $unit';
}

extension _AverageNum on Iterable<num> {
  double average() {
    var count = 0;
    final total = fold<double>(0, (sum, value) {
      count += 1;
      return sum + value.toDouble();
    });
    return count == 0 ? 0 : total / count;
  }
}
