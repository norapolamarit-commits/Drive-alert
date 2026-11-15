import 'package:doz/main.dart'; // EN: Provide the shared alert state. TH: ใช้สถานะ alert ส่วนกลาง
import 'package:doz/models/alert_record.dart'; // EN: Build a recorded alert. TH: สร้าง alert ที่บันทึกแล้ว
import 'package:doz/models/risk_result.dart'; // EN: Describe the alert severity. TH: กำหนดระดับความรุนแรง
import 'package:doz/models/sensor_data.dart'; // EN: Build a sensor snapshot. TH: สร้าง snapshot เซนเซอร์
import 'package:doz/screens/alert_history_screen.dart'; // EN: Exercise the alert-history UI. TH: ทดสอบหน้าประวัติ alert
import 'package:flutter/material.dart'; // EN: Host the widget tree. TH: จัด widget tree
import 'package:flutter_test/flutter_test.dart'; // EN: Assert visible actions. TH: ตรวจปุ่มที่มองเห็น
import 'package:provider/provider.dart'; // EN: Expose DozState to the screen. TH: ส่ง DozState ให้หน้าจอ

void main() {
  // EN: Acknowledged alerts must not offer a duplicate response action.
  // TH: alert ที่ตอบแล้วต้องไม่มีปุ่มให้ตอบซ้ำ
  testWidgets('response buttons disappear after latest alert is acknowledged',
      (tester) async {
    final state = DozState();
    final sensor = SensorData(
      heartRate: 70,
      spo2: 97,
      gsr: 0,
      temperature: 36,
      accelX: 0,
      accelY: 0,
      accelZ: 0,
      gyroX: 0,
      gyroY: 0,
      gyroZ: 0,
    );
    const risk = RiskResult(
      riskClass: 'Drowsiness',
      alertLevel: 'Warning',
      detectedSigns: [],
      recommendation: 'Stop safely.',
    );
    state.alerts.add(AlertRecord(
      id: 'alert-1',
      timestamp: DateTime.utc(2026),
      sensorData: sensor,
      riskResult: risk,
    ));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: Scaffold(body: AlertHistoryScreen())),
    ));
    expect(find.text('I am safe'), findsOneWidget);

    // EN: Replace the latest alert with its persisted acknowledged form.
    // TH: เปลี่ยน alert ล่าสุดเป็นรูปแบบที่มีคำตอบบันทึกแล้ว
    state.alerts[0] = state.alerts[0].copyWith(userResponse: 'I am safe');
    state.notifyListeners();
    await tester.pump();
    expect(find.text('I am safe'), findsNothing);
    // EN: Confirm the stored response while the history card may be offscreen.
    // TH: ตรวจคำตอบที่เก็บไว้โดยไม่พึ่งการ์ดประวัติที่อาจยังอยู่นอกจอ
    expect(state.alerts.first.userResponse, 'I am safe');

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
