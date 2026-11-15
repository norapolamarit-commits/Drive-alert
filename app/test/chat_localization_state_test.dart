import 'package:doz/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_memory_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final language in ['English', 'Thai']) {
    test('chat starter and length warning use $language', () async {
      SharedPreferences.setMockInitialValues(
        {'doz.local-demo.language': language},
      );
      final state = DozState(secureStore: InMemorySecureKeyValueStore());
      await state.initialize();

      final greeting = state.chatMessages.first.text;
      if (language == 'Thai') {
        expect(greeting, startsWith('สวัสดี'));
      } else {
        expect(greeting, startsWith('Hi,'));
      }

      await state.askChatbot('x' * 2001);
      final warning = state.chatMessages.last.text;
      if (language == 'Thai') {
        expect(warning, contains('คำถามยาวเกินไป'));
      } else {
        expect(warning, contains('question is too long'));
      }

      state.dispose();
    });
  }
}
