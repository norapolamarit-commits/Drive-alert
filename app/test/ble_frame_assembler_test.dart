import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:doz/services/ble_frame_assembler.dart';

List<List<int>> splitIntoFrames(List<int> bytes, int sequence) {
  const payloadSize = 14;
  final total = (bytes.length + payloadSize - 1) ~/ payloadSize;
  return List.generate(total, (index) {
    final start = index * payloadSize;
    final end = (start + payloadSize).clamp(0, bytes.length);
    return [
      0xD0,
      0x5A,
      sequence & 0xFF,
      (sequence >> 8) & 0xFF,
      index,
      total,
      ...bytes.sublist(start, end),
    ];
  });
}

void main() {
  test('reassembles fragments delivered out of order', () {
    final assembler = DozBleFrameAssembler();
    final original = utf8.encode(
      '{"type":"telemetry","v":1,"a":[-20,8,16384],"ai":false}',
    );
    final frames = splitIntoFrames(original, 513);
    final order = [...frames.reversed];

    for (final frame in order.take(order.length - 1)) {
      expect(assembler.add(frame), isNull);
    }
    expect(assembler.add(order.last), original);
  });

  test('passes legacy complete packets through unchanged', () {
    final assembler = DozBleFrameAssembler();
    final oldPacket = List<int>.generate(15, (index) => index);
    expect(assembler.add(oldPacket), oldPacket);
  });

  test('rejects invalid frame metadata and clears buffered state', () {
    final assembler = DozBleFrameAssembler();
    expect(assembler.add([0xD0, 0x5A, 1, 0, 0, 0]), isNull);
    final packet =
        utf8.encode('{"ok":"a longer packet requiring multiple BLE frames"}');
    final frames = splitIntoFrames(packet, 2);
    expect(assembler.add(frames.first), isNull);
    expect(assembler.add([0xD0, 0x5A, 2, 0, 1, 1, 0x7B]), isNull);
  });

  test('rejects oversized BLE fragments before buffering their payload', () {
    final assembler = DozBleFrameAssembler();
    final oversized = [
      0xD0,
      0x5A,
      1,
      0,
      0,
      1,
      ...List<int>.filled(15, 0x41),
    ];

    expect(assembler.add(oversized), isNull);
    expect(
        assembler.add([0xD0, 0x5A, 1, 0, 0, 15, ...List<int>.filled(14, 0x41)]),
        isNull);
  });

  test('rejects assembled JSON beyond the firmware buffer size', () {
    final assembler = DozBleFrameAssembler();
    final first = [0xD0, 0x5A, 9, 0, 0, 14, ...List<int>.filled(14, 0x41)];
    expect(assembler.add(first), isNull);
    for (var index = 1; index < 13; index++) {
      expect(
        assembler.add([
          0xD0,
          0x5A,
          9,
          0,
          index,
          14,
          ...List<int>.filled(14, 0x41),
        ]),
        isNull,
      );
    }
    expect(
      assembler.add([0xD0, 0x5A, 9, 0, 13, 14, ...List<int>.filled(14, 0x41)]),
      isNull,
    );
    // EN: A fresh valid one-frame packet still works after rejection.
    // TH: หลังปฏิเสธ packet แล้ว ยังประกอบ packet ใหม่ที่ถูกต้องได้
    final valid = utf8.encode('{"type":"ok"}');
    expect(assembler.add(splitIntoFrames(valid, 10).single), valid);
  });
}
