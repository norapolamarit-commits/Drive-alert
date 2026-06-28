import 'package:flutter_test/flutter_test.dart';

import 'package:doz/main.dart';

void main() {
  testWidgets('doz app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const DozApp());
    await tester.pump();

    expect(find.text('doz'), findsOneWidget);
  });
}
