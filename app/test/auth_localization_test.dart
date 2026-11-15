import 'package:doz/screens/login_screen.dart';
import 'package:doz/screens/password_recovery_screen.dart';
import 'package:doz/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  for (final locale in const [Locale('en'), Locale('th')]) {
    testWidgets('login screen is localized for ${locale.languageCode}',
        (tester) async {
      await tester.pumpWidget(_localizedApp(locale, const LoginScreen()));

      expect(
        find.text(
            locale.languageCode == 'en' ? 'Welcome back' : 'ยินดีต้อนรับกลับ'),
        findsOneWidget,
      );
      expect(
        find.text(locale.languageCode == 'en' ? 'Email' : 'อีเมล'),
        findsOneWidget,
      );
      expect(
        find.text(locale.languageCode == 'en' ? 'Sign in' : 'เข้าสู่ระบบ'),
        findsOneWidget,
      );
      expect(find.byType(AutofillGroup), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).at(0))
            .textInputAction,
        TextInputAction.next,
      );
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).at(1))
            .textInputAction,
        TextInputAction.done,
      );

      await tester.drag(find.byType(ListView), const Offset(0, -360));
      await tester.pumpAndSettle();
      await tester.tap(find.text(locale.languageCode == 'en'
          ? 'Read privacy notice (draft)'
          : 'อ่านประกาศความเป็นส่วนตัว (ฉบับร่าง)'));
      await tester.pumpAndSettle();
      expect(
        find.text(locale.languageCode == 'en'
            ? 'Privacy notice — draft'
            : 'ประกาศความเป็นส่วนตัว — ฉบับร่าง'),
        findsOneWidget,
      );
      expect(
          find.text(
              locale.languageCode == 'en' ? 'I understand' : 'เข้าใจแล้ว'),
          findsNothing);
      await tester
          .tap(find.text(locale.languageCode == 'en' ? 'Close' : 'ปิด'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 360));
      await tester.pumpAndSettle();
      await tester.tap(find.text(locale.languageCode == 'en'
          ? 'New to doz? Create an account'
          : 'ยังไม่มีบัญชี? สมัครใหม่'));
      await tester.pumpAndSettle();
      expect(
        find.text(locale.languageCode == 'en'
            ? 'Confirm password'
            : 'ยืนยันรหัสผ่าน'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).at(1))
            .textInputAction,
        TextInputAction.next,
      );
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).at(2))
            .textInputAction,
        TextInputAction.done,
      );
    });

    testWidgets(
        'password recovery screen is localized for ${locale.languageCode}',
        (tester) async {
      await tester
          .pumpWidget(_localizedApp(locale, const PasswordRecoveryScreen()));

      expect(
        find.text(locale.languageCode == 'en'
            ? 'Reset password'
            : 'ตั้งรหัสผ่านใหม่'),
        findsOneWidget,
      );
      expect(
        find.text(
            locale.languageCode == 'en' ? 'Save password' : 'บันทึกรหัสผ่าน'),
        findsOneWidget,
      );
    });

    testWidgets(
        'password recovery rejects short and mismatched passwords in ${locale.languageCode}',
        (tester) async {
      final isEnglish = locale.languageCode == 'en';
      final validationError = isEnglish
          ? 'Passwords must be at least 8 characters and match.'
          : 'รหัสผ่านต้องอย่างน้อย 8 ตัวและต้องตรงกัน';
      await tester
          .pumpWidget(_localizedApp(locale, const PasswordRecoveryScreen()));

      await tester.enterText(find.byType(TextField).at(0), 'short');
      await tester.enterText(find.byType(TextField).at(1), 'short');
      await tester
          .tap(find.text(isEnglish ? 'Save password' : 'บันทึกรหัสผ่าน'));
      await tester.pumpAndSettle();
      expect(find.text(validationError), findsOneWidget);
      expect(
          find.text(isEnglish
              ? 'Could not update password. The link may have expired; request a new one.'
              : 'ตั้งรหัสผ่านไม่สำเร็จ ลิงก์อาจหมดอายุ โปรดลองใหม่'),
          findsNothing);

      await tester.enterText(find.byType(TextField).at(0), 'securepass123');
      await tester.enterText(find.byType(TextField).at(1), 'different123');
      await tester
          .tap(find.text(isEnglish ? 'Save password' : 'บันทึกรหัสผ่าน'));
      await tester.pumpAndSettle();
      expect(find.text(validationError), findsOneWidget);
      expect(
          find.text(isEnglish
              ? 'Could not update password. The link may have expired; request a new one.'
              : 'ตั้งรหัสผ่านไม่สำเร็จ ลิงก์อาจหมดอายุ โปรดลองใหม่'),
          findsNothing);
    });
  }

  testWidgets('login screen remains usable on a narrow phone viewport',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester
        .pumpWidget(_localizedApp(const Locale('en'), const LoginScreen()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Read privacy notice (draft)'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('New to doz? Create an account'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('New to doz? Create an account'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('login failures are displayed as errors, not success messages',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    final state = DozState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: LoginScreen()),
        ),
      ),
    );
    await tester.enterText(
        find.byType(TextFormField).at(0), 'user@example.org');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    final error = tester.widget<Text>(
      find.text(
        'Could not continue. Check your email, password, email verification, and Auth configuration.',
      ),
    );
    expect(error.style?.color, const Color(0xFFFF8585));
    expect(
      find.ancestor(
        of: find.text(
          'Could not continue. Check your email, password, email verification, and Auth configuration.',
        ),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('email-confirmation sign-up returns to login and clears password',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? submittedEmail;
    String? submittedPassword;

    await tester.pumpWidget(
      _localizedApp(
        const Locale('en'),
        LoginScreen(
          onCreateAccount: (email, password) async {
            submittedEmail = email;
            submittedPassword = password;
            return null;
          },
        ),
      ),
    );
    await tester.tap(find.text('New to doz? Create an account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'new@example.org');
    await tester.enterText(find.byType(TextFormField).at(1), 'securepass123');
    await tester.enterText(find.byType(TextFormField).at(2), 'securepass123');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(submittedEmail, 'new@example.org');
    expect(submittedPassword, 'securepass123');
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(
      find.text('Account created. Verify your email, then return to sign in.'),
      findsOneWidget,
    );
    expect(
      (tester
              .widget<TextFormField>(find.byType(TextFormField).at(0))
              .controller!)
          .text,
      'new@example.org',
    );
    expect(
      (tester
              .widget<TextFormField>(find.byType(TextFormField).at(1))
              .controller!)
          .text,
      isEmpty,
    );
  });

  testWidgets('sign-up blocks mismatched password confirmation',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var accountCreationCalled = false;

    await tester.pumpWidget(
      _localizedApp(
        const Locale('en'),
        LoginScreen(
          onCreateAccount: (email, password) async {
            accountCreationCalled = true;
            return null;
          },
        ),
      ),
    );
    await tester.tap(find.text('New to doz? Create an account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'new@example.org');
    await tester.enterText(find.byType(TextFormField).at(1), 'securepass123');
    await tester.enterText(
        find.byType(TextFormField).at(2), 'differentpass123');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(accountCreationCalled, isFalse);
    expect(find.text('Passwords do not match.'), findsOneWidget);
  });
}

Widget _localizedApp(Locale locale, Widget home) => ChangeNotifierProvider(
      create: (_) => DozState()
        ..language = locale.languageCode == 'th' ? 'Thai' : 'English',
      child: Consumer<DozState>(
        builder: (context, state, _) => MaterialApp(
          locale: Locale(state.language == 'Thai' ? 'th' : 'en'),
          supportedLocales: const [Locale('en'), Locale('th')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: home,
        ),
      ),
    );
