import '../models/risk_result.dart';
import '../models/sensor_data.dart';

class RiskAnalyzer {
  RiskResult analyze(SensorData current, List<SensorData> history) {
    final recent = [...history.takeLast(12), current];
    final hrTrend =
        _trend(recent.map((item) => item.heartRate.toDouble()).toList());
    final spo2Trend =
        _trend(recent.map((item) => item.spo2.toDouble()).toList());
    final stressTrend = _trend(recent.map((item) => item.gsr).toList());
    final lowMovement = current.motionMagnitude < 0.35;
    final highGyro = current.gyroMagnitude > 2.2;
    final unstableGyro = current.gyroMagnitude > 1.25;

    if (current.heartRate > 140 || current.heartRate < 40) {
      return const RiskResult(
        riskClass: 'Cardiac Risk',
        alertLevel: 'Emergency',
        detectedSigns: [
          'Heart Rate อยู่นอกช่วงปลอดภัย',
          'ต้องเฝ้าระวังทันที',
        ],
        recommendation:
            'หยุดกิจกรรม นั่งพักในที่ปลอดภัย และติดต่อผู้ดูแลหากอาการไม่ดีขึ้น',
      );
    }

    if (current.spo2 < 90) {
      return const RiskResult(
        riskClass: 'Low SpO2 Risk',
        alertLevel: 'Emergency',
        detectedSigns: [
          'SpO2 ต่ำกว่า 90%',
          'มีสัญญาณที่ควรได้รับการช่วยเหลือ',
        ],
        recommendation:
            'หยุดกิจกรรม หายใจช้า ๆ ในที่อากาศถ่ายเท และติดต่อผู้ดูแลหากยังผิดปกติ',
      );
    }

    if (_fallPattern(recent)) {
      return const RiskResult(
        riskClass: 'Fall Risk',
        alertLevel: 'Emergency',
        detectedSigns: [
          'พบแรงเร่งสูง',
          'หลังจากนั้นมีการเคลื่อนไหวน้อยมาก',
        ],
        recommendation:
            'อย่ารีบลุก ตรวจสอบความปลอดภัยรอบตัว และติดต่อบุคคลฉุกเฉินหากต้องการความช่วยเหลือ',
      );
    }

    if (highGyro && _repetitiveMovement(recent)) {
      return const RiskResult(
        riskClass: 'Seizure-like Risk',
        alertLevel: 'Emergency',
        detectedSigns: [
          'Gyroscope แกว่งสูง',
          'พบรูปแบบการเคลื่อนไหวซ้ำผิดปกติ',
        ],
        recommendation:
            'หยุดกิจกรรมทันที อยู่ในพื้นที่ปลอดภัย และให้ผู้ดูแลตรวจสอบสถานการณ์',
      );
    }

    if (unstableGyro && current.motionMagnitude > 1.15 && current.gsr > 70) {
      return const RiskResult(
        riskClass: 'Alcohol-like Impairment Risk',
        alertLevel: 'Warning',
        detectedSigns: [
          'การเคลื่อนไหวไม่สม่ำเสมอ',
          'Gyroscope ไม่คงที่',
          'HR/GSR มีรูปแบบผิดปกติ',
        ],
        recommendation:
            'หยุดพักในจุดปลอดภัย หลีกเลี่ยงการขับขี่หรือกิจกรรมที่ต้องใช้สมาธิ',
      );
    }

    if (current.gsr > 80 && current.heartRate > 105) {
      return const RiskResult(
        riskClass: 'Fatigue Risk',
        alertLevel: 'Warning',
        detectedSigns: [
          'GSR สูง',
          'Heart Rate สูงกว่าปกติ',
        ],
        recommendation:
            'พักหายใจช้า ๆ 3-5 นาที ลดสิ่งกระตุ้น และติดตามค่าซ้ำอีกครั้ง',
      );
    }

    if (lowMovement && hrTrend < -1.4 && stressTrend < -1.0) {
      return const RiskResult(
        riskClass: 'Drowsiness Risk',
        alertLevel: 'Warning',
        detectedSigns: [
          'Low movement',
          'Decreasing heart rate',
          'Reduced alertness pattern',
        ],
        recommendation:
            'พักผ่อนอย่างน้อย 15-20 นาที ก่อนทำกิจกรรมที่ต้องใช้สมาธิ',
      );
    }

    if (current.heartRate > 110 &&
        stressTrend > 1.2 &&
        current.motionMagnitude < 0.7) {
      return const RiskResult(
        riskClass: 'Fatigue Risk',
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

    if (current.spo2TrendHint(spo2Trend) && current.spo2 < 95) {
      return const RiskResult(
        riskClass: 'Low SpO2 Risk',
        alertLevel: 'Watch',
        detectedSigns: [
          'SpO2 มีแนวโน้มลดลง',
          'ค่าปัจจุบันต่ำกว่าช่วงที่ควรเฝ้าระวัง',
        ],
        recommendation:
            'พักในที่อากาศถ่ายเท วัดซ้ำ และขอความช่วยเหลือหากมีอาการผิดปกติ',
      );
    }

    return const RiskResult(
      riskClass: 'Normal',
      alertLevel: 'Safe',
      detectedSigns: [
        'Heart Rate อยู่ในช่วง 60-100',
        'SpO2 มากกว่า 95%',
        'Motion และ Gyroscope อยู่ในรูปแบบปกติ',
      ],
      recommendation: 'ค่าปัจจุบันอยู่ในช่วงปลอดภัย ติดตามต่อเนื่องตามปกติ',
    );
  }

  double _trend(List<double> values) {
    if (values.length < 3) return 0;
    final midpoint = values.length ~/ 2;
    final first = values.take(midpoint).average();
    final second = values.skip(midpoint).average();
    return second - first;
  }

  bool _fallPattern(List<SensorData> recent) {
    final spikeIndex =
        recent.lastIndexWhere((item) => item.motionMagnitude > 2.5);
    if (spikeIndex == -1 || spikeIndex == recent.length - 1) return false;
    return recent
        .skip(spikeIndex + 1)
        .any((item) => item.motionMagnitude < 0.25);
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

extension _Spo2TrendHint on SensorData {
  bool spo2TrendHint(double trend) => trend < -0.8;
}
