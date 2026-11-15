import 'package:doz/main.dart'; // EN: Provide the shared device history. TH: ใช้ประวัติอุปกรณ์ส่วนกลาง
import 'package:doz/models/risk_result.dart'; // EN: Tag a telemetry-only sample. TH: ระบุตัวอย่างที่ยังไม่มีผล AI
import 'package:doz/models/sensor_data.dart'; // EN: Supply signed gyro measurements. TH: ใส่ค่าการหมุนที่ติดลบ
import 'package:doz/models/sensor_risk_sample.dart'; // EN: Pair telemetry with its status. TH: ผูกค่าที่วัดกับสถานะ
import 'package:doz/screens/health_history_screen.dart'; // EN: Exercise the history UI. TH: ทดสอบหน้าประวัติ
import 'package:fl_chart/fl_chart.dart'; // EN: Inspect the chart's visible axis range. TH: ตรวจช่วงแกนที่กราฟใช้
import 'package:flutter/material.dart'; // EN: Host the detail route. TH: จัดหน้าแสดงรายละเอียด
import 'package:flutter_test/flutter_test.dart'; // EN: Assert chart behavior. TH: ตรวจพฤติกรรมกราฟ
import 'package:provider/provider.dart'; // EN: Expose DozState to widgets. TH: ส่ง DozState ให้ widget

void main() {
  testWidgets('history chart includes negative gyroscope values',
      (tester) async {
    // EN: Keep the third-row metric card within the test viewport.
    // TH: ให้การ์ดแถวที่สามอยู่ในขอบเขตหน้าจอทดสอบ
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    // EN: Construct a real-packet-shaped sample with negative angular rate.
    // TH: สร้างตัวอย่างรูปแบบ packet จริงที่มีอัตราการหมุนติดลบ
    final state = DozState();
    state.sensorRiskHistory.add(SensorRiskSample(
      sensorData: SensorData(
        heartRate: 0,
        spo2: 0,
        gsr: 0,
        temperature: 0,
        accelX: 0,
        accelY: 0,
        accelZ: 9.8,
        gyroX: -20,
        gyroY: 0,
        gyroZ: 0,
        rawRed: 12000,
        rawIr: 18000,
      ),
      riskResult: const RiskResult(
        riskClass: 'AI analysis unavailable',
        alertLevel: 'Unknown',
        detectedSigns: [],
        recommendation: '',
      ),
    ));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: Scaffold(body: HealthHistoryScreen())),
    ));
    await tester.ensureVisible(find.text('MPU6050 gyroscope X').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('MPU6050 gyroscope X').first);
    await tester.pumpAndSettle();

    // EN: The chart must reserve below-zero space for the signed sample.
    // TH: กราฟต้องมีพื้นที่ต่ำกว่าศูนย์สำหรับตัวอย่างที่ติดลบ
    final chart = tester.widget<BarChart>(find.byType(BarChart));
    expect(chart.data.minY, lessThan(-20));
    expect(chart.data.maxY, greaterThanOrEqualTo(0));
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
