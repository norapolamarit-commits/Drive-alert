import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doz/main.dart';
import 'package:doz/ui_text.dart';
import 'support/in_memory_secure_storage.dart';

void main() {
  testWidgets('doz app starts', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      DozApp(secureStore: InMemorySecureKeyValueStore()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Name (optional)'), findsOneWidget);
  });

  testWidgets('account configuration errors are shown instead of bypassed',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(DozApp(
      startupError: 'auth_configuration',
      secureStore: InMemorySecureKeyValueStore(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Account setup failed'), findsOneWidget);
    expect(find.textContaining('Login will not be bypassed'), findsOneWidget);
  });

  testWidgets('account configuration errors are localized to Thai',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
      {'doz.local-demo.language': 'Thai'},
    );
    await tester.pumpWidget(DozApp(
      startupError: 'auth_configuration',
      secureStore: InMemorySecureKeyValueStore(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('ตั้งค่าระบบบัญชีไม่สำเร็จ'), findsOneWidget);
    expect(find.textContaining('DOZ_SUPABASE_URL'), findsOneWidget);
  });

  testWidgets('Thai locale selects Thai navigation copy',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('th'),
      supportedLocales: const [Locale('en'), Locale('th')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) => Scaffold(
          body: Text(uiText(
            context,
            english: 'Current Health Status',
            thai: 'สถานะสุขภาพ',
          )),
        ),
      ),
    ));

    expect(find.text('สถานะสุขภาพ'), findsOneWidget);
  });

  testWidgets('chat draft survives switching to another tab',
      (WidgetTester tester) async {
    final state = DozState(secureStore: InMemorySecureKeyValueStore());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: DozShell()),
      ),
    );

    await tester.tap(find.text('Ask doz'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Draft for later');

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask doz'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Draft for later'), findsOneWidget);
    state.dispose();
  });

  testWidgets(
      'connection badge does not say LIVE until fresh sensor data arrives',
      (WidgetTester tester) async {
    final state = DozState(secureStore: InMemorySecureKeyValueStore());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: DozShell()),
      ),
    );
    expect(find.text('DEMO'), findsOneWidget);

    state
      ..bleConnected = true
      ..lastSensorUpdateAt = null
      ..notifyListeners();
    await tester.pump();
    expect(find.text('WAITING'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
    expect(
      find.bySemanticsLabel(
          'Device connected; waiting for the first sensor reading'),
      findsOneWidget,
    );

    state
      ..lastSensorUpdateAt = DateTime.now()
      ..notifyListeners();
    await tester.pump();
    expect(find.text('LIVE'), findsOneWidget);

    state
      ..lastSensorUpdateAt =
          DateTime.now().subtract(const Duration(seconds: 31))
      ..notifyListeners();
    await tester.pump();
    expect(find.text('STALE'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
    expect(
      find.bySemanticsLabel('Device connected but sensor data is stale'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
