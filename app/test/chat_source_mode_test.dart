import 'package:doz/screens/chat_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote consent copy is explicit about live versus demo data', () {
    final english = remoteChatConsentDescription(
      destination: 'api.example.net/chat',
      isThai: false,
    );
    final thai = remoteChatConsentDescription(
      destination: 'api.example.net/chat',
      isThai: true,
    );

    expect(english, contains('api.example.net/chat'));
    expect(english, contains('fresh readings from a physical device'));
    expect(english, contains('does not send demo or cached readings'));
    expect(english,
        contains('does not send your name, age, gender, or alert history'));
    expect(thai, contains('ไม่ส่งค่าสาธิตหรือค่าที่เก็บค้างไว้'));
    expect(thai, contains('ไม่ส่งชื่อ อายุ เพศ หรือประวัติการแจ้งเตือน'));
  });

  test('reports local-only when no remote endpoint is configured', () {
    expect(
      resolveChatSourceMode(
        endpointConfigured: false,
        signedIn: false,
        consentValid: false,
        llmEnabled: true,
        mockMode: false,
      ),
      ChatSourceMode.localOnly,
    );
  });

  test('does not report remote AI active before sign-in or consent', () {
    expect(
      resolveChatSourceMode(
        endpointConfigured: true,
        signedIn: false,
        consentValid: false,
        llmEnabled: true,
        mockMode: false,
      ),
      ChatSourceMode.signInRequired,
    );
    expect(
      resolveChatSourceMode(
        endpointConfigured: true,
        signedIn: true,
        consentValid: false,
        llmEnabled: true,
        mockMode: false,
      ),
      ChatSourceMode.consentRequired,
    );
  });

  test('reports remote AI active only when enabled and consented', () {
    expect(
      resolveChatSourceMode(
        endpointConfigured: true,
        signedIn: true,
        consentValid: true,
        llmEnabled: true,
        mockMode: false,
      ),
      ChatSourceMode.remoteAi,
    );
  });

  test('reports local mode when remote generation is disabled or mocked', () {
    expect(
      resolveChatSourceMode(
        endpointConfigured: true,
        signedIn: true,
        consentValid: true,
        llmEnabled: false,
        mockMode: false,
      ),
      ChatSourceMode.localSelected,
    );
    expect(
      resolveChatSourceMode(
        endpointConfigured: true,
        signedIn: true,
        consentValid: true,
        llmEnabled: true,
        mockMode: true,
      ),
      ChatSourceMode.localSelected,
    );
  });

  test('asks for consent only when remote generation is actually selected', () {
    expect(
      shouldPromptForRemoteChatConsent(
        mode: ChatSourceMode.consentRequired,
        consentValid: false,
      ),
      isTrue,
    );
    expect(
      shouldPromptForRemoteChatConsent(
        mode: ChatSourceMode.localSelected,
        consentValid: false,
      ),
      isFalse,
    );
    expect(
      shouldPromptForRemoteChatConsent(
        mode: ChatSourceMode.remoteAi,
        consentValid: true,
      ),
      isFalse,
    );
  });
}
