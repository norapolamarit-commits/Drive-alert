import 'package:doz/widgets/status_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unknown result is presented as analysis status, not advice',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StatusCard(
          status: 'AI analysis unavailable',
          alertLevel: 'Unknown',
          recommendation: 'No risk assessment is available.',
        ),
      ),
    ));

    expect(find.text('Analysis status'), findsOneWidget);
    expect(find.text('Recommendation'), findsNothing);
    expect(find.text('Unknown'), findsOneWidget);
  });

  testWidgets('known risk result retains recommendation label', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StatusCard(
          status: 'Alert',
          alertLevel: 'Safe',
          recommendation: 'Continue monitoring.',
        ),
      ),
    ));

    expect(find.text('Recommendation'), findsOneWidget);
    expect(find.text('Analysis status'), findsNothing);
  });
}
