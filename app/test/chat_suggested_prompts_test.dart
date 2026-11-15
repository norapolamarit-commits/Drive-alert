import 'package:doz/main.dart';
import 'package:doz/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final locale in const [Locale('en'), Locale('th')]) {
    testWidgets(
        'chat prompts are localized and submit in ${locale.languageCode}',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = DozState();
      final isEnglish = locale.languageCode == 'en';

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
            home: const Scaffold(body: ChatScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final label = isEnglish ? 'Connect device' : 'เชื่อมต่ออุปกรณ์';
      expect(find.widgetWithText(ActionChip, label), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, label));
      await tester.pumpAndSettle();

      expect(
        state.chatMessages.any((message) =>
            message.isUser &&
            message.text ==
                (isEnglish
                    ? 'How do I connect Bluetooth?'
                    : 'เชื่อมต่ออุปกรณ์ยังไง?')),
        isTrue,
      );
      expect(find.widgetWithText(ActionChip, label), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });
  }
}
