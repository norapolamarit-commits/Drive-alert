import 'package:doz/main.dart';
import 'package:doz/screens/login_screen.dart';
import 'package:doz/screens/setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_memory_secure_storage.dart';

Widget _localizedApp(DozState state, Widget screen) {
  return ChangeNotifierProvider<DozState>.value(
    value: state,
    child: Consumer<DozState>(
      builder: (context, currentState, _) => MaterialApp(
        locale: Locale(currentState.language == 'Thai' ? 'th' : 'en'),
        supportedLocales: const [Locale('en'), Locale('th')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: screen),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final entry in [
    (
      name: 'login',
      screen: const LoginScreen(),
      en: 'Welcome back',
      th: 'ยินดีต้อนรับกลับ'
    ),
    (
      name: 'setup',
      screen: const SetupScreen(),
      en: 'Name (optional)',
      th: 'ชื่อเล่น (ไม่บังคับ)'
    ),
  ]) {
    testWidgets('${entry.name} can switch language before app setup',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = DozState(secureStore: InMemorySecureKeyValueStore());
      addTearDown(state.dispose);

      await tester.pumpWidget(_localizedApp(state, entry.screen));
      expect(find.text(entry.en), findsOneWidget);

      await tester.tap(find.text('ไทย'));
      await tester.pumpAndSettle();

      expect(state.language, 'Thai');
      expect(find.text(entry.th), findsOneWidget);
    });
  }
}
