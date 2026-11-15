import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show
        kIsWeb; // EN: Skip native permission calls in browsers. TH: ข้ามการขอ permission แบบ native ใน browser
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/risk_result.dart';
import '../models/sensor_data.dart';
import 'ble_frame_assembler.dart';
import 'device_risk_mapper.dart';

/// EN: One BLE reading may contain raw sensor telemetry and an optional device inference.
/// TH: BLE reading หนึ่งชุดอาจมี telemetry ดิบ และอาจมีผล inference จากอุปกรณ์
/// EN: Current JSON v1 firmware sends ai=false, so its riskResult is null and analysisAvailable=false.
/// TH: firmware JSON v1 ปัจจุบันส่ง ai=false จึงไม่มี riskResult และ analysisAvailable=false
class DozDeviceReading {
  DozDeviceReading({
    required this.sensorData,
    this.riskResult,
    required this.battery,
    required this.analysisAvailable,
    this.droppedBleReports,
  });

  final SensorData sensorData;
  final RiskResult? riskResult;
  final int?
      battery; // EN: Null means this packet did not report battery. TH: null หมายถึง packet นี้ไม่ได้รายงานแบตเตอรี่
  final bool analysisAvailable;
  // EN: Reports skipped by the firmware BLE transmit queue since its last accepted report.
  // TH: จำนวน report ที่คิวส่ง BLE ของ firmware ข้ามตั้งแต่ report ที่รับเข้าคิวครั้งก่อน
  final int? droppedBleReports;
}

class BleService {
  static const MethodChannel _platformChannel = MethodChannel('doz/platform');
  // TH: UUID และ JSON/framing ตรงกับ max30102_mpu6050_stream_esp32.ino; decoder 15-byte และ
  //     Cmd characteristic ด้านล่างคงไว้เพื่อรองรับ firmware รุ่นเก่าเท่านั้น
  // EN: UUIDs and JSON/framing match max30102_mpu6050_stream_esp32.ino. The 15-byte decoder and
  //     Cmd characteristic below remain only for legacy firmware compatibility.
  static const String defaultServiceUuid =
      '6b2f0001-4f2a-4c3e-9a1b-9d5e7c1a0001';
  static const String defaultLiveCharacteristicUuid =
      '6b2f0002-4f2a-4c3e-9a1b-9d5e7c1a0001';
  static const String cmdCharacteristicUuid =
      '6b2f0004-4f2a-4c3e-9a1b-9d5e7c1a0001';
  static const int _livePacketSize = 15;
  static const int _cmdAck = 1;
  static const int _maxTelemetryPacketBytes =
      191; // EN: Match the firmware JSON buffer minus its NUL byte. TH: ตรงกับ buffer JSON ของ firmware โดยหัก byte ปิดข้อความ
  static const int _maxPpgSamplesPerReport =
      500; // EN: Allow 5x the nominal 100 Hz one-second count for jitter, not unbounded values. TH: เผื่อ jitter ได้ 5 เท่าจาก 100 Hz ต่อวินาที แต่ไม่รับค่าที่ไร้ขอบเขต
  static const int _maxImuSamplesPerReport =
      250; // EN: Allow 5x the nominal 50 Hz one-second count for jitter. TH: เผื่อ jitterได้ 5 เท่าจาก 50 Hz ต่อวินาที

  final StreamController<DozDeviceReading> _readingController =
      StreamController<DozDeviceReading>.broadcast();
  final StreamController<String> _disconnectController =
      StreamController<String>.broadcast();

  BluetoothDevice? _device;
  BluetoothDevice? _lastFoundDevice;
  bool _scanInProgress = false;
  bool _connectInProgress = false;
  bool _disposed = false;
  int _connectionGeneration =
      0; // EN: Invalidate callbacks from older BLE sessions. TH: ทำให้ callback จาก BLE session เก่าใช้ต่อไม่ได้
  BluetoothCharacteristic? _cmdCharacteristic;
  String? _connectedServiceUuid;
  String? _connectedCharacteristicUuid;
  int? _lastTelemetryTimestampMs;
  StreamSubscription<List<int>>? _sensorSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  final DozBleFrameAssembler _frameAssembler =
      DozBleFrameAssembler(); // EN: Reassemble small-MTU notifications. TH: ประกอบ notification ที่ถูกแบ่งเพราะ MTU เล็ก

  Stream<DozDeviceReading> get deviceReadingStream => _readingController.stream;
  Stream<String> get deviceDisconnectedStream => _disconnectController.stream;
  bool get isConnected => _device != null;

  // TH: ยังรับ override ผ่าน --dart-define ได้เหมือนเดิม แต่ default เป็น UUID จริงของ
  //     เฟิร์มแวร์ doz แทนสตริงว่าง (เดิมว่างแล้ว fallback ไปหา characteristic notify ตัวแรก
  //     ที่เจอ ซึ่งเสี่ยงจับผิดตัวเมื่อเฟิร์มแวร์มีทั้ง Live และ OTA เป็น notify เหมือนกัน)
  // EN: still overridable via --dart-define, but now defaults to the real doz firmware UUIDs
  //     instead of an empty string (which used to fall back to "the first notify
  //     characteristic found" -- risky now that the firmware has both Live and OTA as notify).
  String get configuredServiceUuid {
    const fromEnv = String.fromEnvironment('VITAGAURD_BLE_SERVICE_UUID');
    return fromEnv.isEmpty ? defaultServiceUuid : fromEnv;
  }

