import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/sensor_data.dart';
import '../models/sensor_risk_sample.dart';
import '../ui_text.dart';
import 'health_history_screen.dart';

// EN: Graph actual BLE optical means and motion, excluding demo vital signs.
// TH: วาดกราฟค่าแสงและการเคลื่อนไหวจาก BLE จริง โดยไม่รวมค่าชีพจรเดโม
class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  // EN: Keep the optional raw-data table collapsed initially.
  // TH: เริ่มต้นโดยซ่อนตารางข้อมูลดิบ
  bool _showTable = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DozState>();
    // EN: Require both optical channels before showing a device reading.
    // TH: ต้องมีข้อมูลแสงทั้งสองช่องก่อนแสดงค่าจากอุปกรณ์
    final currentHasRaw =
        state.currentSensor.rawRed != null && state.currentSensor.rawIr != null;
    final storedRawHistory = state.sensorHistory
        .where((sample) => sample.rawRed != null && sample.rawIr != null)
        .toList();
    // EN: Chart at most the latest 80 device-origin snapshots.
    // TH: วาดกราฟจาก snapshot ล่าสุดไม่เกิน 80 รายการ
    final history = _takeLast(
      storedRawHistory.isEmpty && currentHasRaw
          ? [state.currentSensor]
          : storedRawHistory,
      80,
    );
    final hasRawHistory = history.isNotEmpty;
    final lastUpdate = state.lastSensorUpdateAt;
    // EN: Keep full duration precision so even sub-second future times are rejected.
    // TH: ใช้ความละเอียดของ Duration เพื่อปฏิเสธเวลาอนาคตแม้ต่างไม่ถึงวินาที
    final age =
        lastUpdate == null ? null : DateTime.now().difference(lastUpdate);
    final ageSeconds = age?.inSeconds;
    // EN: A future or old receive timestamp must not be called live.
    // TH: เวลารับที่อยู่อนาคตหรือเก่าเกินต้องไม่ถูกเรียกว่าข้อมูลสด
    final isLive = state.bleConnected &&
        currentHasRaw &&
        state.lastReadingWasFromDevice &&
        age != null &&
        !age.isNegative &&
        age <= const Duration(seconds: 8);
    final sampleHistory = _takeLast(
      state.sensorRiskHistory
          .where((sample) => (sample.sensorData.rawRed != null &&
              sample.sensorData.rawIr != null))
          .toList(),
      80,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          uiText(context, english: 'Sensor Data', thai: 'ข้อมูลเซนเซอร์'),
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 16),
        if (hasRawHistory)
          _DataModeNotice(
            text: uiText(
              context,
              english: isLive
                  ? 'Live one-second BLE raw means. Current firmware does not send HR, SpO₂, or AI results.'
                  : state.bleConnected && ageSeconds != null
                      ? 'No fresh BLE packet. Showing earlier sensor readings; last update was $ageSeconds seconds ago.'
                      : 'Showing stored readings from a previous BLE session, not live data. Demo values are not included.',
              thai: isLive
                  ? 'กำลังแสดงค่าเฉลี่ยดิบ BLE แบบเรียลไทม์ เฟิร์มแวร์ปัจจุบันยังไม่ส่งค่า HR, SpO₂ หรือผล AI'
                  : state.bleConnected && ageSeconds != null
                      ? 'ยังไม่มีข้อมูล BLE ล่าสุด กำลังแสดงค่าก่อนหน้า • อัปเดตล่าสุด $ageSeconds วินาทีก่อน'
                      : 'กำลังแสดงประวัติจากการเชื่อมต่อ BLE ก่อนหน้า ไม่ใช่ข้อมูลสด และไม่รวมค่าเดโม',
            ),
          ),
        if (!hasRawHistory)
          _DataModeNotice(
            text: uiText(
              context,
              english:
                  'No live device data yet. Demo values are not sensor readings. Current firmware sends MAX30102 Red/IR ADC means and MPU6050 motion values only; it does not provide HR, SpO₂, GSR, skin temperature, or AI results.',
              thai:
                  'ยังไม่มีข้อมูลสดจากอุปกรณ์ ค่าเดโมไม่ใช่ค่าจากเซนเซอร์ เฟิร์มแวร์ปัจจุบันส่งเฉพาะค่าเฉลี่ย ADC ของ Red/IR จาก MAX30102 และค่าการเคลื่อนไหวจาก MPU6050 ยังไม่มี HR, SpO₂, GSR, อุณหภูมิผิวหนัง หรือผล AI',
            ),
          ),
        if (hasRawHistory) ...[
          _ChartCard(
              title: uiText(context,
                  english: 'MAX30102 Red mean', thai: 'ค่าเฉลี่ย Red MAX30102'),
              yAxisTitle:
                  uiText(context, english: 'ADC count', thai: 'จำนวนครั้ง ADC'),
              xAxisTitle: uiText(context,
                  english: 'Time (hour)', thai: 'เวลา (ชั่วโมง)'),
              spots: _spots(history, (s) => (s.rawRed ?? 0).toDouble()),
              timestamps: _sensorTimes(history)),
          _ChartCard(
              title: uiText(context,
                  english: 'MAX30102 IR mean', thai: 'ค่าเฉลี่ย IR MAX30102'),
              yAxisTitle:
                  uiText(context, english: 'ADC count', thai: 'จำนวนครั้ง ADC'),
              xAxisTitle: uiText(context,
                  english: 'Time (hour)', thai: 'เวลา (ชั่วโมง)'),
              spots: _spots(history, (s) => (s.rawIr ?? 0).toDouble()),
              timestamps: _sensorTimes(history)),
          _ChartCard(
              title: uiText(context,
                  english: 'MPU6050 acceleration magnitude',
                  thai: 'ขนาดความเร่ง MPU6050'),
              yAxisTitle: uiText(context,
                  english: 'm/s² (including gravity)',
                  thai: 'm/s² (รวมแรงโน้มถ่วง)'),
              xAxisTitle: uiText(context,
                  english: 'Time (hour)', thai: 'เวลา (ชั่วโมง)'),
              spots: _spots(history, (s) => s.motionMagnitude),
              timestamps: _sensorTimes(history)),
          _ChartCard(
              title: uiText(context,
                  english: 'MPU6050 gyroscope magnitude',
                  thai: 'ขนาดอัตราการหมุน MPU6050'),
              yAxisTitle: uiText(context, english: '°/s', thai: '°/วินาที'),
              xAxisTitle: uiText(context,
                  english: 'Time (hour)', thai: 'เวลา (ชั่วโมง)'),
              spots: _spots(history, (s) => s.gyroMagnitude),
              timestamps: _sensorTimes(history)),
        ],
        if (hasRawHistory && sampleHistory.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => setState(() => _showTable = !_showTable),
            icon: const Icon(Icons.table_chart_outlined),
            label: Text(uiText(
              context,
              english: _showTable
                  ? 'Hide sensor data table'
                  : 'Show sensor data table',
              thai: _showTable ? 'ซ่อนตารางข้อมูล' : 'แสดงตารางข้อมูลเซนเซอร์',
            )),
          ),
        if (hasRawHistory && _showTable) ...[
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

  List<DateTime> _sensorTimes(List<SensorData> items) {
    return items.map((item) => item.timestamp).toList();
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
    required this.xAxisTitle,
    required this.spots,
    required this.timestamps,
  });

  final String title;
  final String yAxisTitle;
  final String xAxisTitle;
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
                titlesData: _axisTitles(
                    spots, timestamps, compact, yAxisTitle, xAxisTitle),
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
  String xAxisTitle,
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
      axisNameWidget: _AxisName(xAxisTitle),
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

