import 'dart:math'; // EN: Provide random demo variation and waveform helpers. TH: ใช้สุ่มค่าตัวอย่างและคำนวณรูปคลื่น

import '../models/sensor_data.dart'; // EN: Reuse the app's sensor data shape for preview only. TH: ใช้รูปแบบ SensorData ของแอปสำหรับ preview เท่านั้น

/// Generates synthetic preview values; never represents measurements or training data.
/// / สร้างค่าจำลองสำหรับ preview เท่านั้น ไม่ใช่ค่าที่วัดจริงหรือข้อมูลฝึก
class MockDataService {
  // EN: Keep mock generation isolated from hardware acquisition. TH: แยกการสร้าง mock ออกจากการอ่านฮาร์ดแวร์
  final Random _random =
      Random(); // EN: Add non-deterministic variation to demo values. TH: เพิ่มความแปรผันแบบสุ่มให้ค่าตัวอย่าง
  int _tick =
      0; // EN: Track demo steps for scenario timing. TH: นับรอบเพื่อกำหนดเวลาสลับสถานการณ์

  static const scenarios = [
    // EN: List labels accepted by this preview generator. TH: รายชื่อสถานการณ์ที่ตัวสร้าง preview ยอมรับ
    'Normal', // EN: Ordinary demo baseline. TH: ค่าพื้นฐานตัวอย่าง
    'Drowsiness Risk', // EN: Drowsiness-themed demo only. TH: ตัวอย่างธีมความง่วงเท่านั้น
    'Fatigue Risk', // EN: Fatigue-themed demo only. TH: ตัวอย่างธีมความอ่อนล้าเท่านั้น
    'Seizure-like Risk', // EN: Visual demo label, not a medical detector. TH: ป้ายตัวอย่าง UI ไม่ใช่ตัวตรวจทางการแพทย์
    'High Stress Alert', // EN: Stress-themed demo only. TH: ตัวอย่างธีมความเครียดเท่านั้น
    'Immobilization Alert', // EN: Immobilization-themed demo only. TH: ตัวอย่างธีมหยุดนิ่งเท่านั้น
  ];

  SensorData nextAuto() {
    // EN: Select the next scripted preview scenario. TH: เลือกสถานการณ์ preview ตามรอบ
    // หมุนเวียนผ่านทุกสถานการณ์ที่เหลือ คั่นด้วยช่วง Normal
    final profile = _tick %
        40; // EN: Repeat the scripted sequence every forty calls. TH: วนลำดับตัวอย่างทุกสี่สิบรอบ
    if (profile >= 6 && profile <= 9) {
      // EN: Select the drowsiness preview window. TH: เลือกช่วง preview ความง่วง
      return next(
          'Drowsiness Risk'); // EN: Preview four drowsiness steps. TH: แสดงตัวอย่างง่วงสี่รอบ
    }
    if (profile >= 13 && profile <= 16) {
      // EN: Select the fatigue preview window. TH: เลือกช่วง preview ความอ่อนล้า
      return next(
          'Fatigue Risk'); // EN: Preview four fatigue steps. TH: แสดงตัวอย่างอ่อนล้าสี่รอบ
    }
    if (profile >= 22 && profile <= 24) {
      // EN: Select the stress preview window. TH: เลือกช่วง preview ความเครียด
      return next(
          'High Stress Alert'); // EN: Preview three stress steps. TH: แสดงตัวอย่างเครียดสามรอบ
    }
    if (profile >= 30 && profile <= 32) {
      // EN: Select the seizure-like UI preview window. TH: เลือกช่วง preview UI คล้าย seizure
      return next(
          'Seizure-like Risk'); // EN: Preview three seizure-like UI steps only. TH: แสดงตัวอย่างหน้าจอคล้าย seizure สามรอบเท่านั้น
    }
    if (profile == 38) {
      // EN: Select the one-step immobilization preview. TH: เลือก preview หยุดนิ่งหนึ่งรอบ
      return next(
          'Immobilization Alert'); // EN: Preview one immobilization step. TH: แสดงตัวอย่างหยุดนิ่งหนึ่งรอบ
    }
    return next(
        'Normal'); // EN: Use the ordinary demo scenario outside risk-themed windows. TH: ใช้สถานการณ์ปกติตัวอย่างนอกช่วงเสี่ยง
  }