  String get configuredCharacteristicUuid {
    const fromEnv = String.fromEnvironment('VITAGAURD_BLE_CHARACTERISTIC_UUID');
    return fromEnv.isEmpty ? defaultLiveCharacteristicUuid : fromEnv;
  }

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
    Future<void>? cancelSignal,
  }) async {
    // EN: Reject overlapping plugin scans/connections and unreasonable durations.
    // TH: ปฏิเสธ scan/connect ที่ซ้อนกันและระยะเวลาที่ไม่สมเหตุผล
    _ensureActive();
    if (_scanInProgress || _connectInProgress) {
      throw StateError('A BLE scan or connection is already in progress.');
    }
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 1)) {
      throw ArgumentError.value(
          timeout, 'timeout', 'Must be between 0 and 1 minute.');
    }
    _scanInProgress = true;
    try {
      return await _performScan(timeout: timeout, cancelSignal: cancelSignal);
    } finally {
      _scanInProgress = false;
    }
  }

  Future<List<ScanResult>> _performScan({
    required Duration timeout,
    Future<void>? cancelSignal,
  }) async {
    await _requestBlePermissions();
    _ensureActive();
    final adapterState = await FlutterBluePlus.adapterState
        .firstWhere(isAdapterStateSettled)
        .timeout(const Duration(seconds: 8), onTimeout: () {
      throw StateError(
        'Bluetooth status is still starting. Wait a few seconds and scan again.',
      );
    });
    final adapterMessage = adapterAvailabilityMessage(adapterState);
    if (adapterMessage != null) {
      throw StateError(adapterMessage);
    }
    _ensureActive();
    await FlutterBluePlus.startScan(timeout: timeout);
    try {
      final scanFinished = FlutterBluePlus.isScanning
          .where((scanning) => !scanning)
          .first
          .timeout(timeout + const Duration(seconds: 2))
          .then<void>((_) {});
      if (cancelSignal == null) {
        await scanFinished;
      } else {
        await Future.any<void>([scanFinished, cancelSignal]);
      }
    } on TimeoutException {
      // Stop explicitly if the plugin/platform did not end the timed scan.
    } finally {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    }
    final results = FlutterBluePlus.lastScanResults;
    _ensureActive();
    // TH: แสดงเฉพาะชื่อที่มี Doz หรือ service UUID ของ firmware เพื่อไม่ให้ผู้ใช้เลือก
    //     บอร์ด ESP32/อุปกรณ์ BLE อื่นที่ไม่รองรับโดยไม่ตั้งใจ
    // EN: show only Doz-named advertisements or the firmware service UUID, so users
    //     do not accidentally select unrelated ESP32 boards or BLE peripherals.
    final matches = results
        .where((result) => matchesDozAdvertisement(
              platformName: result.device.platformName,
              advertisedName: result.advertisementData.advName,
              serviceUuids:
                  result.advertisementData.serviceUuids.map((uuid) => uuid.str),
              expectedServiceUuid: configuredServiceUuid,
            ))
        .toList();
    _lastFoundDevice = matches.isEmpty ? null : matches.first.device;
    return matches;
  }

  Future<void> stopScan() async {
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
  }

  /// Gives a platform-neutral, actionable explanation before starting a scan.
  /// Null means Bluetooth LE is ready to scan.
  static String? adapterAvailabilityMessage(BluetoothAdapterState state) {
    return switch (state) {
      BluetoothAdapterState.on => null,
      BluetoothAdapterState.off ||
      BluetoothAdapterState.turningOff =>
        'Bluetooth is off. Turn it on in device Settings, then scan again.',
      BluetoothAdapterState.unauthorized =>
        'Bluetooth access is denied. Allow Bluetooth for doz in app Settings.',
      BluetoothAdapterState.unavailable =>
        'Bluetooth LE is unavailable on this device.',
      BluetoothAdapterState.turningOn =>
        'Bluetooth is turning on. Wait a moment and scan again.',
      BluetoothAdapterState.unknown =>
        'Bluetooth status is unavailable. Check Bluetooth and app permissions, then retry.',
    };
  }

  /// Ignore transient startup states; the first stream event can be `unknown`
  /// while CoreBluetooth/Android is still reporting the adapter state.
  static bool isAdapterStateSettled(BluetoothAdapterState state) =>
      state != BluetoothAdapterState.unknown &&
      state != BluetoothAdapterState.turningOn;

  /// Only show the Doz device, not every nearby ESP32 or BLE peripheral.
  /// A matching service UUID is preferred; the advertised Doz name is retained
  /// as a discovery fallback because some platforms omit service UUIDs in scans.
  /// EN: This is a discovery filter, not device authentication; BLE identity is not cryptographically verified.
  /// TH: นี่เป็นตัวกรองค้นหา ไม่ใช่การยืนยันตัวอุปกรณ์; ยังไม่มีการตรวจ identity ด้วย cryptography
  static bool matchesDozAdvertisement({
    required String platformName,
    required String advertisedName,
    required Iterable<String> serviceUuids,
    required String expectedServiceUuid,
  }) {
    final serviceMatches = serviceUuids.any(
      (uuid) => uuid.toLowerCase() == expectedServiceUuid.toLowerCase(),
    );
    final hasDozName =
        '$platformName $advertisedName'.toLowerCase().contains('doz');
    return serviceMatches || hasDozName;
  }

  Future<void> connectLastFound() async {
    final device = _lastFoundDevice;
    if (device == null) {
      throw Exception('No scanned ESP32 device is available');
    }
    await connect(device);
  }

  Future<void> connect(BluetoothDevice device) async {
    _ensureActive();
    if (_connectInProgress || _scanInProgress) {
      throw StateError('A BLE scan or connection is already in progress.');
    }
    if (_device?.remoteId.str == device.remoteId.str) return;
    _connectInProgress = true;
    try {
      if (_device != null) await disconnect();
      await _connectDevice(device);
    } finally {
      _connectInProgress = false;
    }
  }

  Future<void> _connectDevice(BluetoothDevice device) async {
    final generation =
        ++_connectionGeneration; // EN: Give this connection attempt a unique epoch. TH: กำหนด epoch เฉพาะให้ความพยายามเชื่อมต่อนี้
    _lastTelemetryTimestampMs = null;
    StreamSubscription<List<int>>? pendingSubscription;
    StreamSubscription<BluetoothConnectionState>? pendingConnectionSubscription;
    try {
      await device.connect(
          timeout: const Duration(seconds: 12), autoConnect: false);
      _ensureConnectionGeneration(generation);
      final services = await device.discoverServices();
      _ensureConnectionGeneration(generation);
      final characteristic = _findLiveCharacteristic(services);

      if (characteristic == null) {
        throw Exception('ไม่พบ BLE characteristic สำหรับข้อมูลอุปกรณ์ (Live)');
      }
      await characteristic.setNotifyValue(true);
      _ensureConnectionGeneration(generation);
      pendingSubscription = characteristic.onValueReceived.listen((bytes) {
        // EN: Ignore late notifications after disconnect, reconnect, or device switch.
        // TH: ทิ้ง notification ที่มาช้าหลัง disconnect, reconnect หรือเปลี่ยนอุปกรณ์
        if (_disposed ||
            generation != _connectionGeneration ||
            _device?.remoteId.str != device.remoteId.str) {
          return; // EN: Ignore data from a no-longer-active connection. TH: ข้ามข้อมูลจาก connection ที่ไม่ active แล้ว
        }
        final completePacket = _frameAssembler.add(
            bytes); // EN: Reassemble low-MTU frames before decoding. TH: ประกอบ frame ที่ถูกแบ่งเพราะ MTU เล็กก่อนถอดรหัส
        if (completePacket == null) {
          return; // EN: Wait for remaining fragments. TH: รอ fragment ที่เหลือ
        }
        final reading = _decodeLivePacket(completePacket);
        if (reading != null) {
          final deviceTimestamp = reading.sensorData.deviceTimestampMs;
          if (deviceTimestamp != null) {
            // EN: Reject duplicate or backward device time within one connection.
            // TH: ปฏิเสธเวลาอุปกรณ์ซ้ำหรือย้อนกลับภายในการเชื่อมต่อครั้งเดียว
            if (!acceptMonotonicTimestamp(
                _lastTelemetryTimestampMs, deviceTimestamp)) {
              return;
            }
            _lastTelemetryTimestampMs = deviceTimestamp;
          }
          if (!_disposed) _readingController.add(reading);
        }
        // TH: แพ็กเก็ตที่ผิดรูปแบบจะไม่ถูกใช้; รอ notification ถัดไป
        // EN: Ignore malformed packets and wait for the next notification.
      });

      // Publish connection state only after service discovery and notifications succeed.
      _ensureConnectionGeneration(generation);
      _device = device;
      _connectedServiceUuid = services
          .firstWhere(
              (service) => service.characteristics.contains(characteristic))
          .uuid
          .str;
      _connectedCharacteristicUuid = characteristic.uuid.str;
      _cmdCharacteristic =
          _findCharacteristicByUuid(services, cmdCharacteristicUuid);
      _sensorSubscription = pendingSubscription;
      pendingSubscription = null;
      pendingConnectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected &&
            generation == _connectionGeneration &&
            _device?.remoteId.str == device.remoteId.str) {
          _handleUnexpectedDisconnect(device, generation);
        }
      });
      if (generation != _connectionGeneration ||
          _device?.remoteId.str != device.remoteId.str) {
        // EN: Catch a disconnect emitted immediately when subscribing to state.
        // TH: ตรวจจับ disconnect ที่ส่งมาทันทีตอน subscribe สถานะการเชื่อมต่อ
        await pendingConnectionSubscription.cancel();
        pendingConnectionSubscription = null;
        throw StateError('BLE device disconnected during connection setup.');
      }
      _connectionSubscription = pendingConnectionSubscription;
      pendingConnectionSubscription = null;
    } catch (_) {
      if (_connectionGeneration == generation) {
        _connectionGeneration++; // EN: Invalidate callbacks from this failed attempt. TH: ยกเลิก callback ของความพยายามที่ล้มเหลว
      }
      await pendingSubscription?.cancel();
      await pendingConnectionSubscription?.cancel();
      _frameAssembler.reset();
      _device = null;
      _lastTelemetryTimestampMs = null;
      _cmdCharacteristic = null;
      _connectedServiceUuid = null;
      _connectedCharacteristicUuid = null;
      try {
        await device.disconnect();
      } catch (_) {
        // Preserve the original connection error if cleanup also fails.
      }
      rethrow;
    }
  }

  /// TH: ส่งคำสั่ง "รับทราบ" (DOZ_CMD_ACK) กลับไปที่เฟิร์มแวร์ผ่าน Cmd characteristic เพื่อ
  ///     หยุดตัวจับเวลา 30 วินาทีที่บอร์ดเอง (spec R5: "no response after Warning (30s)")
  ///     คืน false เงียบ ๆ ถ้ายังไม่เชื่อมต่อ/หา characteristic ไม่เจอ — ไม่ throw เพราะการกด
  ///     ตอบรับในแอปต้องสำเร็จเสมอสำหรับ mock/demo mode ที่ไม่มีอุปกรณ์จริงต่ออยู่
  /// EN: Sends the "acknowledge" command (DOZ_CMD_ACK) back to the firmware over the Cmd
  ///     characteristic, to stop the board's own 30-second timer (spec R5: "no response after
  ///     Warning (30s)"). Silently returns false if not connected / characteristic not found --
  ///     doesn't throw, since acknowledging in the app must always succeed for mock/demo mode
  ///     with no real device attached.
  Future<bool> sendAck() async {
    if (_disposed) return false;
    final characteristic = _cmdCharacteristic;
    if (characteristic == null) {
      return false;
    }
    try {
      await characteristic.write([_cmdAck], withoutResponse: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    _connectionGeneration++; // EN: Invalidate in-flight connects and callbacks immediately. TH: ยกเลิก connect ที่ค้างและ callback ทันที
    final device = _device;
    _device = null;
    _lastTelemetryTimestampMs = null;
    await _sensorSubscription?.cancel();
    _sensorSubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _frameAssembler
        .reset(); // EN: Discard an incomplete packet on disconnect. TH: ทิ้ง packet ที่ประกอบไม่ครบเมื่อตัดการเชื่อมต่อ
    _cmdCharacteristic = null;
    _connectedServiceUuid = null;
    _connectedCharacteristicUuid = null;
    if (device != null) {
      await device.disconnect();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _connectionGeneration++; // EN: Reject callbacks before asynchronous cleanup begins. TH: ปฏิเสธ callback ก่อนเริ่ม cleanup แบบ async
    final device = _device;
    _device = null;
    _lastTelemetryTimestampMs = null;
    final sensorSubscription = _sensorSubscription;
    final connectionSubscription = _connectionSubscription;
    _sensorSubscription = null;
    _connectionSubscription = null;
    _frameAssembler
        .reset(); // EN: Release buffered frame data. TH: ล้างข้อมูล frame ที่พักไว้
    unawaited(_cleanupDisposed(
      sensorSubscription,
      connectionSubscription,
      device,
    ));
    _readingController.close();
    _disconnectController.close();
  }

  Future<void> _cleanupDisposed(
    StreamSubscription<List<int>>? sensorSubscription,
    StreamSubscription<BluetoothConnectionState>? connectionSubscription,
    BluetoothDevice? device,
  ) async {
    // EN: Cancel callbacks before disconnecting, then safely release plugin resources.
    // TH: ยกเลิก callback ก่อนตัดการเชื่อมต่อ แล้วคืน resource ของ plugin อย่างปลอดภัย
    try {
      await sensorSubscription?.cancel();
    } on Object {
      // EN: Disposal must continue if a plugin subscription has already failed.
      // TH: ให้ dispose ทำงานต่อแม้ subscription ของ plugin มีปัญหา
    }
    try {
      await connectionSubscription?.cancel();
    } on Object {
      // EN: Ignore cleanup-only subscription errors. TH: ข้าม error ที่เกิดเฉพาะตอน cleanup
    }
    try {
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    } on Object {
      // EN: The platform may already have ended scanning. TH: platform อาจหยุด scan ไปแล้ว
    }
    try {
      await device?.disconnect();
    } on Object {
      // EN: Do not throw from synchronous ChangeNotifier disposal.
      // TH: ห้ามโยน error ออกจาก dispose แบบ synchronous
    }
  }

  void _ensureActive() {
    if (_disposed) throw StateError('BleService has already been disposed.');
  }

  void _ensureConnectionGeneration(int generation) {
    _ensureActive(); // EN: Preserve the disposed-service guard. TH: คง guard เมื่อ service ถูก dispose
    if (generation != _connectionGeneration) {
      // EN: Stop a connection attempt superseded by disconnect or a newer session.
      // TH: หยุดความพยายามเชื่อมต่อที่ถูกแทนด้วย disconnect หรือ session ใหม่
      throw StateError('BLE connection attempt is no longer active.');
    }
  }

  void _handleUnexpectedDisconnect(BluetoothDevice device, int generation) {
    if (_disposed || generation != _connectionGeneration) return;
    final id = device.remoteId.str;
    if (_device?.remoteId.str != id) return;
    _device = null;
    _lastTelemetryTimestampMs = null;
    _cmdCharacteristic = null;
    _connectedServiceUuid = null;
    _connectedCharacteristicUuid = null;
    _frameAssembler.reset();
    final sensorSubscription = _sensorSubscription;
    _sensorSubscription = null;
    final connectionSubscription = _connectionSubscription;
    _connectionSubscription = null;
    unawaited(_cancelSubscriptionQuietly(sensorSubscription));
    unawaited(_cancelSubscriptionQuietly(connectionSubscription));
    _disconnectController.add(id);
  }

  /// EN: Swallow errors only while releasing a BLE subscription after disconnect.
  /// TH: ข้าม error เฉพาะตอนคืน subscription BLE หลังการตัดการเชื่อมต่อ
  Future<void> _cancelSubscriptionQuietly<T>(
      StreamSubscription<T>? subscription) async {
    try {
      await subscription
          ?.cancel(); // EN: Await plugin cleanup. TH: รอ cleanup ของ plugin
    } on Object {
      // EN: The connection is already gone; cleanup failure must not escape unhandled.
      // TH: การเชื่อมต่อหลุดแล้ว จึงไม่ปล่อย cleanup error ให้กลายเป็น unhandled
    }
  }

  Future<void> _requestBlePermissions() async {
    // iOS prompts through CoreBluetooth using the usage description in Info.plist.
    // On Android 11 and earlier, BLE scanning requires location authorization.
    // On Android 12+, request Nearby Devices only; location is a separate opt-in feature.
    if (kIsWeb || !Platform.isAndroid) {
      // EN: Browser permission flow is separate from Android's. TH: การขอสิทธิ์ใน browser แยกจาก Android
      return; // EN: Never query dart:io Platform on web. TH: ห้ามเรียก Platform ของ dart:io บนเว็บ
    } // EN: Continue with Android permission checks only. TH: ตรวจสิทธิ์ Android ต่อเฉพาะบน Android
    final apiLevel =
        await _platformChannel.invokeMethod<int>('androidApiLevel');
    final requestedPermissions = apiLevel != null && apiLevel < 31
        ? <Permission>[Permission.locationWhenInUse]
        : <Permission>[Permission.bluetoothScan, Permission.bluetoothConnect];
    final statuses = await requestedPermissions.request();
    if (statuses.values.any((status) => status.isPermanentlyDenied)) {
      throw Exception(
          'Bluetooth permission is blocked. Enable it in Settings.');
    }
    if (statuses.values.any((status) => status.isDenied)) {
      throw Exception('Bluetooth permission was not granted.');
    }
    if (apiLevel != null &&
        apiLevel < 31 &&
        !await Geolocator.isLocationServiceEnabled()) {
      throw StateError(
        'Android 11 and earlier require system Location services to be on for BLE scanning. doz does not read location during scanning.',
      );
    }
  }

  BluetoothCharacteristic? _findCharacteristicByUuid(
    List<BluetoothService> services,
    String uuid,
  ) {
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid.str.toLowerCase() == uuid.toLowerCase()) {
          return characteristic;
        }
      }
    }
    return null;
  }

  BluetoothCharacteristic? _findLiveCharacteristic(
    List<BluetoothService> services,
  ) {
    final serviceUuid = configuredServiceUuid;
    final characteristicUuid = configuredCharacteristicUuid;

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

    // EN: Do not subscribe to an arbitrary notify characteristic (e.g. OTA); fail closed. TH: ไม่ subscribe characteristic แบบสุ่ม เพราะอาจเป็น OTA; ให้หยุดเมื่อ UUID ไม่ตรง
    return null;
  }

  /// TH: ถอดรหัสแพ็กเก็ต Live 15 ไบต์ little-endian ของ firmware รุ่นเก่า:
  ///     hr:u8, spo2:u8, gsr_x100:u16, skin_temp_x100:i16, stress_index:u8, state:u8,
  ///     confidence:u8, alert_level:u8, uptime_ms:u32, battery:u8
  /// EN: Decodes the legacy 15-byte little-endian Live packet (field layout above).
  DozDeviceReading? _decodeLivePacket(List<int> bytes) {
    // EN: Dispatch JSON v1 or legacy binary packets by wire format. TH: เลือกถอดรหัส JSON v1 หรือ binary รุ่นเก่าตามรูปแบบข้อมูล
    if (bytes.isNotEmpty && bytes.first == 0x7B) {
      // EN: Route JSON-looking notifications to the current protocol decoder. TH: ส่ง notification ที่เริ่มเหมือน JSON ไป decoder ปัจจุบัน
      // EN: JSON packets start with '{'. TH: packet JSON เริ่มต้นด้วยอักขระ '{'
      return decodeTelemetryJsonPacket(
          bytes); // EN: Decode the versioned raw-telemetry protocol. TH: ถอดรหัสโปรโตคอล raw telemetry ที่มี version
    }
    if (bytes.length != _livePacketSize) {
      // EN: Require the exact fixed length before reading legacy offsets. TH: บังคับความยาวคงที่ให้ตรงก่อนอ่านตำแหน่งข้อมูล legacy
      return null; // EN: Ignore truncated or extended legacy packets. TH: ข้าม packet legacy ที่สั้นหรือยาวผิดขนาด
    }
    final data = ByteData.sublistView(Uint8List.fromList(
        bytes)); // EN: Create a byte view for fixed-offset decoding. TH: สร้างมุมมอง byte สำหรับถอดรหัสตาม offset คงที่
    final hr = data.getUint8(
        0); // EN: Read the legacy heart-rate byte. TH: อ่าน byte ชีพจรของ protocol เก่า
    final spo2 = data.getUint8(
        1); // EN: Read the legacy oxygen estimate byte. TH: อ่าน byte ค่าออกซิเจนประมาณของ protocol เก่า
    final gsrX100 = data.getUint16(
        2,
        Endian
            .little); // EN: Read GSR scaled by 100 as little-endian unsigned data. TH: อ่าน GSR คูณ 100 แบบ unsigned little-endian
    final skinTempX100 = data.getInt16(
        4,
        Endian
            .little); // EN: Read signed skin-temperature hundredths. TH: อ่านอุณหภูมิผิวหน่วยหนึ่งในร้อยแบบ signed
    final state = data.getUint8(
        7); // EN: Read the device state class code. TH: อ่านรหัสคลาสสถานะจากอุปกรณ์
    final confidence = data.getUint8(
        8); // EN: Read confidence on the legacy 0..255 scale. TH: อ่าน confidence ตามสเกลเก่า 0..255
    final alertLevel = data.getUint8(
        9); // EN: Read the legacy alert-level code. TH: อ่านรหัสระดับเตือนของ protocol เก่า
    final battery = data.getUint8(
        14); // EN: Read the reported battery percentage byte. TH: อ่าน byte เปอร์เซ็นต์แบตเตอรี่

    final sensorData = SensorData(
      // EN: Build the app reading without pretending absent IMU axes were measured. TH: สร้างค่าที่แอปใช้โดยไม่แสร้งว่าแกน IMU ที่ไม่มีถูกวัด
      heartRate: hr,
      spo2: spo2,
      gsr: gsrX100 / 100.0,
      temperature: skinTempX100 / 100.0,
      // TH: binary packet รุ่นเก่าไม่มีแกน accel/gyro จึงใส่ 0 เพื่อคง shape ของ SensorData;
      //     ห้ามตีความว่าเป็นค่าที่วัดได้หรือหลักฐานว่า AI รุ่นปัจจุบันทำงานบนบอร์ด
      // EN: The legacy binary packet has no accel/gyro axes, so zeroes preserve SensorData shape;
      //     do not treat them as measured values or evidence that current on-board AI is running.
      accelX: 0,
      accelY: 0,
      accelZ: 0,
      gyroX: 0,
      gyroY: 0,
      gyroZ: 0,
    );
    final riskResult = mapDeviceAlert(
      // EN: Map the legacy device's class/level fields to app alert labels. TH: แปลง class/level จากอุปกรณ์เก่าเป็นป้ายเตือนของแอป
      stateClass: state,
      alertLevel: alertLevel,
      confidencePercent: (confidence / 255.0 * 100).round(),
      spo2: spo2.toDouble(),
    );
    return DozDeviceReading(
      // EN: Package the legacy sensor values and reported inference. TH: รวมค่าจาก sensor เก่าและผล inference ที่รายงานมา
      sensorData: sensorData,
      riskResult: riskResult,
      battery: battery,
      analysisAvailable:
          true, // EN: This legacy binary packet carries device inference. TH: packet binary รุ่นเก่ามีผล inference จากอุปกรณ์
    );
  }

  /// EN: Decode the firmware's versioned telemetry packet without BLE hardware.
  /// TH: ถอดรหัส telemetry ที่มี version โดยไม่ต้องใช้อุปกรณ์ BLE จริง
  static DozDeviceReading? decodeTelemetryJsonPacket(List<int> bytes) {
    // EN: Return null for invalid packets instead of inventing readings. TH: คืน null เมื่อ packet ผิดแทนการสร้างค่าการวัดขึ้นเอง
    // EN: Parse one BLE telemetry notification. TH: แปลง BLE notification telemetry หนึ่งแพ็กเก็ต
    if (bytes.isEmpty ||
        bytes.length > _maxTelemetryPacketBytes ||
        bytes.any((byte) => byte < 0 || byte > 255)) {
      // EN: Reject oversized or invalid wire data before UTF-8/JSON allocation. TH: ปฏิเสธข้อมูลใหญ่เกินหรือ byte ผิดก่อนสร้าง UTF-8/JSON
      return null; // EN: Do not decode data outside the firmware packet bounds. TH: ไม่ถอดรหัสข้อมูลนอกขนาด packet firmware
    } // EN: Finish bounded input validation. TH: จบการตรวจขนาด input
    try {
      // EN: Convert malformed UTF-8/JSON/type data into packet rejection. TH: เปลี่ยน UTF-8/JSON/ชนิดข้อมูลที่ผิดเป็นการปฏิเสธ packet
      // EN: Treat malformed or unexpected payloads as rejected packets. TH: ปฏิเสธข้อมูลที่เสียหรือไม่ตรงรูปแบบ
      final packet = jsonDecode(utf8.decode(bytes,
          allowMalformed:
              false)); // EN: Decode UTF-8 JSON. TH: ถอดรหัส JSON แบบ UTF-8
      if (packet is! Map<String,
              dynamic> || // EN: Require a JSON object with the expected telemetry protocol identity. TH: บังคับ JSON object และตัวระบุ protocol telemetry ที่คาดไว้
          packet['type'] != 'telemetry' ||
          packet['v'] != 1) {
        return null; // EN: Enforce protocol type/version. TH: ตรวจ type และ version ของโปรโตคอล
      }
      if (packet['ai'] != false) {
        return null; // EN: This raw-stream firmware must not masquerade as an AI source. TH: firmware สตรีม raw นี้ห้ามแอบอ้างว่ามีผล AI
      }
      final red = _integer(packet[
          'r']); // EN: Read mean red ADC count. TH: อ่านค่าเฉลี่ย ADC ช่องแดง
      final ir = _integer(packet[
          'i']); // EN: Read mean IR ADC count. TH: อ่านค่าเฉลี่ย ADC ช่อง IR
      final accel = _integerList(packet[
          'a']); // EN: Read mean accelerometer axes. TH: อ่านค่าเฉลี่ย accelerometer ทั้งสามแกน
      final gyro = _integerList(packet[
          'g']); // EN: Read mean gyroscope axes. TH: อ่านค่าเฉลี่ย gyro ทั้งสามแกน
      final ppgCount = _integer(packet[
          'pn']); // EN: Validate that PPG samples existed. TH: ตรวจว่ามีตัวอย่าง PPG
      final imuCount = _integer(packet[
          'in']); // EN: Validate that IMU samples existed. TH: ตรวจว่ามีตัวอย่าง IMU
      final droppedBleReports = _integer(packet['bd']);
      if (red ==
              null || // EN: Require every expected channel and sample count before constructing a reading. TH: บังคับให้ channel และจำนวนตัวอย่างที่คาดไว้ครบก่อนสร้าง reading
          ir == null ||
          accel == null ||
          gyro == null ||
          ppgCount == null ||
          imuCount == null) {
        return null; // EN: Reject missing or malformed fields. TH: ปฏิเสธฟิลด์ที่ขาดหรือผิดรูปแบบ
      }
      // EN: The current firmware always reports a nonnegative 32-bit BLE drop count.
      // TH: firmware ปัจจุบันส่งจำนวน report ที่ข้ามแบบจำนวนเต็ม 32 บิตไม่ติดลบเสมอ
      if (droppedBleReports == null ||
          droppedBleReports < 0 ||
          droppedBleReports > 0xffffffff) {
        return null;
      }
      if (red <
              0 || // EN: Enforce physical integer bounds for optical counts and report sizes. TH: บังคับขอบเขตจำนวนเต็มของ ADC และขนาดรายงาน
          red > 262143 ||
          ir < 0 ||
          ir > 262143 ||
          ppgCount <= 0 ||
          ppgCount > _maxPpgSamplesPerReport ||
          imuCount <= 0 ||
          imuCount > _maxImuSamplesPerReport) {
        return null; // EN: Validate 18-bit ADC range and plausible one-second counts. TH: ตรวจ ADC 18 บิตและจำนวนตัวอย่างต่อวินาทีที่อยู่ในช่วงสมเหตุผล
      }
      if ([...accel, ...gyro].any((value) => value < -32768 || value > 32767)) {
        return null; // EN: Validate signed 16-bit MPU6050 counts. TH: ตรวจ raw count MPU6050 แบบ signed 16-bit
      }
      final timestampMs = _integer(packet[
          't']); // EN: Read device monotonic timestamp. TH: อ่าน timestamp monotonic จากอุปกรณ์
      if (timestampMs == null || timestampMs < 0) {
        // EN: Reject an invalid device timestamp. TH: ปฏิเสธเวลาของอุปกรณ์ที่ผิด
        return null; // EN: Require a present nonnegative clock. TH: บังคับเวลาที่มีค่าและไม่ติดลบ
      } // EN: Continue decoding a valid packet. TH: ถอดรหัส packet ที่เวลาถูกต้องต่อ
      final sensorData = SensorData(
        // EN: Store raw channels and unit-converted mean IMU values. TH: เก็บช่องดิบและค่า IMU เฉลี่ยที่แปลงหน่วยแล้ว
        heartRate:
            0, // EN: Keep the model shape; this firmware packet does not measure heart rate. TH: คงรูปแบบ model แต่ packet firmware นี้ไม่ได้วัดชีพจร
        spo2:
            0, // EN: Do not infer SpO2 from the raw means in this telemetry packet. TH: ไม่อนุมาน SpO2 จากค่าเฉลี่ยดิบใน packet นี้
        gsr:
            0, // EN: This MAX30102/MPU6050 packet has no GSR channel. TH: packet MAX30102/MPU6050 นี้ไม่มี channel GSR
        temperature:
            0, // EN: These metrics are not provided by this raw telemetry packet. TH: packet ดิบนี้ไม่ได้ให้ค่าชีพจร SpO2, GSR หรืออุณหภูมิผิวหนัง
        accelX: accel[0] /
            16384.0 *
            9.80665, // EN: Convert X counts using the configured ±2 g sensitivity. TH: แปลง count แกน X ด้วย sensitivity ช่วง ±2 g
        accelY: accel[1] /
            16384.0 *
            9.80665, // EN: Convert Y counts using the configured ±2 g sensitivity. TH: แปลง count แกน Y ด้วย sensitivity ช่วง ±2 g
        accelZ: accel[2] /
            16384.0 *
            9.80665, // EN: Convert assuming MPU6050 ±2 g range. TH: แปลงโดยสมมติช่วง MPU6050 ±2 g
        gyroX: gyro[0] /
            131.0, // EN: Convert X counts at the configured ±250 deg/s sensitivity. TH: แปลง count แกน X ด้วย sensitivity ช่วง ±250 deg/s
        gyroY: gyro[1] /
            131.0, // EN: Convert Y counts at the configured ±250 deg/s sensitivity. TH: แปลง count แกน Y ด้วย sensitivity ช่วง ±250 deg/s
        gyroZ: gyro[2] /
            131.0, // EN: Convert assuming ±250 deg/s range. TH: แปลงโดยสมมติช่วง ±250 deg/s
        rawRed: red,
        rawIr: ir,
        deviceTimestampMs:
            timestampMs, // EN: Preserve raw optical counts and the boot-relative device clock. TH: เก็บ ADC ดิบและเวลาอุปกรณ์ที่นับจากตอนเปิดเครื่อง
        timestamp: DateTime
            .now(), // EN: Use phone receive time as wall-clock time. TH: ใช้เวลารับข้อมูลบนโทรศัพท์เป็นเวลาปฏิทิน
      );
      return DozDeviceReading(
          // EN: Mark this reading as raw telemetry with no device-side analysis. TH: ระบุ reading นี้เป็น telemetry ดิบที่ไม่มีการวิเคราะห์บนอุปกรณ์
          sensorData: sensorData,
          riskResult: null,
          battery:
              null, // EN: Firmware JSON v1 has no battery field. TH: firmware JSON v1 ไม่มีฟิลด์แบตเตอรี่
          analysisAvailable: false,
          droppedBleReports:
              droppedBleReports); // EN: Preserve transport loss separately from sensor values. TH: เก็บจำนวน report ที่หลุดแยกจากค่าของเซนเซอร์
    } on FormatException {
      // EN: Handle invalid UTF-8 or JSON syntax. TH: จัดการ UTF-8 หรือ syntax JSON ที่ผิด
      // EN: Reject malformed JSON/UTF-8. TH: ปฏิเสธ JSON หรือ UTF-8 ที่ผิดรูปแบบ
      return null; // EN: Ignore invalid packet without creating a prediction. TH: ข้าม packet ที่ผิดโดยไม่สร้างผลทำนาย
    } on TypeError {
      // EN: Handle values whose decoded types violate the packet schema. TH: จัดการค่าที่ type หลัง decode ไม่ตรง schema packet
      // EN: Reject unexpected JSON value types. TH: ปฏิเสธชนิดข้อมูล JSON ที่ไม่คาดหมาย
      return null; // EN: Ignore unexpected packet contents. TH: ข้ามเนื้อหา packet ที่ผิดรูปแบบ
    }
  }

  /// EN: Accept only strictly increasing device timestamps within a connection.
  /// TH: รับเฉพาะ timestamp อุปกรณ์ที่เพิ่มขึ้นอย่างเคร่งครัดใน connection เดียว
  /// EN: Accept only nonnegative timestamps that strictly advance within a connection.
  /// TH: รับเฉพาะ timestamp ไม่ติดลบและเพิ่มขึ้นใน connection เดียว
  static bool acceptMonotonicTimestamp(int? previous, int current) =>
      current >= 0 && (previous == null || current > previous);

  static int? _integer(dynamic value) => value is int
      ? value
      : null; // EN: Accept only integer wire fields. TH: ยอมรับเฉพาะฟิลด์จำนวนเต็มตามโปรโตคอล
  static List<int>? _integerList(dynamic value) => value is List &&
          value.length == 3 &&
          value.every((item) => item
              is int) // EN: Require exactly three integer axes. TH: ต้องมีแกนจำนวนเต็มครบสามค่า
      ? value.cast<
          int>() // EN: Return the validated axis list. TH: คืนรายการแกนที่ผ่านการตรวจ
      : null; // EN: Reject invalid axis arrays. TH: ปฏิเสธรายการแกนที่ผิดรูปแบบ
}
