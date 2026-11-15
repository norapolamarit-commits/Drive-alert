import 'package:doz/main.dart';
import 'package:doz/models/sensor_data.dart';
import 'package:doz/screens/device_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  for (final locale in const [Locale('en'), Locale('th')]) {
    testWidgets('device screen is localized for ${locale.languageCode}',
        (tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      final state = DozState();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            locale: locale,
            supportedLocales: const [Locale('en'), Locale('th')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const Scaffold(body: DeviceScreen()),
          ),
        ),
      );

      if (locale.languageCode == 'en') {
        expect(find.text('My device'), findsOneWidget);
        expect(find.text('Live sensor check'), findsOneWidget);
        expect(find.text('Connect a device to verify incoming data.'),
            findsOneWidget);
        expect(find.textContaining('Status: Mock BLE stream'), findsOneWidget);
        expect(
            find.textContaining('one-second mean raw Red/IR'), findsOneWidget);
        expect(find.textContaining('does not send AI results'), findsOneWidget);
      } else {
        expect(find.text('อุปกรณ์ของฉัน'), findsOneWidget);
        expect(find.text('ตรวจข้อมูลเซนเซอร์สด'), findsOneWidget);
        expect(find.text('เชื่อมต่ออุปกรณ์เพื่อทดสอบการรับข้อมูล'),
            findsOneWidget);
        expect(
            find.textContaining('สถานะ: ใช้ข้อมูลสาธิตจากแอป'), findsOneWidget);
        expect(find.textContaining('ค่าเฉลี่ยดิบ Red/IR'), findsOneWidget);
        expect(find.textContaining('ยังไม่ส่งผล AI'), findsOneWidget);
      }

      state.bleStatus =
          'BLE scan failed: Bluetooth is off. Turn it on in device Settings, then scan again.';
      state.notifyListeners();
      await tester.pump();
      final permissionHint = find.textContaining(locale.languageCode == 'en'
          ? 'Bluetooth is off'
          : 'Bluetooth ปิดอยู่');
      expect(
        permissionHint,
        findsOneWidget,
      );
      state.bleStatus = 'BLE scan failed: Bluetooth permission is blocked.';
      state.notifyListeners();
      await tester.pump();
      await tester.ensureVisible(find.text(locale.languageCode == 'en'
          ? 'Open app settings'
          : 'เปิดการตั้งค่าแอป'));
      expect(
          find.text(locale.languageCode == 'en'
              ? 'Open app settings'
              : 'เปิดการตั้งค่าแอป'),
          findsOneWidget);

      state.bleStatus =
          'BLE scan failed: Android 11 and earlier require system Location services to be on for BLE scanning. doz does not read location during scanning.';
      state.notifyListeners();
      await tester.pump();
      expect(
        find.text(locale.languageCode == 'en'
            ? 'Open Location settings'
            : 'เปิดการตั้งค่าตำแหน่ง'),
        findsOneWidget,
      );
      expect(
        find.textContaining(locale.languageCode == 'en'
            ? 'doz does not read location during scanning'
            : 'แอปไม่อ่านพิกัดระหว่างค้นหา'),
        findsOneWidget,
      );

      state.bleStatus =
          'Doz device not found. Check power and BLE advertising; demo data is separate.';
      state.notifyListeners();
      await tester.pump();
      expect(
        find.textContaining(locale.languageCode == 'en'
            ? 'Doz device not found'
            : 'ไม่พบอุปกรณ์ Doz'),
        findsOneWidget,
      );
      expect(
        find.textContaining(locale.languageCode == 'en'
            ? 'demo data is separate'
            : 'ข้อมูลสาธิตแยกจากอุปกรณ์จริง'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('live device screen stays usable on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = DozState()
      ..bleConnected = true
      ..bleDeviceName = 'Doz prototype'
      ..lastSensorUpdateAt = DateTime.now()
      ..currentSensor = SensorData(
        heartRate: 0,
        spo2: 0,
        gsr: 0,
        temperature: 0,
        accelX: 0.1,
        accelY: -0.2,
        accelZ: 9.8,
        gyroX: 0.1,
        gyroY: 0.2,
        gyroZ: -0.1,
        rawRed: 123456,
        rawIr: 234567,
      );
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<DozState>.value(
        value: state,
        child: const MaterialApp(
          locale: Locale('th'),
          supportedLocales: [Locale('en'), Locale('th')],
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: DeviceScreen()),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('กำลังรับข้อมูลดิบจากอุปกรณ์'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('123456'), findsOneWidget);
    expect(find.text('234567'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('ยังไม่ยืนยันตัวตนผู้ส่ง BLE'),
      findsOneWidget,
    );
  });

  testWidgets('live telemetry is shown only when connected sensor data exists',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    final state = DozState()
      ..bleConnected = true
      ..bleDeviceName = 'Doz prototype'
      ..lastSensorUpdateAt = DateTime.now()
      ..currentSensor = SensorData(
        heartRate: 0,
        spo2: 0,
        gsr: 0,
        temperature: 0,
        accelX: 1.25,
        accelY: -0.5,
        accelZ: 9.81,
        gyroX: 1.75,
        gyroY: 0,
        gyroZ: 0,
        rawRed: 123456,
        rawIr: 234567,
      );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: DeviceScreen()),
        ),
      ),
    );

    expect(find.text('Red (ADC)'), findsOneWidget);
    expect(find.text('123456'), findsOneWidget);
    expect(find.text('IR (ADC)'), findsOneWidget);
    expect(find.text('234567'), findsOneWidget);
    expect(find.text('Gyro X'), findsOneWidget);
    expect(find.text('1.75 °/s'), findsOneWidget);
    expect(find.text('Receiving live raw telemetry'), findsOneWidget);
    expect(
      find.textContaining(
          'BLE sender identity is not cryptographically verified'),
      findsOneWidget,
    );
    expect(
        find.textContaining('does not send an AI prediction'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('connected device is marked stale when packets stop arriving',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    final state = DozState()
      ..bleConnected = true
      ..bleDeviceName = 'Doz prototype'
      ..lastSensorUpdateAt = DateTime.now()
      ..currentSensor = SensorData(
        heartRate: 0,
        spo2: 0,
        gsr: 0,
        temperature: 0,
        accelX: 0,
        accelY: 0,
        accelZ: 0,
        gyroX: 0,
        gyroY: 0,
        gyroZ: 0,
        rawRed: 123,
        rawIr: 456,
      );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: DeviceScreen()),
        ),
      ),
    );

    expect(find.textContaining('Receiving live raw telemetry'), findsOneWidget);
    // Simulate an old packet and ask the shared state to publish the freshness
    // transition so every screen (not only the device page) updates together.
    state.lastSensorUpdateAt =
        DateTime.now().subtract(const Duration(seconds: 9));
    state.refreshSensorFreshness();
    await tester.pump();
    expect(find.textContaining('No recent packet'), findsOneWidget);
    expect(find.textContaining('Receiving live raw telemetry'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('sensor freshness dot exposes a localized screen-reader label',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    final semantics = tester.ensureSemantics();
    final state = DozState()
      ..bleConnected = true
      ..lastSensorUpdateAt = DateTime.now()
      ..currentSensor = SensorData(
        heartRate: 0,
        spo2: 0,
        gsr: 0,
        temperature: 0,
        accelX: 0,
        accelY: 0,
        accelZ: 0,
        gyroX: 0,
        gyroY: 0,
        gyroZ: 0,
        rawRed: 10,
        rawIr: 20,
      );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: DeviceScreen()),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Fresh sensor data',
      ),
      findsOneWidget,
    );
    state.lastSensorUpdateAt =
        DateTime.now().subtract(const Duration(seconds: 10));
    state.refreshSensorFreshness();
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'No fresh sensor data',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    semantics.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
