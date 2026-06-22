import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/sensor_risk_sample.dart';

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

class HealthHistorySection extends StatefulWidget {
  const HealthHistorySection({super.key});

  @override
  State<HealthHistorySection> createState() => _HealthHistorySectionState();
}

class _HealthHistorySectionState extends State<HealthHistorySection> {
  String _selectedMetricId = 'heartRate';

  static const _metrics = [
    _HistoryMetric(
      id: 'heartRate',
      title: 'Average Heart Rate',
      unit: 'BPM',
      icon: Icons.favorite,
    ),
    _HistoryMetric(
      id: 'spo2',
      title: 'Average SpO2',
      unit: '%',
      icon: Icons.air,
    ),
    _HistoryMetric(
      id: 'ecgRate',
      title: 'Average ECG Rate',
      unit: 'BPM',
      icon: Icons.monitor_heart,
    ),
    _HistoryMetric(
      id: 'ecgRrInterval',
      title: 'Average ECG RR',
      unit: 'ms',
      icon: Icons.timeline,
    ),
    _HistoryMetric(
      id: 'ecgHrv',
      title: 'Average ECG HRV',
      unit: 'ms',
      icon: Icons.show_chart,
    ),
    _HistoryMetric(
      id: 'gsr',
      title: 'Average GSR',
      unit: '',
      icon: Icons.sensors,
    ),
    _HistoryMetric(
      id: 'temperature',
      title: 'Average Temperature',
      unit: '°C',
      icon: Icons.thermostat,
    ),
    _HistoryMetric(
      id: 'stress',
      title: 'Average Stress',
      unit: '',
      icon: Icons.bolt,
    ),
    _HistoryMetric(
      id: 'accelX',
      title: 'Average Accel X',
      unit: 'g',
      icon: Icons.swap_horiz,
    ),
    _HistoryMetric(
      id: 'accelY',
      title: 'Average Accel Y',
      unit: 'g',
      icon: Icons.swap_vert,
    ),
    _HistoryMetric(
      id: 'accelZ',
      title: 'Average Accel Z',
      unit: 'g',
      icon: Icons.open_in_full,
    ),
    _HistoryMetric(
      id: 'gyroX',
      title: 'Average Gyro X',
      unit: 'dps',
      icon: Icons.screen_rotation_alt,
    ),
    _HistoryMetric(
      id: 'gyroY',
      title: 'Average Gyro Y',
      unit: 'dps',
      icon: Icons.screen_rotation,
    ),
    _HistoryMetric(
      id: 'gyroZ',
      title: 'Average Gyro Z',
      unit: 'dps',
      icon: Icons.rotate_90_degrees_ccw,
    ),
    _HistoryMetric(
      id: 'motionMagnitude',
      title: 'Average Motion',
      unit: 'g',
      icon: Icons.directions_run,
    ),
    _HistoryMetric(
      id: 'gyroMagnitude',
      title: 'Average Gyro Magnitude',
      unit: 'dps',
      icon: Icons.threesixty,
    ),
    _HistoryMetric(
      id: 'alerts',
      title: 'High Alert Days',
      unit: '',
      icon: Icons.warning_amber,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DzozState>();
    final allSamples = state.sensorRiskHistory.isEmpty
        ? [
            SensorRiskSample(
              sensorData: state.currentSensor,
              riskResult: state.currentRisk,
            ),
          ]
        : state.sensorRiskHistory;
    final samples = _takeLast(allSamples, 120);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Header(),
        const SizedBox(height: 16),
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
    if (metricId == 'alerts') {
      final highAlertDays = samples
          .where(
            (item) =>
                item.riskResult.alertLevel == 'Warning' ||
                item.riskResult.alertLevel == 'Emergency',
          )
          .map((item) => DateUtils.dateOnly(item.sensorData.timestamp))
          .toSet()
          .length;
      return '$highAlertDays';
    }

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
      'Health History',
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
    );
  }
}

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
                metric.title,
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
      return const Center(
        child: Text(
          'No graph data',
          style: TextStyle(color: Color(0xFFA7B0C0), fontSize: 11),
        ),
      );
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: spots.length <= 1 ? 1 : (spots.length - 1).toDouble(),
        minY: metric.id == 'alerts' ? 0 : minY - yPadding,
        maxY: metric.id == 'alerts' ? 3 : maxY + yPadding,
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
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0D12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'No history data yet.',
        style: TextStyle(color: Color(0xFFA7B0C0)),
      ),
    );
  }
}

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
    final state = context.watch<DzozState>();
    final samples = state.sensorRiskHistory.isEmpty
        ? [
            SensorRiskSample(
              sensorData: state.currentSensor,
              riskResult: state.currentRisk,
            ),
          ]
        : state.sensorRiskHistory;
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
                    widget.metric.title,
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
    final averageLabel = metric.id == 'alerts' ? 'Avg Level' : 'Avg';
    final maxLabel = metric.id == 'alerts' ? 'Max Level' : 'Max';
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
        Expanded(child: _CountStat(label: 'Bars', value: count)),
      ],
    );
  }
}

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
    final maxY = bars.isEmpty
        ? 1.0
        : bars.map((item) => item.value).reduce((a, b) => a > b ? a : b);
    final paddedMaxY = metric.id == 'alerts'
        ? (maxY < 3 ? 3.0 : maxY + 1)
        : (maxY <= 0 ? 1.0 : maxY * 1.18);

    return Container(
      height: compact ? 320 : 380,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF232833)),
      ),
      child: bars.isEmpty
          ? const Center(
              child: Text(
                'No history data yet.',
                style: TextStyle(color: Color(0xFFA7B0C0)),
              ),
            )
          : BarChart(
              BarChartData(
                maxY: paddedMaxY,
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
                    axisNameWidget: _ChartAxisName(_metricAxisName(metric)),
                    axisNameSize: 20,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: compact ? 34 : 42,
                      getTitlesWidget: (value, meta) =>
                          _ChartAxisLabel(_formatShortMetric(value)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: _ChartAxisName(_rangeAxisName(range)),
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
            'Values',
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
                subtitle: metric.id == 'alerts'
                    ? 'Average alert level'
                    : 'Average ${metric.title}',
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

String _rangeAxisName(String range) {
  return switch (range) {
    'Day' => 'Hour',
    'Week' => 'Day',
    'Month' => 'Day',
    'Year' => 'Month',
    _ => 'Time',
  };
}

String _metricAxisName(_HistoryMetric metric) {
  if (metric.id == 'alerts') return 'Alert Level';
  return metric.unit.isEmpty ? metric.title : metric.unit;
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
    'heartRate' => sample.sensorData.heartRate.toDouble(),
    'spo2' => sample.sensorData.spo2.toDouble(),
    'ecgRate' => sample.sensorData.ecgRate.toDouble(),
    'ecgRrInterval' => sample.sensorData.ecgRrInterval,
    'ecgHrv' => sample.sensorData.ecgHrv,
    'gsr' => sample.sensorData.gsr,
    'temperature' => sample.sensorData.temperature,
    'stress' => sample.sensorData.stressLevel.toDouble(),
    'accelX' => sample.sensorData.accelX,
    'accelY' => sample.sensorData.accelY,
    'accelZ' => sample.sensorData.accelZ,
    'gyroX' => sample.sensorData.gyroX,
    'gyroY' => sample.sensorData.gyroY,
    'gyroZ' => sample.sensorData.gyroZ,
    'motionMagnitude' => sample.sensorData.motionMagnitude,
    'gyroMagnitude' => sample.sensorData.gyroMagnitude,
    'alerts' => sample.riskResult.levelValue.toDouble(),
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
