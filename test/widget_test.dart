import 'package:flutter_test/flutter_test.dart';

import 'package:dzoz/main.dart';

void main() {
  testWidgets('Dzoz app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const DzozApp());
    await tester.pump();

    expect(find.text('Dzoz'), findsOneWidget);
  });
}
