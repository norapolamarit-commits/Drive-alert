import '../models/risk_result.dart';
import '../models/sensor_data.dart';

class RiskAnalyzer {
  // ── เกณฑ์สำหรับตรวจจับหลับใน (drowsiness) ──────────────────────────────────
  static const double _drivingMinKmh = 20; // ต่ำกว่านี้ถือว่าไม่ได้ขับรถ
  static const double _hrvDropTrend = -0.5; // HRV (RMSSD) ลดลงต่อเนื่อง
  static const double _hrvLowMs = 25; // HRV ต่ำเชิงสัมบูรณ์ = ล้าสะสม
  static const double _hrDropTrend = -1.0; // HR ค่อยๆ ลด = เริ่มง่วง
  static const double _calmMotion = 0.5; // การเคลื่อนไหวน้อย (นิ่ง)

  /// [speedKmh] ความเร็วจาก GPS (ถ้ามี) — ใช้ตรวจเฉพาะตอนขับรถ; null = ตรวจตลอด
  RiskResult analyze(
    SensorData current,
    List<SensorData> history, {
    double? speedKmh,
  }) {
    // Safety guard: SpO2 ต่ำวิกฤต — แจ้งฉุกเฉินเสมอ (ป้ายแบบรวม ไม่ใช่ risk class แยก)
    // เงื่อนไข > 0 กันกรณีเซนเซอร์ยังไม่มีค่า (อ่านได้ 0)
    if (current.spo2 > 0 && current.spo2 < 90) {
      return const RiskResult(
        riskClass: 'ออกซิเจนในเลือดต่ำ ควรหยุดทันที',
        alertLevel: 'Emergency',
        detectedSigns: [
          'ค่าออกซิเจนในเลือดต่ำวิกฤต (SpO2 < 90%)',
        ],
        recommendation:
            'หยุดกิจกรรมทันที หายใจช้า ๆ ในที่อากาศถ่ายเท หากไม่ดีขึ้นใน 2 นาที โทร 1669',
      );
    }

    final recent = [...history.takeLast(12), current];
    final hrTrend =
        _trend(recent.map((item) => item.heartRate.toDouble()).toList());
    final hrvTrend = _trend(recent.map((item) => item.ecgHrv).toList());
    final stressTrend = _trend(recent.map((item) => item.gsr).toList());
    final highGyro = current.gyroMagnitude > 2.2;

    if (highGyro && _repetitiveMovement(recent)) {
      return const RiskResult(
        riskClass: 'พบการเคลื่อนไหวผิดปกติ ควรหยุดทันที',
        alertLevel: 'Emergency',
        detectedSigns: [
          'Gyroscope แกว่งสูง',
          'พบรูปแบบการเคลื่อนไหวซ้ำผิดปกติ',
        ],
        recommendation:
            'หยุดกิจกรรมทันที อยู่ในพื้นที่ปลอดภัย และให้ผู้ดูแลตรวจสอบสถานการณ์',
      );
    }

    if (current.gsr > 80 && current.heartRate > 105) {
      return const RiskResult(
        riskClass: 'ควรพัก (ร่างกายอ่อนล้า/เครียด)',
        alertLevel: 'Warning',
        detectedSigns: [
          'GSR สูง',
          'Heart Rate สูงกว่าปกติ',
        ],
        recommendation:
            'พักหายใจช้า ๆ 3-5 นาที ลดสิ่งกระตุ้น และติดตามค่าซ้ำอีกครั้ง',
      );
    }

    final drowsiness = _assessDrowsiness(
      current: current,
      recent: recent,
      hrTrend: hrTrend,
      hrvTrend: hrvTrend,
      speedKmh: speedKmh,
    );
    if (drowsiness != null) return drowsiness;

    if (current.heartRate > 110 &&
        stressTrend > 1.2 &&
        current.motionMagnitude < 0.7) {
      return const RiskResult(
        riskClass: 'เริ่มอ่อนล้า ควรระวัง',
        alertLevel: 'Watch',
        detectedSigns: [
          'Heart Rate มีแนวโน้มผิดปกติ',
          'Stress Level สูงขึ้น',
          'การเคลื่อนไหวลดความสม่ำเสมอ',
        ],
        recommendation:
            'ลดความเร็วของกิจกรรม ดื่มน้ำ และพักสั้น ๆ เพื่อประเมินความพร้อม',
      );
    }

    return const RiskResult(
      riskClass: 'ปกติ',
      alertLevel: 'Safe',
      detectedSigns: [
        'Heart Rate อยู่ในช่วง 60-100',
        'SpO2 มากกว่า 95%',
        'Motion และ Gyroscope อยู่ในรูปแบบปกติ',
      ],
      recommendation: 'ค่าปัจจุบันอยู่ในช่วงปลอดภัย ติดตามต่อเนื่องตามปกติ',
    );
  }

