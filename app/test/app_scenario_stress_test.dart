import 'dart:convert'; // EN: Encode BLE frames. TH: เข้ารหัสเฟรม BLE
import 'dart:math'; // EN: Generate reproducible scenarios. TH: สร้างสถานการณ์ที่ทำซ้ำได้

import 'package:doz/screens/chat_screen.dart'; // EN: Exercise chatbot source selection. TH: ทดสอบการเลือกแหล่งตอบ chatbot
import 'package:doz/services/auth_service.dart'; // EN: Exercise Auth configuration validation. TH: ทดสอบการตรวจ config ระบบบัญชี
import 'package:doz/services/ble_frame_assembler.dart'; // EN: Exercise BLE fragment reassembly. TH: ทดสอบการประกอบ fragment BLE
import 'package:doz/services/ble_service.dart'; // EN: Exercise BLE filtering and telemetry decoding. TH: ทดสอบการกรอง BLE และถอดรหัส telemetry
import 'package:doz/services/device_risk_mapper.dart'; // EN: Exercise device-status mapping. TH: ทดสอบการ map สถานะจากอุปกรณ์
import 'package:flutter_test/flutter_test.dart'; // EN: Use Flutter's test runner. TH: ใช้ตัวรันเทสต์ของ Flutter

List<List<int>> _split(List<int> packet, int sequence, int chunkSize) {
  // EN: Split a packet into BLE-compatible chunks. TH: แบ่ง packet เป็นชิ้นสำหรับ BLE
  final count = (packet.length + chunkSize - 1) ~/
      chunkSize; // EN: Calculate the fragment count. TH: คำนวณจำนวน fragment
  return List.generate(count, (index) {
    // EN: Build every fragment with its header. TH: สร้าง fragment พร้อม header ทุกชิ้น
    final start = index *
        chunkSize; // EN: Find this fragment's first byte. TH: หาตำแหน่ง byte แรกของ fragment
    final end = min(
        start + chunkSize,
        packet
            .length); // EN: Clamp the end to packet length. TH: จำกัดปลายไม่ให้เกิน packet
    return [
      0xD0,
      0x5A,
      sequence & 0xFF,
      (sequence >> 8) & 0xFF,
      index,
      count,
      ...packet.sublist(start, end)
    ]; // EN: Add framing metadata and payload. TH: เพิ่ม metadata กรอบและ payload
  }); // EN: Finish the fragment list. TH: จบรายการ fragment
} // EN: End the packet splitter. TH: จบฟังก์ชันแบ่ง packet

