import 'package:doz/main.dart';
import 'package:doz/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('chat source status is available to screen readers',
      (tester) async {
    final state = DozState();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: ChatScreen()),
        ),
      ),
    );

    expect(find.text('Local help only • remote AI is not configured'),
        findsOneWidget);
    expect(find.bySemanticsLabel('Local assistance mode'), findsOneWidget);
  });

  testWidgets('remote chat setup status is announced to screen readers',
      (tester) async {
    final state = DozState()..phratumaEndpoint = 'https://api.example.net/chat';
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: ChatScreen()),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel('Server check starts after remote consent'),
      findsOneWidget,
    );
    final status = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.text('Server check starts after remote consent'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(status.properties.liveRegion, isTrue);
  });

  testWidgets(
      'chat layout remains usable on a short screen with keyboard inset',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final state = DozState();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(
            resizeToAvoidBottomInset: true,
            body: ChatScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
