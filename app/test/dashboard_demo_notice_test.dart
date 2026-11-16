import 'package:doz/main.dart';
import 'package:doz/models/risk_result.dart';
import 'package:doz/models/sensor_data.dart';
import 'package:doz/models/sensor_risk_sample.dart';
import 'package:doz/screens/dashboard_screen.dart';
import 'package:doz/widgets/risk_explanation_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  test('CSV exports optical means and device time without inventing demo data',
      () {
    // EN: Use a physical-packet-shaped snapshot with known ADC counts.
    // TH: ใช้ snapshot รูปแบบ packet จริงที่กำหนดค่า ADC ชัดเจน
    final state = DozState();
    final sensor = SensorData(
      heartRate: 0,
      spo2: 0,
      gsr: 0,
      temperature: 0,
      accelX: 1,
      accelY: 2,
      accelZ: 3,
      gyroX: 4,
      gyroY: 5,
      gyroZ: 6,
      rawRed: 12345,
      rawIr: 23456,
      deviceTimestampMs: 789,
    );
    const unknown = RiskResult(
      riskClass: 'AI analysis unavailable',
      alertLevel: 'Unknown',
      detectedSigns: [],
      recommendation: '',
    );
    state.sensorRiskHistory.add(
      SensorRiskSample(sensorData: sensor, riskResult: unknown),
    );
    final rows = state.exportSensorHistoryCsv().trim().split('\n');
    final header = rows.first.split(',');
    final values = rows.last.split(',');
    expect(header.length, values.length);
    expect(values[header.indexOf('red_adc_mean')], '12345');
    expect(values[header.indexOf('ir_adc_mean')], '23456');
    expect(values[header.indexOf('device_timestamp_ms')], '789');

    state.sensorRiskHistory.clear();
    state.sensorRiskHistory.add(
      SensorRiskSample(
        sensorData: SensorData(
          heartRate: 78,
          spo2: 97,
          gsr: 45,
          temperature: 36.7,
          accelX: 0,
          accelY: 0,
          accelZ: 0,
          gyroX: 0,
          gyroY: 0,
          gyroZ: 0,
        ),
        riskResult: unknown,
      ),
    );
    final demoValues =
        state.exportSensorHistoryCsv().trim().split('\n').last.split(',');
    expect(demoValues[header.indexOf('red_adc_mean')], isEmpty);
    expect(demoValues[header.indexOf('ir_adc_mean')], isEmpty);
    expect(demoValues[header.indexOf('device_timestamp_ms')], isEmpty);
    state.dispose();
  });

  testWidgets('dashboard clearly marks demo values as non-device data',
      (tester) async {
    final state = DozState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
      ),
    );

    expect(find.textContaining('Demo data only'), findsOneWidget);
    expect(find.textContaining('Preview data • not from a wearable'),
        findsOneWidget);
    expect(find.text('Battery —'), findsOneWidget);
    expect(find.text('Connect wearable'), findsOneWidget);
    expect(find.text('Demo preview'), findsWidgets);
    expect(find.text('Unknown'), findsWidgets);
    expect(find.text('Safe'), findsNothing);
    expect(find.text('No AI or risk assessment is available in demo mode.'),
        findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('MAX30102 Red mean'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('MAX30102 Red mean'), findsOneWidget);
    expect(find.text('MAX30102 IR mean'), findsOneWidget);
    expect(find.text('MPU6050 Gyro Z'), findsOneWidget);
    expect(find.text('Heart Rate'), findsNothing);
    expect(find.text('SpO₂'), findsNothing);
    expect(find.text('Stress Level'), findsNothing);
    expect(find.text('GSR'), findsNothing);
    expect(find.text('Temperature'), findsNothing);
  });

  test('mock sensor updates never create a health-risk assessment', () async {
    final state = DozState();
    await state.updateSensorData(
      SensorData(
        heartRate: 120,
        spo2: 94,
        gsr: 80,
        temperature: 36.8,
        accelX: 0.2,
        accelY: 0.3,
        accelZ: 1.0,
        gyroX: 1.0,
        gyroY: 1.0,
        gyroZ: 1.0,
      ),
    );

    expect(state.currentRisk.riskClass, 'Demo preview');
    expect(state.currentRisk.alertLevel, 'Unknown');
    expect(state.sensorRiskHistory.single.riskResult.alertLevel, 'Unknown');
    expect(state.alerts, isEmpty);
    state.dispose();
  });

  testWidgets(
      'connected dashboard waits for real telemetry instead of demo values',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    final state = DozState()
      ..bleConnected = true
      ..currentRisk = const RiskResult(
        riskClass: 'AI analysis unavailable',
        alertLevel: 'Unknown',
        detectedSigns: ['Waiting for first sensor packet.'],
        recommendation: 'No risk assessment is available.',
      );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
      ),
    );

    expect(find.textContaining('Device connected'), findsOneWidget);
    expect(find.text('MAX30102 Red mean'), findsOneWidget);
    expect(find.text('MAX30102 IR mean'), findsOneWidget);
    expect(find.text('MPU6050 Accel X'), findsOneWidget);
    expect(find.text('MPU6050 Gyro X'), findsOneWidget);
    expect(find.text('MPU6050 Gyro Y'), findsOneWidget);
    expect(find.text('MPU6050 Gyro Z'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(9));
    expect(find.textContaining('AI analysis unavailable'), findsNWidgets(2));
    expect(find.textContaining('Demo data only'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('demo notice and connect action are localized in Thai',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DozState(),
        child: const MaterialApp(
          locale: Locale('th'),
          supportedLocales: [Locale('en'), Locale('th')],
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: DashboardScreen()),
        ),
      ),
    );

    expect(find.textContaining('ข้อมูลสาธิตเท่านั้น'), findsOneWidget);
    expect(find.text('เชื่อมต่ออุปกรณ์'), findsOneWidget);
    expect(find.text('ตัวอย่างสาธิต'), findsWidgets);
    expect(find.text('โหมดสาธิตไม่มีการประเมินความเสี่ยงหรือผลจาก AI'),
        findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1400));
    await tester.pumpAndSettle();
  });

  testWidgets('demo provenance in the risk explanation is localized in Thai',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('th'),
      supportedLocales: [Locale('en'), Locale('th')],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: RiskExplanationCard(
          risk: RiskResult(
            riskClass: 'Demo preview',
            alertLevel: 'Unknown',
            detectedSigns: [
              'Demo sensor values are generated for interface preview only.'
            ],
            recommendation:
                'No AI or risk assessment is available in demo mode.',
          ),
        ),
      ),
    ));

    expect(
      find.text('ค่าจากเซนเซอร์เป็นข้อมูลจำลองสำหรับดูตัวอย่างหน้าจอเท่านั้น'),
      findsOneWidget,
    );
  });

  testWidgets('English dashboard translates the built-in safe recommendation',
      (tester) async {
    final state = DozState()
      ..currentRisk = const RiskResult(
        riskClass: 'ปกติ',
        alertLevel: 'Safe',
        detectedSigns: ['ปกติ'],
        recommendation: 'ค่าปัจจุบันอยู่ในช่วงปลอดภัย ติดตามต่อเนื่องตามปกติ',
      );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: [Locale('en'), Locale('th')],
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: DashboardScreen()),
        ),
      ),
    );

    expect(
      find.text(
        'Current readings are within the safe range. Continue monitoring as usual.',
      ),
      findsOneWidget,
    );
    expect(find.text('Normal'), findsWidgets);
    expect(find.text('ค่าปัจจุบันอยู่ในช่วงปลอดภัย ติดตามต่อเนื่องตามปกติ'),
        findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('raw telemetry analysis status is localized and non-reassuring',
      (tester) async {
    final state = DozState()
      ..bleConnected = true
      ..lastReadingWasFromDevice = true
      ..currentRisk = const RiskResult(
        riskClass: 'AI analysis unavailable',
        alertLevel: 'Unknown',
        detectedSigns: ['Connected to ESP32; raw sensor telemetry received.'],
        recommendation:
            'This firmware only streams sensor data; on-device AI inference is not integrated yet.',
      );

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
          home: Scaffold(body: DashboardScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ยังไม่มีผลวิเคราะห์ AI'), findsWidgets);
    expect(find.text('ยังไม่ทราบ'), findsWidgets);
    expect(find.text('สถานะการวิเคราะห์'), findsOneWidget);
    expect(find.text('คำแนะนำ'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('Thai raw-only explanation says no risk analysis is available',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('th'),
      supportedLocales: [Locale('en'), Locale('th')],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: RiskExplanationCard(
          risk: RiskResult(
            riskClass: 'AI analysis unavailable',
            alertLevel: 'Unknown',
            detectedSigns: [
              'Connected to ESP32; raw sensor telemetry received.'
            ],
            recommendation: 'No risk assessment is available.',
          ),
        ),
      ),
    ));

    expect(find.text('สถานะการวิเคราะห์'), findsOneWidget);
    expect(
      find.text('รับข้อมูลดิบจากเซนเซอร์แล้ว แต่ยังไม่มีผลประเมินความเสี่ยง'),
      findsOneWidget,
    );
    expect(find.text('สัญญาณที่ตรวจพบ'), findsNothing);
  });
}
