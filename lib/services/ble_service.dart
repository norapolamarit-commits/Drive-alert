import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/sensor_data.dart';

class BleService {
  final StreamController<SensorData> _sensorController =
      StreamController<SensorData>.broadcast();

  BluetoothDevice? _device;
  BluetoothDevice? _lastFoundDevice;
  String? _connectedServiceUuid;
  String? _connectedCharacteristicUuid;
  StreamSubscription<List<int>>? _sensorSubscription;

  Stream<SensorData> get sensorStream => _sensorController.stream;
  bool get isConnected => _device != null;
  String get configuredServiceUuid =>
      const String.fromEnvironment('VITAGAURD_BLE_SERVICE_UUID');
  String get configuredCharacteristicUuid =>
      const String.fromEnvironment('VITAGAURD_BLE_CHARACTERISTIC_UUID');
  String get lastFoundDeviceName =>
      _lastFoundDevice?.platformName.trim().isEmpty ?? true
          ? 'Unknown device'
          : _lastFoundDevice!.platformName;
  String get lastFoundDeviceId => _lastFoundDevice?.remoteId.str ?? '-';
  String get connectedDeviceName => _device?.platformName.trim().isEmpty ?? true
      ? 'Unknown device'
      : _device!.platformName;
  String get connectedDeviceId => _device?.remoteId.str ?? '-';
  String get connectedServiceUuid => _connectedServiceUuid ?? '-';
  String get connectedCharacteristicUuid => _connectedCharacteristicUuid ?? '-';

  Future<List<ScanResult>> scanForEsp32({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    await _requestBlePermissions();
    await FlutterBluePlus.startScan(timeout: timeout);
    await Future<void>.delayed(timeout);
    await FlutterBluePlus.stopScan();
    final results = await FlutterBluePlus.scanResults.first;
    final matches = results
        .where((result) =>
            result.device.platformName.toLowerCase().contains('esp32') ||
            result.advertisementData.advName.toLowerCase().contains('esp32'))
        .toList();
    _lastFoundDevice = matches.isEmpty ? null : matches.first.device;
    return matches;
  }

  Future<void> connectLastFound() async {
    final device = _lastFoundDevice;
    if (device == null) {
      throw Exception('No scanned ESP32 device is available');
    }
    await connect(device);
  }

  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    await device.connect(
        timeout: const Duration(seconds: 12), autoConnect: false);
    final services = await device.discoverServices();
    final characteristic = _findSensorCharacteristic(services);

    if (characteristic == null) {
      throw Exception('ไม่พบ BLE characteristic สำหรับ sensor data');
    }
    _connectedServiceUuid = services
        .firstWhere(
          (service) => service.characteristics.contains(characteristic),
          orElse: () => services.first,
        )
        .uuid
        .str;
    _connectedCharacteristicUuid = characteristic.uuid.str;

    await characteristic.setNotifyValue(true);
    _sensorSubscription = characteristic.onValueReceived.listen((bytes) {
      try {
        final raw = utf8.decode(bytes);
        _sensorController.add(SensorData.fromJsonString(raw));
      } catch (_) {
        // Ignore partial packets; the next valid JSON notification will update UI.
      }
    });
  }

  Future<void> disconnect() async {
    await _sensorSubscription?.cancel();
    final device = _device;
    _device = null;
    _connectedServiceUuid = null;
    _connectedCharacteristicUuid = null;
    if (device != null) {
      await device.disconnect();
    }
  }

  void dispose() {
    _sensorSubscription?.cancel();
    _sensorController.close();
  }

  Future<void> _requestBlePermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  BluetoothCharacteristic? _findSensorCharacteristic(
    List<BluetoothService> services,
  ) {
    const serviceUuid = String.fromEnvironment('VITAGAURD_BLE_SERVICE_UUID');
    const characteristicUuid =
        String.fromEnvironment('VITAGAURD_BLE_CHARACTERISTIC_UUID');

    final characteristics =
        services.expand((service) => service.characteristics);
    if (serviceUuid.isNotEmpty && characteristicUuid.isNotEmpty) {
      for (final service in services) {
        if (service.uuid.str.toLowerCase() != serviceUuid.toLowerCase()) {
          continue;
        }
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid.str.toLowerCase() ==
              characteristicUuid.toLowerCase()) {
            return characteristic;
          }
        }
      }
    }

    return characteristics
        .where((item) => item.properties.notify || item.properties.indicate)
        .firstOrNull;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