  /// ตรวจจับหลับใน: รวม HRV + แนวโน้ม + ต้องเกิดต่อเนื่อง + เฉพาะตอนขับรถ
  RiskResult? _assessDrowsiness({
    required SensorData current,
    required List<SensorData> recent,
    required double hrTrend,
    required double hrvTrend,
    double? speedKmh,
  }) {
    // 1) Driving gate — ถ้ามีข้อมูลความเร็วและไม่ได้ขับรถ ไม่ต้องเตือน
    if (speedKmh != null && speedKmh < _drivingMinKmh) return null;

    // 2) Sustained — นับ reading ล่าสุดที่ "นิ่ง" ติดต่อกัน (กัน false alarm ชั่ววูบ)
    final calmStreak =
        _trailingCount(recent, (s) => s.motionMagnitude < _calmMotion);

    // 3) สัญญาณสรีรวิทยา (เน้น HRV เป็นตัวหลัก)
    final hrvDeclining = hrvTrend < _hrvDropTrend;
    final hrvLow = current.ecgHrv > 0 && current.ecgHrv < _hrvLowMs;
    final hrDeclining = hrTrend < _hrDropTrend;
    final signals =
        (hrvDeclining || hrvLow ? 1 : 0) + (hrDeclining ? 1 : 0);

    // 4) Circadian — ช่วง 0-6 น. และ 13-16 น. เสี่ยงสูง ลดจำนวนที่ต้องยืนยัน
    final needSustain = _highDrowsyHour(current.timestamp) ? 2 : 3;

    if (calmStreak < needSustain || signals == 0) return null;

    // ความรุนแรง: HRV ต่ำ+ลดต่อเนื่อง หรือ HRV+HR ลดพร้อมกัน = อันตรายชัดเจน
    final severe = (hrvLow && hrvDeclining) || (hrvDeclining && hrDeclining);

    final signs = <String>[
      'การเคลื่อนไหวน้อยต่อเนื่อง $calmStreak ช่วง',
      if (hrvDeclining) 'HRV ลดลงต่อเนื่อง (สัญญาณเหนื่อยล้า)',
      if (hrvLow) 'HRV ต่ำกว่าเกณฑ์ (${current.ecgHrv.toStringAsFixed(0)} ms)',
      if (hrDeclining) 'อัตราการเต้นหัวใจค่อยๆ ลดลง',
      if (_highDrowsyHour(current.timestamp)) 'อยู่ในช่วงเวลาที่เสี่ยงง่วงสูง',
    ];

    return RiskResult(
      riskClass: severe ? 'เสี่ยงหลับใน ควรพักทันที' : 'เริ่มง่วง ควรพัก',
      alertLevel: severe ? 'Warning' : 'Watch',
      detectedSigns: signs,
      recommendation: severe
          ? 'พบสัญญาณหลับในชัดเจน จอดในจุดปลอดภัยทันที งีบ 15-20 นาที '
              'ดื่มกาแฟแล้วรอ 20 นาทีก่อนขับต่อ'
          : 'เริ่มมีสัญญาณง่วง วางแผนหยุดพักใน 15 นาที ดื่มน้ำ และเพิ่มความระมัดระวัง',
    );
  }

  /// นับจำนวน element ท้ายสุดที่ผ่านเงื่อนไขแบบติดต่อกัน
  int _trailingCount(List<SensorData> recent, bool Function(SensorData) test) {
    var count = 0;
    for (final s in recent.reversed) {
      if (test(s)) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  /// ช่วงเวลาที่ร่างกายเสี่ยงง่วงสูงตามนาฬิกาชีวภาพ
  bool _highDrowsyHour(DateTime t) {
    final h = t.hour;
    return (h >= 0 && h < 6) || (h >= 13 && h < 16);
  }

  double _trend(List<double> values) {
    if (values.length < 3) return 0;
    final midpoint = values.length ~/ 2;
    final first = values.take(midpoint).average();
    final second = values.skip(midpoint).average();
    return second - first;
  }

  bool _repetitiveMovement(List<SensorData> recent) {
    if (recent.length < 5) return false;
    final highCount = recent.where((item) => item.gyroMagnitude > 1.5).length;
    return highCount >= 4;
  }
}

extension _ListStats on Iterable<double> {
  double average() {
    if (isEmpty) return 0;
    return reduce((a, b) => a + b) / length;
  }
}

extension _TakeLast<T> on List<T> {
  List<T> takeLast(int count) =>
      skip(length > count ? length - count : 0).toList();
}
