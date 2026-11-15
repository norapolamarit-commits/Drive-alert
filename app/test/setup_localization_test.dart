import 'package:doz/main.dart';
import 'package:doz/screens/setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_memory_secure_storage.dart';

void main() {
  for (final locale in const [Locale('en'), Locale('th')]) {
    testWidgets('profile setup and privacy consent use ${locale.languageCode}',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = DozState(secureStore: InMemorySecureKeyValueStore())
        ..language = locale.languageCode == 'th' ? 'Thai' : 'English';
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
            home: const Scaffold(body: SetupScreen()),
          ),
        ),
      );

      final isEnglish = locale.languageCode == 'en';
      expect(
        find.text(isEnglish ? 'Name (optional)' : 'ชื่อเล่น (ไม่บังคับ)'),
        findsOneWidget,
      );
      expect(find.text(isEnglish ? 'Birth date' : 'วันเกิด'), findsNothing);
      expect(
          find.text(isEnglish ? 'Weight (kg)' : 'น้ำหนัก (กก.)'), findsNothing);
      expect(
        find.textContaining(isEnglish
            ? 'This acknowledgement only confirms that you understand this draft.'
            : 'การยืนยันนี้เป็นเพียงการรับทราบและเข้าใจประกาศฉบับร่าง'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byType(Checkbox),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(
        find.text(isEnglish
            ? 'Privacy notice — draft'
            : 'ประกาศความเป็นส่วนตัว — ฉบับร่าง'),
        findsOneWidget,
      );
      expect(
        find.text(isEnglish ? 'I understand' : 'เข้าใจแล้ว'),
        findsOneWidget,
      );

      await tester.tap(find.text(isEnglish ? 'Close' : 'ปิด'));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

      // Declining the notice must not allow the next tap to bypass consent.
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(
        find.text(isEnglish
            ? 'Privacy notice — draft'
            : 'ประกาศความเป็นส่วนตัว — ฉบับร่าง'),
        findsOneWidget,
      );
      await tester.tap(find.text(isEnglish ? 'I understand' : 'เข้าใจแล้ว'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(isEnglish ? 'Continue' : 'ดำเนินการต่อ'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
          find.text(isEnglish ? 'Continue' : 'ดำเนินการต่อ'), findsOneWidget);

      await tester.tap(find.text(isEnglish ? 'Continue' : 'ดำเนินการต่อ'));
      await tester.pumpAndSettle();
      expect(state.setupDone, isTrue);
      expect(state.userName, isEnglish ? 'Doz user' : 'ผู้ใช้ doz');
      expect(state.age, 20);
      expect(state.weight, 60);

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });
  }
}