  SensorData next(String scenario) {
    // EN: Generate one preview sample for an explicitly supported scenario. TH: สร้างตัวอย่างหนึ่งชุดตามสถานการณ์ที่รองรับ
    if (!scenarios.contains(scenario)) {
      // EN: Reject unknown labels instead of silently returning Normal. TH: ปฏิเสธ label ที่ไม่รู้จักแทนการแอบคืนค่า Normal
      throw ArgumentError.value(scenario, 'scenario',
          'Unsupported demo scenario.'); // EN: Identify the invalid argument without implying sensor failure. TH: แจ้ง argument ที่ไม่รองรับโดยไม่ทำให้เข้าใจว่า sensor เสีย
    }
    _tick++; // EN: Advance the demo time only after validating the scenario. TH: เพิ่มรอบหลังตรวจสถานการณ์ผ่านแล้ว
    final wave = sin(_tick /
        3); // EN: Create a smooth synthetic oscillation for visuals. TH: สร้างการแกว่งสังเคราะห์แบบเรียบเพื่อแสดงผล
    final jitter = (_random.nextDouble() - 0.5) *
        0.08; // EN: Add small random demo variation. TH: เพิ่มความแปรผันสุ่มเล็กน้อยในตัวอย่าง

    switch (scenario) {
      // EN: Choose synthetic values for the requested preview label. TH: เลือกค่าจำลองตามป้าย preview
      case 'Drowsiness Risk':
        return _base(
          heartRate: max(
              48,
              78 -
                  _tick %
                      18), // EN: Generate a bounded illustrative heart rate. TH: สร้างชีพจรตัวอย่างที่มีขอบเขต
          spo2:
              96, // EN: Use a fixed illustrative oxygen value. TH: ใช้ค่าออกซิเจนตัวอย่างคงที่
          gsr: max(18, 45 - _tick % 20)
              .toDouble(), // EN: Generate illustrative skin conductance. TH: สร้างค่าการนำไฟฟ้าผิวตัวอย่าง
          motion: 0.18 +
              jitter, // EN: Simulate low movement. TH: จำลองการเคลื่อนไหวต่ำ
          gyro: 0.05, // EN: Simulate low angular motion. TH: จำลองการหมุนต่ำ
        );
      case 'Fatigue Risk':
        return _base(
          heartRate: 112 +
              (_random.nextInt(
                  8)), // EN: Generate a varied demo pulse. TH: สร้างชีพจรตัวอย่างแบบแปรผัน
          spo2:
              95, // EN: Use an illustrative fixed value. TH: ใช้ค่าตัวอย่างคงที่
          gsr: 74 +
              _random.nextDouble() *
                  12, // EN: Add demo conductance variation. TH: เพิ่มความแปรผันการนำไฟฟ้าผิวตัวอย่าง
          motion: 0.45 +
              jitter, // EN: Simulate moderate movement. TH: จำลองการเคลื่อนไหวปานกลาง
          gyro:
              0.35, // EN: Simulate moderate angular movement. TH: จำลองการหมุนปานกลาง
        );
      case 'Seizure-like Risk':
        return _base(
          heartRate:
              118, // EN: Use an illustrative pulse value only. TH: ใช้ค่าชีพจรตัวอย่างเท่านั้น
          spo2:
              94, // EN: Use an illustrative oxygen value only. TH: ใช้ค่าออกซิเจนตัวอย่างเท่านั้น
          gsr:
              78, // EN: Use an illustrative conductance value only. TH: ใช้ค่าการนำไฟฟ้าผิวตัวอย่างเท่านั้น
          motion: 1.3 +
              wave.abs(), // EN: Simulate oscillating movement for the UI. TH: จำลองการเคลื่อนไหวแกว่งเพื่อแสดงผล
          gyro: 2.4 +
              wave.abs(), // EN: Simulate oscillating angular movement. TH: จำลองการหมุนแกว่ง
        );
      case 'High Stress Alert':
        return _base(
          heartRate:
              112, // EN: Use a demo heart-rate value. TH: ใช้ค่าชีพจรตัวอย่าง
          spo2: 96, // EN: Use a demo oxygen value. TH: ใช้ค่าออกซิเจนตัวอย่าง
          gsr:
              88, // EN: Use a demo conductance value. TH: ใช้ค่าการนำไฟฟ้าผิวตัวอย่าง
          motion:
              0.6, // EN: Simulate moderate movement. TH: จำลองการเคลื่อนไหวปานกลาง
          gyro: 0.25, // EN: Simulate low angular movement. TH: จำลองการหมุนต่ำ
        );
      case 'Immobilization Alert':
        return _base(
          heartRate:
              76, // EN: Use a demo heart-rate value. TH: ใช้ค่าชีพจรตัวอย่าง
          spo2: 97, // EN: Use a demo oxygen value. TH: ใช้ค่าออกซิเจนตัวอย่าง
          gsr:
              44, // EN: Use a demo conductance value. TH: ใช้ค่าการนำไฟฟ้าผิวตัวอย่าง
          motion:
              0.08, // EN: Simulate near-still movement. TH: จำลองการเคลื่อนไหวเกือบหยุดนิ่ง
          gyro:
              0.02, // EN: Simulate near-zero rotation. TH: จำลองการหมุนเกือบศูนย์
        );
      case 'Normal': // EN: Generate the ordinary demo scenario. TH: สร้างสถานการณ์ปกติตัวอย่าง
        return _base(
          heartRate: 74 +
              _random.nextInt(
                  12), // EN: Generate a demo pulse in a narrow range. TH: สร้างชีพจรตัวอย่างในช่วงแคบ
          spo2: 96 +
              _random.nextInt(
                  3), // EN: Generate an illustrative oxygen percentage. TH: สร้างเปอร์เซ็นต์ออกซิเจนตัวอย่าง
          gsr: 42 +
              _random.nextDouble() *
                  12, // EN: Generate illustrative conductance variation. TH: สร้างความแปรผันการนำไฟฟ้าผิวตัวอย่าง
          motion: 0.85 +
              jitter, // EN: Simulate ordinary movement. TH: จำลองการเคลื่อนไหวทั่วไป
          gyro: 0.18 +
              jitter
                  .abs(), // EN: Simulate small angular variation. TH: จำลองความแปรผันการหมุนเล็กน้อย
        );
      default: // EN: Guard against future labels missing an implementation. TH: ป้องกัน label ใหม่ที่ยังไม่มี implementation
        throw StateError(
            'Demo scenario passed validation but has no generator.'); // EN: Fail visibly instead of fabricating a Normal sample. TH: แจ้งชัดแทนการสร้างตัวอย่าง Normal ปลอม
    }
  }

