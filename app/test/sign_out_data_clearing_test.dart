import 'package:doz/main.dart';
import 'package:doz/models/sensor_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_memory_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sign-out clears in-memory account data but keeps scoped local data',
      () async {
    SharedPreferences.setMockInitialValues({});
    final state =
        DozState.forTesting(secureStore: InMemorySecureKeyValueStore());
    await state.initialize(authUserId: 'account-a');
    await state.completeSetup(
      newName: 'Account A',
      newWeight: 62,
      newHeight: 170,
      newAge: 25,
      newGender: 'Female',
      newConditions: 'None',
    );
    state.sensorHistory.add(SensorData(
      heartRate: 80,
      spo2: 97,
      gsr: 20,
      temperature: 36.5,
      accelX: 0,
      accelY: 0,
      accelZ: 1,
      gyroX: 0,
      gyroY: 0,
      gyroZ: 0,
    ));

    await state.clearRuntimeDataOnSignOut();

    expect(state.userName, isEmpty);
    expect(state.profileDetailsProvided, isFalse);
    expect(state.sensorHistory, isEmpty);
    expect(state.setupDone, isFalse);
    expect(state.currentRisk.alertLevel, 'Unknown');
    expect(state.lastReadingWasFromDevice, isFalse);

    await state.bindAuthenticatedUser('account-a');

    expect(state.userName, 'Account A');
    expect(state.setupDone, isTrue);
    expect(state.sensorHistory, isEmpty);
    state.dispose();
  });

  test('account switch clears prior live-device provenance and battery state',
      () async {
    SharedPreferences.setMockInitialValues({});
    final state =
        DozState.forTesting(secureStore: InMemorySecureKeyValueStore());
    await state.initialize(authUserId: 'account-a');
    state
      ..bleConnected = true
      ..lastReadingWasFromDevice = true
      ..lastSensorUpdateAt = DateTime.now()
      ..deviceBattery = 73;

    await state.bindAuthenticatedUser('account-b');

    expect(state.bleConnected, isFalse);
    expect(state.lastReadingWasFromDevice, isFalse);
    expect(state.lastSensorUpdateAt, isNull);
    expect(state.deviceBattery, isNull);
    expect(state.authScopeId, 'account-b');
    expect(state.currentRisk.alertLevel, 'Unknown');
    expect(state.currentRisk.riskClass, 'AI analysis unavailable');
    expect(state.bleStatus, 'Mock BLE stream connected');
    expect(state.sensorStatus, 'No sensor data yet');
    state.dispose();
  });
}
