import 'dart:convert';

import 'package:doz/models/alert_record.dart';
import 'package:doz/models/risk_result.dart';
import 'package:doz/models/sensor_data.dart';
import 'package:doz/services/cloud_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('health-data upload omits battery when firmware did not report it',
      () async {
    http.Request? captured;
    final service = CloudService(
      client: MockClient((request) async {
        captured = request;
        return http.Response('{"ok":true}', 200);
      }),
    );
    final sensor = SensorData(
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
    );
    const risk = RiskResult(
      riskClass: 'Unknown',
      alertLevel: 'Unknown',
      detectedSigns: [],
      recommendation: 'Unavailable',
    );

    final uploaded = await service.uploadSensor(
      baseUrl: 'https://api.example.net',
      bearerToken: 'test-token',
      sensorData: sensor,
      riskResult: risk,
      userProfile: const {},
      battery: null,
      bleStatus: 'connected',
      sensorStatus: 'raw telemetry',
    );

    expect(uploaded, isTrue);
    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body.containsKey('battery'), isFalse);
  });

  test('remote advice sends the authenticated user token', () async {
    http.Request? captured;
    final service = CloudService(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          '{"advice":"Take a break","mode":"fallback"}',
          200,
        );
      }),
    );

    final result = await service.fetchAdvice(
      baseUrl: 'https://api.example.net',
      status: 'Drowsiness',
      alertLevel: 'Warning',
      sensor: 'raw telemetry summary',
      bearerToken: 'access-token',
    );

    expect(result?.advice, 'Take a break');
    expect(captured?.headers['Authorization'], 'Bearer access-token');
    expect(captured?.followRedirects, isFalse);
    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body['status'], 'Drowsiness');
  });

  test('advice is not requested without an authenticated token', () async {
    var requestSent = false;
    final service = CloudService(
      client: MockClient((_) async {
        requestSent = true;
        return http.Response('{}', 200);
      }),
    );

    final result = await service.fetchAdvice(
      baseUrl: 'https://api.example.net',
      status: 'Drowsiness',
      alertLevel: 'Warning',
      sensor: 'raw telemetry summary',
      bearerToken: '',
    );

    expect(requestSent, isFalse);
    expect(result, isNull);
  });

  test('remote advice refuses unsafe destinations before sending the token',
      () async {
    var requestSent = false;
    final service = CloudService(
      client: MockClient((_) async {
        requestSent = true;
        return http.Response('{"advice":"unsafe"}', 200);
      }),
    );

    for (final baseUrl in [
      'http://api.example.net',
      'https://user:secret@api.example.net',
      'https://api.example.net?redirect=https://attacker.example',
    ]) {
      expect(
        await service.fetchAdvice(
          baseUrl: baseUrl,
          status: 'Drowsiness',
          alertLevel: 'Warning',
          sensor: 'private sensor data',
          bearerToken: 'secret-test-token',
        ),
        isNull,
      );
    }
    expect(requestSent, isFalse);
  });

  test('account deletion sends bearer token to the secure endpoint', () async {
    http.Request? captured;
    final service = CloudService(
      client: MockClient((request) async {
        captured = request;
        return http.Response('', 204);
      }),
    );

    final result = await service.deleteAccount(
      baseUrl: 'https://api.example.net/',
      bearerToken: 'user-access-token',
    );

    expect(result, AccountDeletionResult.deleted);
    expect(captured?.method, 'DELETE');
    expect(captured?.url.path, '/account');
    expect(captured?.headers['Authorization'], 'Bearer user-access-token');
    expect(captured?.followRedirects, isFalse);
  });

  test('account deletion refuses insecure remote URLs and missing token',
      () async {
    var requestSent = false;
    final service = CloudService(
      client: MockClient((_) async {
        requestSent = true;
        return http.Response('', 204);
      }),
    );

    final insecure = await service.deleteAccount(
      baseUrl: 'http://api.example.net',
      bearerToken: 'user-access-token',
    );
    final missingToken = await service.deleteAccount(
      baseUrl: 'https://api.example.net',
      bearerToken: '',
    );

    expect(insecure, AccountDeletionResult.notConfigured);
    expect(missingToken, AccountDeletionResult.notConfigured);
    expect(requestSent, isFalse);
  });

  test('health-data upload is blocked without an authenticated token',
      () async {
    var requestSent = false;
    final service = CloudService(
      client: MockClient((_) async {
        requestSent = true;
        return http.Response('{"ok":true}', 200);
      }),
    );
    final sensor = SensorData(
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
    );
    const risk = RiskResult(
      riskClass: 'Unknown',
      alertLevel: 'Unknown',
      detectedSigns: [],
      recommendation: 'Unavailable',
    );

    final uploaded = await service.uploadAlert(
      baseUrl: 'https://api.example.net',
      bearerToken: '',
      alert: AlertRecord(
        id: 'test-alert',
        timestamp: DateTime.utc(2026),
        sensorData: sensor,
        riskResult: risk,
      ),
      userProfile: const {},
    );

    expect(uploaded, isFalse);
    expect(requestSent, isFalse);
  });
}