// EN: Preserve the measured minute on the chart; do not round every point to the hour.
// TH: คงนาทีจริงบนแกนกราฟ ไม่ปัดทุกจุดเป็นต้นชั่วโมง
String _formatTime(DateTime value) =>
    DateFormat('HH:mm').format(value.toLocal());

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
        columns: [
          DataColumn(
              label: Text(uiText(context,
                  english: 'Receive time', thai: 'เวลาที่รับข้อมูล'))),
          DataColumn(
              label: Text(uiText(context,
                  english: 'Red mean (ADC)', thai: 'ค่าเฉลี่ย Red (ADC)'))),
          DataColumn(
              label: Text(uiText(context,
                  english: 'IR mean (ADC)', thai: 'ค่าเฉลี่ย IR (ADC)'))),
          DataColumn(
              label: Text(uiText(context,
                  english: 'Accel X (m/s²)', thai: 'ความเร่ง X (m/s²)'))),
          DataColumn(
              label: Text(uiText(context,
                  english: 'Accel Y (m/s²)', thai: 'ความเร่ง Y (m/s²)'))),
          DataColumn(
              label: Text(uiText(context,
                  english: 'Accel Z (m/s²)', thai: 'ความเร่ง Z (m/s²)'))),
          DataColumn(
              label: Text(uiText(context,
                  english: 'Gyro X (°/s)', thai: 'อัตราหมุน X (°/วินาที)'))),
          DataColumn(
              label: Text(uiText(context,
                  english: 'Gyro Y (°/s)', thai: 'อัตราหมุน Y (°/วินาที)'))),
          DataColumn(
              label: Text(uiText(context,
                  english: 'Gyro Z (°/s)', thai: 'อัตราหมุน Z (°/วินาที)'))),
          DataColumn(
              label: Text(
                  uiText(context, english: 'Analysis', thai: 'การวิเคราะห์'))),
        ],
        rows: rows
            .map(
              (sample) => DataRow(
                cells: [
                  DataCell(Text(DateFormat('HH:mm:ss')
                      .format(sample.sensorData.timestamp))),
                  DataCell(Text('${sample.sensorData.rawRed ?? '—'}')),
                  DataCell(Text('${sample.sensorData.rawIr ?? '—'}')),
                  DataCell(Text(sample.sensorData.accelX.toStringAsFixed(2))),
                  DataCell(Text(sample.sensorData.accelY.toStringAsFixed(2))),
                  DataCell(Text(sample.sensorData.accelZ.toStringAsFixed(2))),
                  DataCell(Text(sample.sensorData.gyroX.toStringAsFixed(2))),
                  DataCell(Text(sample.sensorData.gyroY.toStringAsFixed(2))),
                  DataCell(Text(sample.sensorData.gyroZ.toStringAsFixed(2))),
                  DataCell(Text(sample.riskResult.alertLevel)),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DataModeNotice extends StatelessWidget {
  const _DataModeNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF302818),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: const TextStyle(height: 1.35)),
      );
}
