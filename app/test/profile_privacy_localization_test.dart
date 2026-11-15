import 'package:doz/main.dart';
import 'package:doz/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_memory_secure_storage.dart';

void main() {
  test('clearLocation removes only the active account coordinates', () async {
    SharedPreferences.setMockInitialValues({
      'doz.local-demo.latitude': 13.75,
      'doz.local-demo.longitude': 100.50,
      'doz.other-account.latitude': 1.25,
    });
    final state = DozState(secureStore: InMemorySecureKeyValueStore())
      ..latitude = 13.75
      ..longitude = 100.50;

    await state.clearLocation();

    final prefs = await SharedPreferences.getInstance();
    expect(state.latitude, isNull);
    expect(state.longitude, isNull);
    expect(state.locationStatus, 'Location cleared');
    expect(prefs.containsKey('doz.local-demo.latitude'), isFalse);
    expect(prefs.containsKey('doz.local-demo.longitude'), isFalse);
    expect(prefs.getDouble('doz.other-account.latitude'), 1.25);
    state.dispose();
  });

  for (final locale in const [Locale('en'), Locale('th')]) {
    testWidgets('profile privacy controls use ${locale.languageCode}',
        (tester) async {
      final state = DozState(secureStore: InMemorySecureKeyValueStore());
      await tester.pumpWidget(
        ChangeNotifierProvider<DozState>.value(
          value: state,
          child: MaterialApp(
            locale: locale,
            supportedLocales: const [Locale('en'), Locale('th')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const Scaffold(body: ProfileScreen()),
          ),
        ),
      );

      final isEnglish = locale.languageCode == 'en';
      expect(
        find.text(isEnglish ? 'Local demo profile' : 'โปรไฟล์ทดลองในเครื่อง'),
        findsOneWidget,
      );
      expect(
        find.text(isEnglish
            ? 'Demo account • not signed in'
            : 'บัญชีทดลอง • ยังไม่ได้เข้าสู่ระบบ'),
        findsOneWidget,
      );
      expect(find.textContaining('User ID:'), findsNothing);
      final privacyTitle =
          find.text(isEnglish ? 'Privacy Policy' : 'ความเป็นส่วนตัว');
      await tester.scrollUntilVisible(
        privacyTitle,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(privacyTitle, findsOneWidget);
      expect(
        find.text(isEnglish
            ? 'Cloud sync is disabled. Remote chatbot processing is optional and asks separately before sending a request.'
            : 'ปิดการซิงก์ข้อมูลขึ้นคลาวด์ไว้ การประมวลผล chatbot ระยะไกลเป็นตัวเลือก และจะแจ้งขอความยินยอมแยกก่อนส่งคำขอ'),
        findsOneWidget,
      );
      expect(
        find.text(isEnglish
            ? 'Delete local alerts & clear sensor buffer'
            : 'ลบประวัติแจ้งเตือนและล้างข้อมูลเซนเซอร์'),
        findsOneWidget,
      );
      final cloudSyncTitle = find.text(
          isEnglish ? 'Cloud health-data sync' : 'ซิงก์ข้อมูลสุขภาพขึ้นคลาวด์');
      await tester.scrollUntilVisible(
        cloudSyncTitle,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(cloudSyncTitle, findsOneWidget);
      expect(
        find.text(isEnglish
            ? 'Disabled pending privacy and security review.'
            : 'ปิดไว้ระหว่างทบทวนความเป็นส่วนตัวและความปลอดภัย'),
        findsOneWidget,
      );
      final openNotice = find.text(
          isEnglish ? 'Open Privacy Policy' : 'อ่านประกาศความเป็นส่วนตัว');
      await tester.scrollUntilVisible(
        openNotice,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(openNotice);
      await tester.pumpAndSettle();
      expect(
          find.text(isEnglish
              ? 'Privacy notice — draft'
              : 'ประกาศความเป็นส่วนตัว — ฉบับร่าง'),
          findsOneWidget);
      expect(
          find.text(isEnglish ? 'I understand' : 'เข้าใจแล้ว'), findsNothing);
      expect(find.text(isEnglish ? 'Accept' : 'ยอมรับ'), findsNothing);
      await tester.tap(find.text(isEnglish ? 'Close' : 'ปิด'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });
  }

  testWidgets('device detail BLE controls are localized in Thai',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = DozState(secureStore: InMemorySecureKeyValueStore());
    state
      ..latitude = 13.75
      ..longitude = 100.50
      ..locationStatus = 'Location ready: 13.75000, 100.50000';
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
          home: Scaffold(body: ProfileScreen()),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('ตั้งค่าอุปกรณ์'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.ancestor(
        of: find.text('ตั้งค่าอุปกรณ์'),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
          'ปิดการซิงก์คลาวด์ไว้ ระหว่างรอทบทวนความเป็นส่วนตัวและความปลอดภัย'),
      findsOneWidget,
    );
    expect(find.text('พร้อมใช้งาน • 13.75000, 100.50000'), findsOneWidget);
    expect(find.text('ยังไม่มีข้อมูลจากเซนเซอร์'), findsOneWidget);
    expect(find.text('ค้นหาอุปกรณ์'), findsOneWidget);
    expect(find.text('เชื่อมต่อ'), findsOneWidget);
    expect(find.text('ยกเลิกการเชื่อมต่อ'), findsOneWidget);
    expect(find.text('ใช้ข้อมูลสาธิต'), findsOneWidget);
    expect(find.text('ลืมอุปกรณ์นี้'), findsOneWidget);
    expect(find.text('เปิดการแจ้งเตือน'), findsOneWidget);
    final clearLocation = find.text('ลบตำแหน่งที่บันทึกไว้');
    await tester.scrollUntilVisible(
      clearLocation,
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(clearLocation);
    await tester.pumpAndSettle();
    expect(state.latitude, isNull);
    expect(state.longitude, isNull);
    expect(find.text('ลบตำแหน่งที่บันทึกไว้'), findsNothing);
    expect(find.text('ลบตำแหน่งที่บันทึกไว้แล้ว'), findsOneWidget);
  });

  testWidgets('profile fits a narrow phone viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = DozState(secureStore: InMemorySecureKeyValueStore());
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
          home: Scaffold(body: ProfileScreen()),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('ตั้งค่าอุปกรณ์'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    final deviceCard = find.ancestor(
      of: find.text('ตั้งค่าอุปกรณ์'),
      matching: find.byType(InkWell),
    );
    expect(deviceCard, findsOneWidget);
    await tester.ensureVisible(deviceCard);
    await tester.pumpAndSettle();
    await tester.tap(deviceCard);
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_DeviceDetailScreen',
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('ค้นหาอุปกรณ์'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('ค้นหาอุปกรณ์'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('ใช้ข้อมูลสาธิต'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('ใช้ข้อมูลสาธิต'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