void main() {
  // EN: Register deterministic stress scenarios. TH: ลงทะเบียนสถานการณ์ stress แบบทำซ้ำได้
  test('10,000 deterministic scenarios across app safety-critical logic', () {
    // EN: Run 10,000 offline cases without real accounts or devices. TH: รัน 10,000 กรณีแบบออฟไลน์ ไม่ใช้บัญชีหรืออุปกรณ์จริง
    final random = Random(
        20261109); // EN: Fix the seed so failures can be reproduced. TH: ล็อก seed เพื่อทำซ้ำกรณีที่ผิดพลาดได้
    final assembler =
        DozBleFrameAssembler(); // EN: Reuse a frame assembler across cases. TH: ใช้ตัวประกอบเฟรมตัวเดิมตลอดกรณี
    var decodedPackets =
        0; // EN: Count valid telemetry packets. TH: นับ telemetry ที่ถอดรหัสผ่าน
    var assembledPackets =
        0; // EN: Count successfully rebuilt payloads. TH: นับ payload ที่ประกอบกลับสำเร็จ
    var rejectedPackets =
        0; // EN: Count intentionally malformed packets rejected. TH: นับ packet ผิดรูปแบบที่ถูกปฏิเสธ

    for (var caseIndex = 0; caseIndex < 10000; caseIndex++) {
      // EN: Explore 10,000 reproducible combinations. TH: สำรวจชุดค่าที่ทำซ้ำได้ 10,000 แบบ
      final release = random
          .nextBool(); // EN: Vary debug and release Auth policy. TH: สลับเงื่อนไข Auth ของ debug/release
      final useHttps = random
          .nextBool(); // EN: Vary secure versus insecure endpoint schemes. TH: สลับ scheme ปลอดภัย/ไม่ปลอดภัย
      final partialConfig = random.nextInt(5) ==
          0; // EN: Include missing-key configurations. TH: สุ่มกรณี key ตั้งค่าไม่ครบ
      final key = random.nextInt(7) == 0
          ? 'service_role_secret'
          : 'sb_publishable_stress'; // EN: Include a forbidden secret-key case. TH: มีกรณี key ลับที่ห้ามใช้
      final url = partialConfig
          ? ''
          : '${useHttps ? 'https' : 'http'}://${random.nextInt(2) == 0 ? 'demo.example.test' : 'localhost:54321'}'; // EN: Vary endpoint host and scheme. TH: สลับ host และ scheme ของ endpoint
      final authError = authConfigurationError(
          url: url,
          publishableKey: key,
          releaseMode:
              release); // EN: Validate the generated account configuration. TH: ตรวจ config บัญชีที่สุ่มได้
      if (authError == null) {
        // EN: Assert every accepted remote endpoint is safe. TH: ยืนยัน endpoint ระยะไกลที่ผ่านว่าปลอดภัย
        expect(
            url.startsWith('https://') ||
                (!release && url.contains('localhost')),
            isTrue,
            reason:
                'Auth accepted insecure remote URL in case $caseIndex'); // EN: Permit HTTP only for local debug development. TH: อนุญาต HTTP เฉพาะ debug ในเครื่อง
        expect(url, isNot(contains('@')),
            reason:
                'Auth accepted URL credentials in case $caseIndex'); // EN: Reject embedded URL credentials. TH: ปฏิเสธ credential ที่ฝังใน URL
        expect(key.toLowerCase(), isNot(contains('service_role')),
            reason:
                'Auth accepted a server secret in case $caseIndex'); // EN: Ensure server secrets never pass validation. TH: ยืนยันว่า key ฝั่ง server ไม่ผ่าน validation
      } // EN: Finish Auth safety assertions. TH: จบ assertion ด้าน Auth

      final endpoint = random
          .nextBool(); // EN: Vary chatbot endpoint availability. TH: สลับการตั้ง endpoint chatbot
      final signedIn =
          random.nextBool(); // EN: Vary sign-in state. TH: สลับสถานะ login
      final consent = random
          .nextBool(); // EN: Vary privacy consent. TH: สลับ consent ความเป็นส่วนตัว
      final llm = random
          .nextBool(); // EN: Vary remote model enablement. TH: สลับการเปิดใช้โมเดลระยะไกล
      final mock = random
          .nextBool(); // EN: Vary demo response mode. TH: สลับโหมดคำตอบจำลอง
      final chatMode = resolveChatSourceMode(
          endpointConfigured: endpoint,
          signedIn: signedIn,
          consentValid: consent,
          llmEnabled: llm,
          mockMode:
              mock); // EN: Resolve the expected chatbot route. TH: คำนวณเส้นทางตอบ chatbot
      if (!endpoint) {
        expect(
            chatMode,
            ChatSourceMode
                .localOnly); // EN: Missing endpoint must stay local. TH: ไม่มี endpoint ต้องตอบในเครื่อง
      }
      if (endpoint && !signedIn) {
        expect(
            chatMode,
            ChatSourceMode
                .signInRequired); // EN: Remote access must require sign-in. TH: ใช้ระยะไกลต้อง login
      }
      if (endpoint && signedIn && (!llm || mock)) {
        expect(
            chatMode,
            ChatSourceMode
                .localSelected); // EN: Disabled or demo AI must remain local. TH: ปิด AI หรือเป็น demo ต้องอยู่ในเครื่อง
      }
      if (endpoint && signedIn && llm && !mock && !consent) {
        expect(
            chatMode,
            ChatSourceMode
                .consentRequired); // EN: Missing consent must block remote AI. TH: ไม่มี consent ต้องบล็อก AI ระยะไกล
      }
      if (endpoint && signedIn && llm && !mock && consent) {
        expect(
            chatMode,
            ChatSourceMode
                .remoteAi); // EN: Remote AI requires every gate to pass. TH: AI ระยะไกลต้องผ่านเงื่อนไขทั้งหมด
      }

      final hasDozName = random
          .nextBool(); // EN: Vary advertised device names. TH: สลับชื่ออุปกรณ์ที่ประกาศ
      final hasService = random
          .nextBool(); // EN: Vary advertised service UUID presence. TH: สลับการประกาศ service UUID
      final match = BleService.matchesDozAdvertisement(
          platformName: hasDozName
              ? 'doz-${random.nextInt(9999)}'
              : 'sensor-${random.nextInt(9999)}',
          advertisedName: '',
          serviceUuids:
              hasService ? ['6B2F0001-4F2A-4C3E-9A1B-9D5E7C1A0001'] : const [],
          expectedServiceUuid: BleService
              .defaultServiceUuid); // EN: Test name and case-insensitive UUID matching. TH: ทดสอบการ match ชื่อและ UUID ที่ไม่สนตัวพิมพ์
      expect(match, hasDozName || hasService,
          reason:
              'BLE advertisement filtering failed in case $caseIndex'); // EN: Only supported Doz advertisements should pass. TH: ให้ผ่านเฉพาะ advertisement ของ Doz ที่รองรับ

      final red = random.nextInt(
          262144); // EN: Generate an in-range MAX30102 ADC value. TH: สร้างค่า ADC MAX30102 ในช่วงที่รับได้
      final ir = random.nextInt(
          262144); // EN: Generate an in-range infrared ADC value. TH: สร้างค่า ADC อินฟราเรดในช่วงที่รับได้
      final payload = utf8.encode(
          '{"type":"telemetry","v":1,"t":$caseIndex,"r":$red,"i":$ir,"a":[0,-8192,16384],"g":[131,-262,0],"pn":1,"in":1,"ai":false}'); // EN: Build a valid firmware-contract payload. TH: สร้าง payload ตามสัญญา firmware ที่ถูกต้อง
      final decoded = BleService.decodeTelemetryJsonPacket(
          payload); // EN: Decode the generated live packet. TH: ถอดรหัส packet live ที่สร้างขึ้น
      expect(decoded, isNotNull,
          reason:
              'Valid telemetry rejected in case $caseIndex'); // EN: Accept structurally valid telemetry. TH: ยอมรับ telemetry ที่โครงสร้างถูกต้อง
      expect(decoded!.sensorData.rawRed,
          red); // EN: Preserve the exact Red ADC count. TH: รักษาค่า ADC Red ให้ตรง
      expect(decoded.sensorData.rawIr,
          ir); // EN: Preserve the exact IR ADC count. TH: รักษาค่า ADC IR ให้ตรง
      expect(decoded.analysisAvailable,
          isFalse); // EN: Never invent an unavailable device inference. TH: ห้ามสร้างผลวิเคราะห์ที่ firmware ยังไม่มี
      decodedPackets++; // EN: Record this successful decoding case. TH: บันทึกกรณีถอดรหัสสำเร็จ

      final chunkSize = 10 +
          random.nextInt(
              5); // EN: Vary fragment payload within the firmware's 10–14 byte range. TH: สุ่ม payload ในช่วง 10–14 ไบต์ตามข้อจำกัด firmware
      final frames = _split(payload, caseIndex & 0xFFFF, chunkSize)
        ..shuffle(
            random); // EN: Reorder fragments to model BLE delivery variation. TH: สลับลำดับ fragment จำลองการส่ง BLE
      List<int>?
          rebuilt; // EN: Hold the reassembled packet. TH: เก็บ packet ที่ประกอบกลับ
      for (final frame in frames) {
        // EN: Feed each fragment into the production assembler. TH: ส่ง fragment เข้า assembler ที่แอปใช้จริง
        rebuilt = assembler.add(frame) ??
            rebuilt; // EN: Keep the complete result when the last part arrives. TH: เก็บผลเมื่อ fragment ครบ
      } // EN: Finish feeding this frame set. TH: จบการส่งเฟรมชุดนี้
      expect(rebuilt, payload,
          reason:
              'Fragment reassembly failed in case $caseIndex'); // EN: Ensure byte-exact reconstruction. TH: ยืนยันว่า byte ที่ประกอบกลับตรงทุกตัว
      assembledPackets++; // EN: Record this successful frame case. TH: บันทึกกรณีประกอบเฟรมสำเร็จ

      final bad = BleService.decodeTelemetryJsonPacket(utf8.encode(
          '{"type":"telemetry","v":99,"t":1}')); // EN: Make an unsupported-version packet. TH: สร้าง packet เวอร์ชันที่ไม่รองรับ
      expect(bad, isNull,
          reason:
              'Unsupported firmware version accepted in case $caseIndex'); // EN: Reject unsupported firmware versions. TH: ปฏิเสธ firmware version ที่ไม่รองรับ
      rejectedPackets++; // EN: Record this expected rejection. TH: บันทึกกรณีปฏิเสธตามคาด

      final confidence = random.nextInt(151) - 25;
      final spo2 = random.nextDouble() * 120;
      final stateClass = random.nextInt(6) - 1;
      final alertLevel = random.nextInt(7) - 2;
      final mapped = mapDeviceAlert(
          stateClass: stateClass,
          alertLevel: alertLevel,
          confidencePercent: confidence,
          spo2:
              spo2); // EN: Exercise out-of-range defensive mapping inputs. TH: ทดสอบ input map ที่เกินช่วง
      expect(['Safe', 'Watch', 'Warning', 'Emergency'],
          contains(mapped.alertLevel),
          reason:
              'Risk mapper returned an invalid level in case $caseIndex'); // EN: Keep displayed device levels within the supported set. TH: จำกัดระดับที่แสดงในชุดที่รองรับ
      final isValidInferenceInput = [0, 1, 2].contains(stateClass) &&
          [0, 1, 2, 3].contains(alertLevel) &&
          confidence >= 0 &&
          confidence <= 100;
      if (isValidInferenceInput) {
        expect(
          mapped.detectedSigns.join(' '),
          contains('ความมั่นใจ $confidence%'),
          reason: 'Valid confidence changed in case $caseIndex',
        );
      } else {
        expect(mapped.alertLevel, 'Warning',
            reason: 'Invalid device input was not rejected in case $caseIndex');
        expect(mapped.riskClass, 'ผลจากอุปกรณ์ไม่ถูกต้อง',
            reason:
                'Invalid input was presented as a real class in case $caseIndex');
        expect(mapped.recommendation, contains('อย่าใช้ผลนี้ยืนยันว่าปลอดภัย'),
            reason:
                'Invalid input lacked a fail-closed instruction in case $caseIndex');
      }
      expect(
        mapped.detectedSigns.join(' ').contains('SpO2 ='),
        spo2 > 0 && spo2 <= 100,
        reason: 'Invalid SpO2 leaked into the UI in case $caseIndex',
      );
      if (![0, 1, 2].contains(stateClass)) {
        final unknownClass = mapDeviceAlert(
          stateClass: stateClass,
          alertLevel: random.nextInt(7) - 2,
          confidencePercent: confidence,
          spo2: spo2,
        );
        expect(unknownClass.alertLevel, 'Warning',
            reason: 'Unknown class was presented as safe in case $caseIndex');
        expect(unknownClass.riskClass, isNot('ปกติ'),
            reason: 'Unknown class fell back to Normal in case $caseIndex');
        expect(unknownClass.recommendation,
            contains('อย่าใช้ผลนี้ยืนยันว่าปลอดภัย'),
            reason:
                'Unknown class lacked a fail-closed instruction in case $caseIndex');
      }
    } // EN: Finish all generated scenarios. TH: จบสถานการณ์ที่สร้างทั้งหมด

    expect(decodedPackets,
        10000); // EN: Confirm every generated telemetry packet decoded. TH: ยืนยันว่าถอดรหัส telemetry ครบ
    expect(assembledPackets,
        10000); // EN: Confirm every BLE payload reassembled exactly. TH: ยืนยันว่าประกอบ BLE ครบและตรง
    expect(rejectedPackets,
        10000); // EN: Confirm all unsupported versions were rejected. TH: ยืนยันว่าปฏิเสธเวอร์ชันที่ไม่รองรับครบ
  }); // EN: Finish the 10,000-case stress test. TH: จบ stress test 10,000 กรณี
} // EN: Finish test registration. TH: จบการลงทะเบียนเทสต์
