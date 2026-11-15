import 'package:doz/main.dart';
import 'package:doz/models/risk_result.dart';
import 'package:doz/models/sensor_data.dart';
import 'package:doz/models/sensor_risk_sample.dart';
import 'package:doz/screens/graph_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('raw BLE readings show raw telemetry charts, not zero HR/SpO2',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = DozState();
    final reading = SensorData(
      heartRate: 0,
      spo2: 0,
      gsr: 0,
      temperature: 0,
      accelX: 0.1,
      accelY: 0.2,
      accelZ: 9.8,
      gyroX: 1,
      gyroY: 2,
      gyroZ: 3,
      rawRed: 123456,
      rawIr: 234567,
      // EN: Keep a nonzero minute to catch chart labels rounded to HH:00.
      // TH: กำหนดนาทีที่ไม่ใช่ศูนย์เพื่อตรวจป้ายกราฟที่เคยปัดเป็น HH:00
      timestamp: DateTime(2026, 11, 15, 7, 24),
    );
    const unknown = RiskResult(
      riskClass: 'AI analysis unavailable',
      alertLevel: 'Unknown',
      detectedSigns: ['Raw telemetry only'],
      recommendation: 'Analysis is not available.',
    );
    state.currentSensor = reading;
    state.currentRisk = unknown;
    state.bleConnected = true;
    state.lastReadingWasFromDevice = true;
    state.lastSensorUpdateAt = DateTime.now();
    state.sensorHistory.add(reading);
    state.sensorRiskHistory
        .add(SensorRiskSample(sensorData: reading, riskResult: unknown));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: GraphScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MAX30102 Red mean'), findsOneWidget);
    expect(find.text('MAX30102 IR mean'), findsOneWidget);
    expect(find.text('07:24'), findsWidgets);
    expect(
        find.textContaining('Live one-second BLE raw means'), findsOneWidget);
    expect(find.text('Heart Rate'), findsNothing);
    expect(find.text('SpO2'), findsNothing);
  });

  testWidgets('raw telemetry chart and table labels follow Thai locale',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = DozState();
    final reading = SensorData(
      heartRate: 0,
      spo2: 0,
      gsr: 0,
      temperature: 0,
      accelX: 0.1,
      accelY: 0.2,
      accelZ: 9.8,
      gyroX: 1,
      gyroY: 2,
      gyroZ: 3,
      rawRed: 123456,
      rawIr: 234567,
    );
    const unknown = RiskResult(
      riskClass: 'AI analysis unavailable',
      alertLevel: 'Unknown',
      detectedSigns: ['Raw telemetry only'],
      recommendation: 'Analysis is not available.',
    );
    state.currentSensor = reading;
    state.currentRisk = unknown;
    state.sensorHistory.add(reading);
    state.sensorRiskHistory
        .add(SensorRiskSample(sensorData: reading, riskResult: unknown));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          locale: Locale('th'),
          supportedLocales: [Locale('en'), Locale('th')],
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: GraphScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ค่าเฉลี่ย Red MAX30102'), findsOneWidget);
    expect(find.text('ค่าเฉลี่ย IR MAX30102'), findsOneWidget);
    expect(find.text('จำนวนครั้ง ADC'), findsNWidgets(2));
    expect(find.text('เวลา (ชั่วโมง)'), findsWidgets);

    await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('แสดงตารางข้อมูลเซนเซอร์'));
    await tester.pumpAndSettle();
    expect(find.text('เวลาที่รับข้อมูล'), findsOneWidget);
    expect(find.text('ค่าเฉลี่ย Red (ADC)'), findsOneWidget);
    expect(find.text('ความเร่ง X (m/s²)'), findsOneWidget);
    expect(find.text('อัตราหมุน Z (°/วินาที)'), findsOneWidget);
    expect(find.text('การวิเคราะห์'), findsOneWidget);
  });

  testWidgets('disconnected view labels retained BLE charts as history',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = DozState();
    final reading = SensorData(
      heartRate: 0,
      spo2: 0,
      gsr: 0,
      temperature: 0,
      accelX: 0.1,
      accelY: 0.2,
      accelZ: 9.8,
      gyroX: 1,
      gyroY: 2,
      gyroZ: 3,
      rawRed: 123456,
      rawIr: 234567,
    );
    state.sensorHistory.add(reading);
    state.sensorRiskHistory.add(
      SensorRiskSample(
        sensorData: reading,
        riskResult: const RiskResult(
          riskClass: 'AI analysis unavailable',
          alertLevel: 'Unknown',
          detectedSigns: ['Raw telemetry only'],
          recommendation: 'Analysis is not available.',
        ),
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: GraphScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MAX30102 Red mean'), findsOneWidget);
    expect(find.textContaining('stored readings from a previous BLE session'),
        findsOneWidget);
    expect(find.text('Heart Rate'), findsNothing);
    expect(find.text('SpO2'), findsNothing);
  });

  testWidgets('demo values are not graphed as device health measurements',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = DozState();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: GraphScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No live device data yet'), findsOneWidget);
    expect(find.textContaining('Demo values are not sensor readings'),
        findsOneWidget);
    expect(find.text('Heart Rate'), findsNothing);
    expect(find.text('SpO2'), findsNothing);
    expect(find.text('GSR'), findsNothing);
    expect(find.text('Temperature'), findsNothing);
    expect(find.text('Stress Level'), findsNothing);
    expect(find.text('Alert Level Trend'), findsNothing);
    expect(
        find.textContaining('No real BLE sensor history yet'), findsOneWidget);
  });
}
