import 'dart:convert';

import 'package:doz/services/ble_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes the current firmware JSON telemetry contract', () {
    final payload = utf8.encode(
      '{"type":"telemetry","v":1,"t":123456,"r":120000,"i":98000,'
      '"a":[0,-8192,16384],"g":[131,-262,0],"pn":100,"in":50,'
      '"bd":3,"ai":false}',
    );

    final reading = BleService.decodeTelemetryJsonPacket(payload);

    expect(reading, isNotNull);
    expect(reading!.sensorData.rawRed, 120000);
    expect(reading.sensorData.rawIr, 98000);
    expect(reading.sensorData.deviceTimestampMs, 123456);
    expect(reading.sensorData.accelX, closeTo(0, 1e-9));
    expect(reading.sensorData.accelY, closeTo(-4.903325, 1e-6));
    expect(reading.sensorData.accelZ, closeTo(9.80665, 1e-6));
    expect(reading.sensorData.gyroX, closeTo(1, 1e-9));
    expect(reading.sensorData.gyroY, closeTo(-2, 1e-9));
    expect(reading.sensorData.heartRate, 0);
    expect(reading.sensorData.spo2, 0);
    expect(reading.analysisAvailable, isFalse);
    expect(reading.droppedBleReports, 3);
    expect(reading.riskResult, isNull);
  });

  test('rejects unsupported, incomplete, out-of-range, and malformed packets',
      () {
    List<int> packet(String json) => utf8.encode(json);
    String json({int red = 10, int ppgCount = 10, bool ai = false}) =>
        '{"type":"telemetry","v":1,"t":1,"r":$red,"i":11,'
        '"a":[0,0,16384],"g":[0,0,0],"pn":$ppgCount,"in":10,"ai":$ai}';

    expect(
      BleService.decodeTelemetryJsonPacket(packet(json(ai: true))),
      isNull,
    );
    expect(
      BleService.decodeTelemetryJsonPacket(packet(json(red: 262144))),
      isNull,
    );
    expect(
      BleService.decodeTelemetryJsonPacket(
          packet('{"type":"telemetry","v":1,"t":1,"r":10,"i":11,'
              '"a":[0,0,16384],"g":[0,0,0],"in":10,"ai":false}')),
      isNull,
    );
    expect(
      BleService.decodeTelemetryJsonPacket(
          packet('{"type":"telemetry","v":1,"r":10,"i":11,'
              '"a":[0,0,16384],"g":[0,0,0],"pn":10,"in":10,"ai":false}')),
      isNull,
    );
    expect(BleService.decodeTelemetryJsonPacket(packet(json(ppgCount: 0))),
        isNull);
    expect(BleService.decodeTelemetryJsonPacket(packet(json())), isNull);
    expect(
      BleService.decodeTelemetryJsonPacket([0xff, 0xfe]),
      isNull,
    );
  });

  test('strictly increasing timestamps reject duplicates and replays', () {
    expect(BleService.acceptMonotonicTimestamp(null, 1), isTrue);
    expect(BleService.acceptMonotonicTimestamp(10, 11), isTrue);
    expect(BleService.acceptMonotonicTimestamp(10, 10), isFalse);
    expect(BleService.acceptMonotonicTimestamp(10, 9), isFalse);
    expect(BleService.acceptMonotonicTimestamp(null, -1), isFalse);
  });
}
