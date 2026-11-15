import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doz/services/ble_service.dart';

void main() {
  group('BLE adapter guidance', () {
    test('allows scanning only when Bluetooth is on', () {
      expect(
          BleService.isAdapterStateSettled(BluetoothAdapterState.on), isTrue);
      expect(
        BleService.adapterAvailabilityMessage(BluetoothAdapterState.on),
        isNull,
      );
    });

    test('waits through unknown and turning-on startup states', () {
      expect(
        BleService.isAdapterStateSettled(BluetoothAdapterState.unknown),
        isFalse,
      );
      expect(
        BleService.isAdapterStateSettled(BluetoothAdapterState.turningOn),
        isFalse,
      );
      expect(
        BleService.isAdapterStateSettled(BluetoothAdapterState.off),
        isTrue,
      );
    });

    test('explains how to recover from disabled or denied Bluetooth', () {
      expect(
        BleService.adapterAvailabilityMessage(BluetoothAdapterState.off),
        contains('Turn it on'),
      );
      expect(
        BleService.adapterAvailabilityMessage(
            BluetoothAdapterState.unauthorized),
        contains('Allow Bluetooth'),
      );
      expect(
        BleService.adapterAvailabilityMessage(
            BluetoothAdapterState.unavailable),
        contains('unavailable'),
      );
    });

    test('device discovery excludes unrelated ESP32 boards', () {
      expect(
        BleService.matchesDozAdvertisement(
          platformName: 'ESP32 Sensor',
          advertisedName: 'ESP32 Sensor',
          serviceUuids: const [],
          expectedServiceUuid: BleService.defaultServiceUuid,
        ),
        isFalse,
      );
      expect(
        BleService.matchesDozAdvertisement(
          platformName: '',
          advertisedName: '',
          serviceUuids: const [BleService.defaultServiceUuid],
          expectedServiceUuid: BleService.defaultServiceUuid,
        ),
        isTrue,
      );
      expect(
        BleService.matchesDozAdvertisement(
          platformName: 'Doz-ESP32S3',
          advertisedName: '',
          serviceUuids: const [],
          expectedServiceUuid: BleService.defaultServiceUuid,
        ),
        isTrue,
      );
    });
  });
}
