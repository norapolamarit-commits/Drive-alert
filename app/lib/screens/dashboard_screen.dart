import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import 'alert_history_screen.dart';
import 'device_screen.dart';
import '../widgets/risk_explanation_card.dart';
import '../widgets/sensor_card.dart';
import '../widgets/status_card.dart';
import '../ui_text.dart';

// EN: Present device telemetry, alert history, and explicit demo provenance.
// TH: แสดงข้อมูลอุปกรณ์ ประวัติแจ้งเตือน และที่มาของข้อมูลสาธิตให้ชัดเจน
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // EN: Use shorter spacing for the phone layout. TH: ลดระยะห่างบนหน้าจอมือถือ
    final compact = MediaQuery.sizeOf(context).width < 600;
    // EN: Rebuild when the shared sensor or connection state changes.
    // TH: สร้างหน้าจอใหม่เมื่อข้อมูลเซนเซอร์หรือสถานะเชื่อมต่อเปลี่ยน
    final state = context.watch<DozState>();
    final sensor = state.currentSensor;
    // EN: A BLE link alone does not prove that a device packet has arrived.
    // TH: การเชื่อม BLE อย่างเดียวไม่ยืนยันว่าได้รับ packet จากอุปกรณ์แล้ว
    final hasDeviceReading =
        state.bleConnected && state.lastReadingWasFromDevice;
    // EN: Show Red/IR counts only when both channels came from the device.
    // TH: แสดงค่า Red/IR เฉพาะเมื่อได้รับทั้งสองช่องจากอุปกรณ์จริง
    final rawTelemetry =
        hasDeviceReading && sensor.rawRed != null && sensor.rawIr != null;
    final risk = state.currentRisk;
    // EN: Count alerts awaiting a user response; Unknown is not a new alert.
    // TH: นับเฉพาะ alert ที่ยังไม่ตอบรับ โดย Unknown ไม่ใช่ alert ใหม่
    final activeAlerts =
        state.alerts.where((item) => item.userResponse.isEmpty).length;

    return ListView(
      padding: EdgeInsets.all(compact ? 8 : 16),
      children: [
        // EN: Orient the user before presenting measurements and alerts.
        // TH: บอกผู้ใช้ว่าหน้านี้แสดงอะไร ก่อนเข้าสู่ค่าการวัดและการแจ้งเตือน
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            uiText(context,
                english: 'Your status now', thai: 'สถานะของคุณตอนนี้'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        _WatchConnectionCard(state: state),
        // EN: Make simulated values unmistakable whenever BLE is disconnected.
        // TH: ระบุว่าค่าเป็นข้อมูลจำลองเสมอเมื่อไม่ได้เชื่อม BLE
        if (!state.bleConnected) ...[
          const SizedBox(height: 10),
          const _DemoDataNotice(),
        ],
        SizedBox(height: compact ? 8 : 12),
        StatusCard(
          status: localizedRiskClass(context, risk.riskClass),
          alertLevel: risk.alertLevel,
          // EN: Use remote advice only when present; otherwise display the current risk message.
          // TH: ใช้คำแนะนำระยะไกลเมื่อมี มิฉะนั้นแสดงข้อความจากผลความเสี่ยงปัจจุบัน
          recommendation: state.aiAdvice.isNotEmpty
              ? state.aiAdvice
              : localizedRiskRecommendation(context, risk.recommendation),
          cause: state.aiAdvice.isNotEmpty ? state.aiAdviceCause : '',
          disclaimer: state.aiAdvice.isNotEmpty ? state.aiAdviceDisclaimer : '',
        ),
        if (rawTelemetry) ...[
          const SizedBox(height: 8),
          Text(
            uiText(context,
                english:
                    '8 measured channels • AI drowsiness alerts are not available with the current firmware.',
                thai:
                    'ข้อมูลวัดจริง 8 ช่อง • เฟิร์มแวร์ปัจจุบันยังไม่แจ้งเตือนความง่วงด้วย AI'),
            style: const TextStyle(color: Color(0xFFFFC66D)),
          ),
        ],
        SizedBox(height: compact ? 8 : 12),
        // EN: Separate action-oriented status from supporting detail.
        // TH: แยกสถานะที่ต้องใช้ตัดสินใจออกจากข้อมูลประกอบ
        _SectionHeading(
          title: uiText(context, english: 'At a glance', thai: 'ภาพรวม'),
          subtitle: uiText(context,
              english: 'Alerts and device readiness',
              thai: 'การแจ้งเตือนและความพร้อมของอุปกรณ์'),
        ),
        // EN: Summarize alerts and state separately from physical measurements.
        // TH: แยกสรุป alert และสถานะออกจากค่าที่เซนเซอร์วัด
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: compact ? 1.42 : 1.15,
          crossAxisSpacing: compact ? 8 : 10,
          mainAxisSpacing: compact ? 8 : 10,
          children: [
            SensorCard(
                title: uiText(context,
                    english: 'Active Alerts', thai: 'การแจ้งเตือน'),
                value: '$activeAlerts',
                unit: '',
                icon: Icons.warning_amber,
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                          body: SafeArea(child: AlertHistoryScreen()),
                        )))),
            SensorCard(
                title: uiText(context,
                    english: 'Latest Alert Level',
                    thai: 'ระดับแจ้งเตือนล่าสุด'),
                value: localizedAlertLevel(context, risk.alertLevel),
                unit: '',
                icon: Icons.shield_outlined),
            SensorCard(
                title: uiText(context,
                    english: 'Detected Risk', thai: 'ความเสี่ยงที่ตรวจพบ'),
                value: localizedRiskClass(context, risk.riskClass),
                unit: '',
                icon: Icons.radar_outlined),
            SensorCard(
                title: uiText(context,
                    english: 'Device Battery', thai: 'แบตเตอรี่อุปกรณ์'),
                value: state.deviceBattery?.toString() ?? '—',
                unit: state.deviceBattery == null ? '' : '%',
                icon: Icons.battery_5_bar),
          ],
        ),
        SizedBox(height: compact ? 8 : 12),
        _SectionHeading(
          title: uiText(context,
              english: 'Sensor readings', thai: 'ข้อมูลเซนเซอร์'),
          subtitle: rawTelemetry
              ? uiText(context,
                  english:
                      '8 channels from device · 1-second means, not full waveforms',
                  thai:
                      'ข้อมูล 8 ช่องจากอุปกรณ์ · ค่าเฉลี่ย 1 วินาที ไม่ใช่คลื่นสัญญาณเต็ม')
              : uiText(context,
                  english:
                      'Waiting for device data · no sensor readings available',
                  thai: 'รอข้อมูลจากอุปกรณ์ · ยังไม่มีค่าเซนเซอร์จริง'),
        ),
        // EN: Display only the eight measured channels in the current firmware.
        // TH: แสดงเฉพาะแปดช่องที่เฟิร์มแวร์ปัจจุบันวัดและส่งมา
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: compact ? 1.42 : 1.15,
          crossAxisSpacing: compact ? 8 : 10,
          mainAxisSpacing: compact ? 8 : 10,
          children: [
            SensorCard(
                title: 'MAX30102 Red mean',
                value: rawTelemetry ? '${sensor.rawRed}' : '—',
                unit: rawTelemetry ? 'ADC' : '',
                icon: Icons.favorite_outline),
            SensorCard(
                title: 'MAX30102 IR mean',
                value: rawTelemetry ? '${sensor.rawIr}' : '—',
                unit: rawTelemetry ? 'ADC' : '',
                icon: Icons.air_outlined),
            SensorCard(
                title: 'MPU6050 Accel X',
                value: rawTelemetry ? sensor.accelX.toStringAsFixed(2) : '—',
                unit: rawTelemetry ? 'm/s²' : '',
                icon: Icons.bolt_outlined),
            SensorCard(
                title: 'MPU6050 Accel Y',
                value: rawTelemetry ? sensor.accelY.toStringAsFixed(2) : '—',
                unit: rawTelemetry ? 'm/s²' : '',
                icon: Icons.sensors_outlined),
            SensorCard(
                title: 'MPU6050 Accel Z',
                value: rawTelemetry ? sensor.accelZ.toStringAsFixed(2) : '—',
                unit: rawTelemetry ? 'm/s²' : '',
                icon: Icons.thermostat_outlined),
            SensorCard(
                title: 'MPU6050 Gyro X',
                value: rawTelemetry ? sensor.gyroX.toStringAsFixed(2) : '—',
                unit: rawTelemetry ? '°/s' : '',
                icon: Icons.screen_rotation_alt),
            SensorCard(
                title: 'MPU6050 Gyro Y',
                value: rawTelemetry ? sensor.gyroY.toStringAsFixed(2) : '—',
                unit: rawTelemetry ? '°/s' : '',
                icon: Icons.screen_rotation),
            SensorCard(
                title: 'MPU6050 Gyro Z',
                value: rawTelemetry ? sensor.gyroZ.toStringAsFixed(2) : '—',
                unit: rawTelemetry ? '°/s' : '',
                icon: Icons.rotate_90_degrees_ccw),
          ],
        ),
        SizedBox(height: compact ? 8 : 12),
        // EN: Explain Unknown as unavailable analysis, not a Safe prediction.
        // TH: อธิบาย Unknown ว่ายังไม่มีผลวิเคราะห์ ไม่ใช่ผล Safe
        RiskExplanationCard(risk: risk),
        SizedBox(height: compact ? 8 : 12),
        if (state.profileDetailsProvided) _PersonalInfo(state: state),
      ],
    );
  }
}