  SensorData _base({
    required int heartRate,
    required int spo2,
    required double gsr,
    required double motion,
    required double gyro,
  }) {
    // EN: Convert scenario parameters into the app's SensorData shape. TH: แปลงพารามิเตอร์สถานการณ์เป็นรูปแบบ SensorData
    return SensorData(
      // EN: Construct one synthetic reading for UI preview. TH: สร้างค่าจำลองหนึ่งชุดสำหรับ preview UI
      heartRate:
          heartRate, // EN: Store the generated pulse value. TH: เก็บค่าชีพจรตัวอย่าง
      spo2:
          spo2, // EN: Store the generated oxygen value. TH: เก็บค่าออกซิเจนตัวอย่าง
      gsr:
          gsr, // EN: Store the generated conductance value. TH: เก็บค่าการนำไฟฟ้าผิวตัวอย่าง
      temperature: 36.3 +
          _random.nextDouble() *
              0.8, // EN: Generate a demo temperature; it is not a skin measurement. TH: สร้างอุณหภูมิตัวอย่าง ไม่ใช่ค่าผิวที่วัดจริง
      accelX: motion /
          3, // EN: Spread demo motion across the X axis. TH: กระจายการเคลื่อนไหวตัวอย่างไปแกน X
      accelY: motion /
          4, // EN: Spread demo motion across the Y axis. TH: กระจายการเคลื่อนไหวตัวอย่างไปแกน Y
      accelZ: max(0.02,
          motion), // EN: Keep a small illustrative Z-axis floor. TH: กำหนดค่าต่ำสุดตัวอย่างของแกน Z
      gyroX: gyro /
          2, // EN: Spread demo angular motion across X. TH: กระจายการหมุนตัวอย่างไปแกน X
      gyroY: gyro /
          3, // EN: Spread demo angular motion across Y. TH: กระจายการหมุนตัวอย่างไปแกน Y
      gyroZ: gyro /
          4, // EN: Spread demo angular motion across Z. TH: กระจายการหมุนตัวอย่างไปแกน Z
    );
  }
}
