import 'dart:convert';

import 'package:doz/models/alert_record.dart';
import 'package:doz/models/risk_result.dart';
import 'package:doz/models/sensor_data.dart';
import 'package:doz/services/alert_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_memory_secure_storage.dart';

AlertRecord _alert(int id) => AlertRecord(
      id: '$id',
      timestamp: DateTime.utc(2026, 1, 1).add(Duration(seconds: id)),
      sensorData: SensorData(
        heartRate: 80,
        spo2: 98,
        gsr: 2,
        temperature: 36.5,
        accelX: 0,
        accelY: 0,
        accelZ: 1,
        gyroX: 0,
        gyroY: 0,
        gyroZ: 0,
      ),
      riskResult: const RiskResult(
        riskClass: 'Drowsiness',
        alertLevel: 'Warning',
        detectedSigns: ['sample'],
        recommendation: 'Pause safely',
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('corrupt local JSON does not crash alert-history loading', () async {
    SharedPreferences.setMockInitialValues({
      'doz.local-demo.alert_history': '{bad json',
    });

    final records = await AlertStorageService(
      secureStore: InMemorySecureKeyValueStore({
        'doz.local-demo.alert_history.secure.v1': '{bad json',
      }),
    ).loadAlerts();

    expect(records, isEmpty);
  });

  test('non-list and malformed entries are ignored', () async {
    final invalidNumericRecord = _alert(2).toJson();
    (invalidNumericRecord['sensorData'] as Map<String, dynamic>)['heart_rate'] =
        'NaN';
    SharedPreferences.setMockInitialValues({
      'doz.local-demo.alert_history': jsonEncode([
        'not an alert object',
        invalidNumericRecord,
        _alert(1).toJson(),
      ]),
    });

    final records = await AlertStorageService(
      secureStore: InMemorySecureKeyValueStore({
        'doz.local-demo.alert_history.secure.v1': jsonEncode([
          'not an alert object',
          invalidNumericRecord,
          _alert(1).toJson(),
        ]),
      }),
    ).loadAlerts();

    expect(records.map((record) => record.id), ['1']);
  });

  test('saving alert history keeps at most the newest-first limit', () async {
    final service =
        AlertStorageService(secureStore: InMemorySecureKeyValueStore());
    final alerts = List<AlertRecord>.generate(520, _alert);

    await service.saveAlerts(alerts);
    final records = await service.loadAlerts();

    expect(records, hasLength(AlertStorageService.maxEntries));
    expect(records.first.id, '0');
    expect(records.last.id, '${AlertStorageService.maxEntries - 1}');
  });

  test('account scopes do not read another scope history', () async {
    final secureStore = InMemorySecureKeyValueStore();
    final first = AlertStorageService(secureStore: secureStore)
      ..setScope('account-a');
    final second = AlertStorageService(secureStore: secureStore)
      ..setScope('account-b');
    await first.saveAlerts([_alert(1)]);

    expect(await first.loadAlerts(), hasLength(1));
    expect(await second.loadAlerts(), isEmpty);
  });

  test('migrates alert history and removes plaintext after verified copy',
      () async {
    SharedPreferences.setMockInitialValues({
      'doz.local-demo.alert_history': jsonEncode([_alert(3).toJson()]),
      'doz_alert_history': jsonEncode([_alert(4).toJson()]),
    });
    final preferences = await SharedPreferences.getInstance();
    final secureStore = InMemorySecureKeyValueStore();
    final service = AlertStorageService(secureStore: secureStore);

    await service.migrateLegacyHistoryIfNeeded();

    expect((await service.loadAlerts()).map((record) => record.id), ['3', '4']);
    expect(preferences.containsKey('doz.local-demo.alert_history'), isFalse);
    expect(preferences.containsKey('doz_alert_history'), isFalse);
  });

  test('keeps plaintext if secure migration write fails', () async {
    SharedPreferences.setMockInitialValues({
      'doz.local-demo.alert_history': jsonEncode([_alert(5).toJson()]),
    });
    final preferences = await SharedPreferences.getInstance();
    final service = AlertStorageService(
      secureStore: _FailingWriteSecureStorage(),
    );

    await expectLater(service.migrateLegacyHistoryIfNeeded(), throwsStateError);

    expect(preferences.containsKey('doz.local-demo.alert_history'), isTrue);
  });

  test('merges legacy alerts into existing secure history without duplicates',
      () async {
    SharedPreferences.setMockInitialValues({
      'doz.local-demo.alert_history': jsonEncode([
        _alert(2).toJson(),
        _alert(3).toJson(),
      ]),
    });
    final preferences = await SharedPreferences.getInstance();
    final service = AlertStorageService(
      secureStore: InMemorySecureKeyValueStore({
        'doz.local-demo.alert_history.secure.v1':
            jsonEncode([_alert(1).toJson(), _alert(2).toJson()]),
      }),
    );

    await service.migrateLegacyHistoryIfNeeded();

    expect((await service.loadAlerts()).map((record) => record.id),
        ['1', '2', '3']);
    expect(preferences.containsKey('doz.local-demo.alert_history'), isFalse);
  });
}

class _FailingWriteSecureStorage extends InMemorySecureKeyValueStore {
  @override
  Future<void> write(String key, String value) async {
    throw StateError('secure write failed');
  }
}