// EN: Give each dashboard group a readable title and provenance cue.
// TH: ตั้งหัวข้อแต่ละกลุ่มให้อ่านง่ายพร้อมระบุที่มาของค่า
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: const Color(0xFFA7B0C0))),
        ],
      ),
    );
  }
}

// EN: Label the connection and cloud setting without claiming successful inference.
// TH: ระบุการเชื่อมต่อและการตั้งค่าคลาวด์ โดยไม่อ้างว่าทำนายสำเร็จ
class _WatchConnectionCard extends StatelessWidget {
  const _WatchConnectionCard({required this.state});

  final DozState state;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final connectedText = state.bleConnected
        ? uiText(context,
            english: 'Device connected', thai: 'เชื่อมต่ออุปกรณ์แล้ว')
        : uiText(context, english: 'Demo mode', thai: 'โหมดสาธิต');
    final signalText = state.bleConnected
        ? localizedBleStatus(context, state.sensorFreshnessStatus)
        : uiText(context,
            english: 'Preview data • not from a wearable',
            thai: 'ข้อมูลตัวอย่าง • ไม่ได้มาจากอุปกรณ์จริง');

    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF232833)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF151922), Color(0xFF0B0D12)],
        ),
      ),
      child: Row(
        children: [
          const _WatchIllustration(),
          SizedBox(width: compact ? 14 : 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  uiText(context, english: 'Wearable', thai: 'อุปกรณ์สวมใส่'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$connectedText • $signalText',
                  style: const TextStyle(color: Color(0xFFA7B0C0)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _WatchChip(
                      icon: Icons.bluetooth,
                      label: state.bleConnected
                          ? 'BLE'
                          : uiText(context, english: 'Demo', thai: 'สาธิต'),
                    ),
                    _WatchChip(
                      icon: Icons.battery_5_bar,
                      label: state.deviceBattery == null
                          ? uiText(context,
                              english: 'Battery —', thai: 'แบตเตอรี่ —')
                          : '${state.deviceBattery}%',
                    ),
                    _WatchChip(
                      icon: Icons.sync,
                      label: state.cloudEnabled
                          ? uiText(context, english: 'Cloud', thai: 'คลาวด์')
                          : uiText(context,
                              english: 'Local', thai: 'ในเครื่อง'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// EN: Draw a decorative wearable icon; it is not a hardware rendering.
// TH: วาดรูปอุปกรณ์ประกอบหน้าจอ ไม่ใช่ภาพชิ้นส่วนจริง
class _WatchIllustration extends StatelessWidget {
  const _WatchIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      height: 108,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 0,
            child: Container(
              width: 30,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF232833),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              width: 30,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF232833),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Container(
            width: 62,
            height: 74,
            decoration: BoxDecoration(
              color: const Color(0xFF050608),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(
              Icons.watch_outlined,
              color: Color(0xFF55D6A7),
              size: 30,
            ),
          ),
        ],
      ),
    );
  }
}

// EN: Render one short connection, battery, or storage label.
// TH: แสดงป้ายสั้นสำหรับการเชื่อมต่อ แบตเตอรี่ หรือการจัดเก็บ
class _WatchChip extends StatelessWidget {
  const _WatchChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF050608),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF343B4A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF55D6A7)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// EN: Warn that disconnected-mode values are samples and link to device setup.
// TH: เตือนว่าค่าในโหมดไม่ได้เชื่อมต่อเป็นตัวอย่างและเชื่อมไปหน้าตั้งค่าอุปกรณ์
class _DemoDataNotice extends StatelessWidget {
  const _DemoDataNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF251C10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF654A20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.science_outlined,
              color: Color(0xFFFFC56A), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  uiText(context,
                      english:
                          'Demo data only — values and status are not from your device.',
                      thai:
                          'ข้อมูลสาธิตเท่านั้น — ค่าและสถานะไม่ใช่ข้อมูลจากอุปกรณ์จริง'),
                  style: const TextStyle(
                    color: Color(0xFFFFD99A),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        body: SafeArea(child: DeviceScreen()),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.bluetooth_searching, size: 16),
                  label: Text(uiText(context,
                      english: 'Connect wearable', thai: 'เชื่อมต่ออุปกรณ์')),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFFC56A),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// EN: Display profile fields only after the user has supplied them.
// TH: แสดงข้อมูลส่วนตัวเฉพาะหลังผู้ใช้กรอกข้อมูลแล้ว
class _PersonalInfo extends StatelessWidget {
  const _PersonalInfo({required this.state});

  final DozState state;

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
            uiText(context,
                english: 'Personal information', thai: 'ข้อมูลส่วนบุคคล'),
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
              '${uiText(context, english: 'Weight', thai: 'น้ำหนัก')}: ${state.weight.toStringAsFixed(0)} kg'),
          Text(
              '${uiText(context, english: 'Height', thai: 'ส่วนสูง')}: ${state.height.toStringAsFixed(0)} cm'),
          Text(
              '${uiText(context, english: 'Age', thai: 'อายุ')}: ${state.age}'),
          Text(
              '${uiText(context, english: 'Gender', thai: 'เพศ')}: ${state.gender}'),
          Text(
              '${uiText(context, english: 'Health conditions', thai: 'โรคประจำตัว')}: ${state.conditions}'),
        ],
      ),
    );
  }
}
