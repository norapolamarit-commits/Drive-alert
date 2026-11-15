import 'dart:convert';

import 'package:doz/models/risk_result.dart';
import 'package:doz/models/sensor_data.dart';
import 'package:doz/services/phratuma_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final sensorData = SensorData(
    heartRate: 80,
    spo2: 97,
    gsr: 12,
    temperature: 36.5,
    accelX: 0,
    accelY: 0,
    accelZ: 1,
    gyroX: 0,
    gyroY: 0,
    gyroZ: 0,
  );
  const riskResult = RiskResult(
    riskClass: 'Alert',
    alertLevel: 'Safe',
    detectedSigns: ['test'],
    recommendation: 'Continue monitoring.',
  );

  test('chat readiness check probes the matching API ready route', () async {
    Uri? checkedUri;
    final service = PhratumaService(
      client: MockClient((request) async {
        checkedUri = request.url;
        expect(request.followRedirects, isFalse);
        return http.Response('{"status":"ready"}', 200);
      }),
    );

    final ready = await service.checkReady(
      chatEndpoint: 'https://api.example.net/v1/chat',
    );

    expect(ready, isTrue);
    expect(checkedUri, Uri.parse('https://api.example.net/v1/ready'));
  });

  test('chat readiness rejects a live API with Auth unavailable', () async {
    final service = PhratumaService(
      client: MockClient((request) async {
        expect(request.url.path, '/ready');
        return http.Response(
            '{"detail":"Required service configuration is unavailable."}', 503);
      }),
    );
    expect(
        await service.checkReady(chatEndpoint: 'https://api.example.net/chat'),
        isFalse);
  });

  test('chat readiness rejects liveness-only response', () async {
    final service = PhratumaService(
      client:
          MockClient((request) async => http.Response('{"status":"ok"}', 200)),
    );
    expect(
        await service.checkReady(chatEndpoint: 'https://api.example.net/chat'),
        isFalse);
  });

  test('approved chat endpoint derives its same-server API base', () {
    expect(
      PhratumaService.chatApiBaseUrl('https://api.example.net/v1/chat'),
      'https://api.example.net/v1',
    );
    expect(
      PhratumaService.chatApiBaseUrl('https://api.example.net/chat'),
      'https://api.example.net',
    );
    expect(
      PhratumaService.chatApiBaseUrl(
          'https://api.example.net/chat?to=elsewhere'),
      isNull,
    );
  });

  test('chat health check marks missing or invalid servers unavailable',
      () async {
    final service = PhratumaService(
      client: MockClient((_) async => http.Response('Not Found', 404)),
    );

    expect(
      await service.checkReady(chatEndpoint: 'https://api.example.net/chat'),
      isFalse,
    );
    expect(
      await service.checkReady(chatEndpoint: 'http://api.example.net/chat'),
      isFalse,
    );
  });

  test('chat health check rejects unsafe endpoints before making a request',
      () async {
    var requestSent = false;
    final service = PhratumaService(
      client: MockClient((_) async {
        requestSent = true;
        return http.Response('{"status":"ready"}', 200);
      }),
    );

    for (final endpoint in [
      'https://user:secret@api.example.net/chat',
      'https://api.example.net/chat?redirect=https://attacker.example',
      'https://api.example.net/chat#fragment',
      'https://api.example.net/not-chat',
    ]) {
      expect(await service.checkReady(chatEndpoint: endpoint), isFalse);
    }
    expect(requestSent, isFalse);
  });

  test('remote chat rejects unsafe endpoint without forwarding bearer token',
      () async {
    var requestSent = false;
    final service = PhratumaService(
      client: MockClient((_) async {
        requestSent = true;
        return http.Response('{"mode":"llm","answer":"unsafe"}', 200);
      }),
    );

    final answer = await service.ask(
      endpoint: 'https://attacker.example/chat?redirect=other',
      model: 'test-model',
      userMessage: 'What is this?',
      sensorData: sensorData,
      riskResult: riskResult,
      isLiveDeviceData: false,
      enabled: true,
      useMockResponse: false,
      bearerToken: 'secret-test-token',
    );

    expect(requestSent, isFalse);
    expect(answer, contains('คำตอบช่วยเหลือในเครื่อง'));
  });

  test('remote chat sends bearer token and no account profile/history',
      () async {
    http.Request? captured;
    final service = PhratumaService(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          '{"mode":"llm","answer":"Safe test answer"}',
          200,
        );
      }),
    );

    final answer = await service.ask(
      endpoint: 'https://api.example.net/chat',
      model: 'test-model',
      userMessage: 'What does this status mean?',
      sensorData: sensorData,
      riskResult: riskResult,
      isLiveDeviceData: true,
      enabled: true,
      useMockResponse: false,
      bearerToken: 'test-access-token',
    );

    expect(answer, 'Safe test answer');
    expect(captured!.headers['Authorization'], 'Bearer test-access-token');
    expect(captured!.followRedirects, isFalse);
    final requestBody = jsonDecode(captured!.body) as Map<String, dynamic>;
    final prompt = requestBody['prompt'] as String;
    expect(prompt, contains('What does this status mean?'));
    expect(prompt, isNot(contains('User profile:')));
    expect(prompt, isNot(contains('Recent alert history:')));
    expect(prompt.toLowerCase(), isNot(contains('latitude')));
    expect(prompt.toLowerCase(), isNot(contains('longitude')));
    expect(prompt.toLowerCase(), isNot(contains('location')));
    expect(prompt, contains('Confirmed live device metrics'));
  });

  test('remote knowledge fallback is labeled as non-LLM output', () async {
    final service = PhratumaService(
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'mode': 'fallback',
              'answer': 'Knowledge-base answer',
            }),
            200,
          )),
    );

    final answer = await service.ask(
      endpoint: 'https://api.example.net/chat',
      model: 'test-model',
      userMessage: 'What is this?',
      sensorData: sensorData,
      riskResult: riskResult,
      isLiveDeviceData: false,
      enabled: true,
      useMockResponse: false,
      bearerToken: 'test-access-token',
      language: 'English',
    );

    expect(answer, contains('Knowledge fallback'));
    expect(answer, contains('not generated by the AI model'));
    expect(answer, contains('Knowledge-base answer'));
  });

  test(
      'remote response without a recognized source mode is never trusted as LLM output',
      () async {
    final service = PhratumaService(
      client: MockClient((_) async => http.Response(
            '{"answer":"Unverified response"}',
            200,
          )),
    );

    final answer = await service.ask(
      endpoint: 'https://api.example.net/chat',
      model: 'test-model',
      userMessage: 'What is this?',
      sensorData: sensorData,
      riskResult: riskResult,
      isLiveDeviceData: false,
      enabled: true,
      useMockResponse: false,
      bearerToken: 'test-access-token',
      language: 'English',
    );

    expect(answer, contains('Local help (not generated by remote AI)'));
    expect(answer, isNot(contains('Unverified response')));
  });

  test('remote chat fails back locally if no authenticated token exists',
      () async {
    var requestSent = false;
    final service = PhratumaService(
      client: MockClient((_) async {
        requestSent = true;
        return http.Response('{}', 200);
      }),
    );

    final answer = await service.ask(
      endpoint: 'https://api.example.net/chat',
      model: 'test-model',
      userMessage: 'What does this status mean?',
      sensorData: sensorData,
      riskResult: riskResult,
      isLiveDeviceData: false,
      enabled: true,
      useMockResponse: false,
    );

    expect(requestSent, isFalse);
    expect(answer, contains('คำตอบช่วยเหลือในเครื่อง'));
    expect(answer, contains('ยังไม่มีข้อมูลสดจากอุปกรณ์จริง'));
  });

  test('offline FAQ recognizes natural BLE and privacy questions', () {
    final service = PhratumaService();
    final connectionAnswer = service.fallbackAnswer(
      'How do I connect to my device?',
      sensorData,
      riskResult,
      isLiveDeviceData: false,
      language: 'English',
    );
    final privacyAnswer = service.fallbackAnswer(
      'What data is stored on-device?',
      sensorData,
      riskResult,
      isLiveDeviceData: false,
      language: 'English',
    );
    final thaiPrivacyAnswer = service.fallbackAnswer(
      'แอปเก็บข้อมูลอะไรบ้าง',
      sensorData,
      riskResult,
      isLiveDeviceData: false,
    );

    expect(connectionAnswer, contains('To connect:'));
    expect(connectionAnswer, contains('No live readings'));
    expect(privacyAnswer, contains('in-memory buffer'));
    expect(privacyAnswer, contains('Alert history and profile data'));
    expect(privacyAnswer, contains('cloud health-data sync is disabled'));
    expect(thaiPrivacyAnswer, contains('เก็บในเครื่อง'));
    expect(thaiPrivacyAnswer, contains('cloud health-data sync ปิดอยู่'));
  });

  test('remote failure falls back locally and identifies the source', () async {
    final service = PhratumaService(
      client: MockClient((_) async => http.Response('unavailable', 503)),
    );

    final answer = await service.ask(
      endpoint: 'https://api.example.net/chat',
      model: 'test-model',
      userMessage: 'How do I connect Bluetooth?',
      sensorData: sensorData,
      riskResult: riskResult,
      isLiveDeviceData: false,
      enabled: true,
      useMockResponse: false,
      bearerToken: 'test-access-token',
      language: 'English',
    );

    expect(answer, contains('Local help (not generated by remote AI)'));
    expect(answer, contains('No live readings from a physical device'));
    expect(answer, contains('To connect:'));
  });

  test(
      'offline fallback answers BLE setup questions without inventing readings',
      () async {
    final service = PhratumaService(
      client: MockClient((_) async => http.Response('{}', 500)),
    );

    final answer = await service.ask(
      endpoint: 'https://api.example.net/chat',
      model: 'test-model',
      userMessage: 'ต่อ Bluetooth ยังไง',
      sensorData: sensorData,
      riskResult: riskResult,
      isLiveDeviceData: false,
      enabled: false,
      useMockResponse: true,
    );

    expect(answer, contains('ยังไม่มีข้อมูลสดจากอุปกรณ์จริง'));
    expect(answer, contains('Doz-ESP32S3'));
    expect(answer, contains('อนุญาต Bluetooth'));
    expect(answer, isNot(contains('HR 80')));
  });

  test('offline fallback accurately explains mobile distribution status', () {
    final answer = PhratumaService().fallbackAnswer(
      'Where can I download and install the app?',
      sensorData,
      riskResult,
      isLiveDeviceData: false,
      language: 'English',
    );

    expect(answer, contains('Android debug APK'));
    expect(answer, contains('not a Play Store release'));
    expect(answer, contains('not yet been verified'));
  });

  test('offline fallback gives safe password recovery guidance', () {
    final answer = PhratumaService().fallbackAnswer(
      'I forgot my password',
      sensorData,
      riskResult,
      isLiveDeviceData: false,
      language: 'English',
    );

    expect(answer, contains('Forgot password'));
    expect(answer, contains('doz://login-callback/'));
    expect(answer, contains('Do not share passwords'));
  });

  test('offline fallback distinguishes account deletion from clearing history',
      () {
    final service = PhratumaService();
    final english = service.fallbackAnswer(
      'How do I delete my account?',
      sensorData,
      riskResult,
      isLiveDeviceData: false,
      language: 'English',
    );
    final thai = service.fallbackAnswer(
      'ลบบัญชีได้อย่างไร',
      sensorData,
      riskResult,
      isLiveDeviceData: false,
    );

    expect(english, contains('API to confirm deletion first'));
    expect(english, contains('does not delete the account or local data'));
    expect(thai, contains('ต้องเข้าสู่ระบบ'));
    expect(thai, contains('เซิร์ฟเวอร์ยืนยันแล้ว'));
    expect(thai, isNot(contains('ส่งออก sensor buffer')));
  });

  test('offline fallback distinguishes MPU6050 chip temperature from skin', () {
    final answer = PhratumaService().fallbackAnswer(
      'Does the MPU6050 measure skin temperature?',
      sensorData,
      riskResult,
      isLiveDeviceData: false,
      language: 'English',
    );

    expect(answer, contains('not skin temperature'));
    expect(answer, contains('does not send temperature'));
  });

  test('offline fallback explains raw MAX30102 counts are not SpO2', () async {
    final service = PhratumaService();
    final answer = service.fallbackAnswer(
      'ค่า Red/IR คือ SpO2 หรือไม่',
      SensorData(
        heartRate: 0,
        spo2: 0,
        gsr: 0,
        temperature: 0,
        accelX: 0,
        accelY: 0,
        accelZ: 0,
        gyroX: 0,
        gyroY: 0,
        gyroZ: 0,
        rawRed: 123456,
        rawIr: 98765,
      ),
      riskResult,
      isLiveDeviceData: true,
    );

    expect(answer, contains('raw telemetry'));
    expect(answer, contains('ไม่ใช่ค่า HR หรือ SpO₂ โดยตรง'));
  });

  test('offline fallback follows the selected English app language', () async {
    final service = PhratumaService();
    final answer = await service.ask(
      endpoint: 'https://api.example.net/chat',
      model: 'test-model',
      userMessage: 'How do I connect Bluetooth?',
      sensorData: sensorData,
      riskResult: riskResult,
      isLiveDeviceData: false,
      enabled: false,
      useMockResponse: true,
      language: 'English',
    );

    expect(answer, contains('No live readings from a physical device'));
    expect(answer, contains('Local help (not generated by remote AI)'));
    expect(answer, contains('To connect:'));
    expect(answer, isNot(contains('ยังไม่มีข้อมูลสด')));
  });

  test('raw device telemetry is not presented as heart rate or SpO2', () async {
    http.Request? captured;
    final rawSensorData = SensorData(
      heartRate: 0,
      spo2: 0,
      gsr: 0,
      temperature: 0,
      accelX: 0.1,
      accelY: 0.2,
      accelZ: 9.8,
      gyroX: 0,
      gyroY: 0,
      gyroZ: 0,
      rawRed: 120000,
      rawIr: 90000,
    );
    final service = PhratumaService(
      client: MockClient((request) async {
        captured = request;
        return http.Response('{"answer":"Raw data received."}', 200);
      }),
    );

    await service.ask(
      endpoint: 'https://api.example.net/chat',
      model: 'test-model',
      userMessage: 'Interpret this reading',
      sensorData: rawSensorData,
      riskResult: const RiskResult(
        riskClass: 'AI analysis unavailable',
        alertLevel: 'Unknown',
        detectedSigns: ['raw telemetry only'],
        recommendation: 'AI analysis is unavailable.',
      ),
      isLiveDeviceData: true,
      enabled: true,
      useMockResponse: false,
      bearerToken: 'test-access-token',
    );

    final prompt = (jsonDecode(captured!.body)
        as Map<String, dynamic>)['prompt'] as String;
    expect(prompt, contains('Red ADC mean: 120000'));
    expect(prompt, contains('does not provide heart rate, SpO2'));
    expect(prompt, isNot(contains('Heart Rate: 0 BPM')));
    expect(prompt, isNot(contains('SpO2: 0 %')));
  });
}
