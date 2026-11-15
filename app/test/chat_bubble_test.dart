import 'package:doz/models/chat_message.dart';
import 'package:doz/widgets/chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('user chat bubble uses the doz palette with readable white text', () {
    expect(chatUserBubbleColors, hasLength(2));
    for (final background in chatUserBubbleColors) {
      expect(
          _contrastRatio(Colors.white, background), greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('chat bubble renders the message and timestamp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatBubble(
            message: ChatMessage(
              text: 'Bluetooth setup help',
              isUser: true,
              timestamp: DateTime(2026, 11, 9, 9, 5),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Bluetooth setup help'), findsOneWidget);
    expect(find.text('09:05'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
