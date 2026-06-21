import 'package:flutter_test/flutter_test.dart';

import 'package:vitaguard/main.dart';

void main() {
  testWidgets('Vita gaurd app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const VitaGuardApp());
    await tester.pump();

    expect(find.text('Vita gaurd'), findsOneWidget);
  });
}
