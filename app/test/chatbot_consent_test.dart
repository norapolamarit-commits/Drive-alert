import 'package:doz/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_memory_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('remote chatbot consent is revoked when its endpoint changes', () async {
    final state = DozState(secureStore: InMemorySecureKeyValueStore());

    await state.updateSettings(endpoint: 'https://api.example.net/chat');
    expect(state.chatbotRemoteConfigured, isTrue);
    expect(state.chatbotRemoteConsentValid, isFalse);

    // Simulate a previously granted consent for the current remote endpoint.
    state.chatbotRemoteConsent = true;
    state.chatbotRemoteConsentEndpoint = state.phratumaEndpoint;

    await state.updateSettings(endpoint: 'https://other.example.org/chat');
    expect(state.chatbotRemoteConsent, isFalse);
    expect(state.chatbotRemoteConsentValid, isFalse);
  });

  test('remote consent cannot be granted for an insecure endpoint', () async {
    final state = DozState(secureStore: InMemorySecureKeyValueStore());

    await state.updateSettings(endpoint: 'http://api.example.net/chat');
    await state.setChatbotRemoteConsent(true);

    expect(state.chatbotRemoteConfigured, isFalse);
    expect(state.chatbotRemoteConsentValid, isFalse);
  });
}
