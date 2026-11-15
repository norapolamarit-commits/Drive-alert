import 'package:doz/services/device_risk_mapper.dart'; // EN: Test the device enum safety boundary. TH: ทดสอบขอบเขตความปลอดภัยของ enum จากอุปกรณ์
import 'package:flutter_test/flutter_test.dart'; // EN: Use Flutter's test matchers. TH: ใช้ matcher ของ Flutter test

void main() {
  // EN: Register fail-closed protocol validation tests. TH: ลงทะเบียนการทดสอบ validation แบบ fail-closed
  group('mapDeviceAlert input validation', () {
    // EN: Reject a negative level instead of clamping it to Safe. TH: ปฏิเสธระดับติดลบแทนการ clamp ให้เป็น Safe
    test('rejects a negative alert level', () {
      final result = mapDeviceAlert(
        stateClass: dozClassNormal,
        alertLevel: -1,
        confidencePercent: 80,
        spo2: 98,
      );
      expect(result.alertLevel, 'Warning');
      expect(result.riskClass, 'ผลจากอุปกรณ์ไม่ถูกต้อง');
      expect(result.detectedSigns.join(' '), contains('alert level ไม่รู้จัก'));
    });

    // EN: Reject a high unknown level instead of converting it to Emergency. TH: ปฏิเสธระดับที่สูงเกินแทนการแปลงเป็น Emergency
    test('rejects an alert level above the defined enum', () {
      final result = mapDeviceAlert(
        stateClass: dozClassNormal,
        alertLevel: 4,
        confidencePercent: 80,
        spo2: 98,
      );
      expect(result.alertLevel, 'Warning');
      expect(result.detectedSigns.join(' '), contains('alert level ไม่รู้จัก'));
    });

    // EN: Reject confidence outside percent units rather than presenting a clamped value. TH: ปฏิเสธ confidence ที่อยู่นอกหน่วยเปอร์เซ็นต์แทนการแสดงค่าที่ clamp
    test('rejects confidence outside 0 to 100', () {
      final result = mapDeviceAlert(
        stateClass: dozClassNormal,
        alertLevel: dozAlertSafe,
        confidencePercent: 101,
        spo2: 98,
      );
      expect(result.alertLevel, 'Warning');
      expect(result.detectedSigns.join(' '),
          contains('ไม่มีค่าความมั่นใจที่ใช้ได้'));
      expect(result.detectedSigns.join(' '), isNot(contains('ความมั่นใจ 0%')));
    });

    // EN: Preserve a recognized inference packet. TH: คงการแปลง packet ที่มีค่าถูกต้อง
    test('maps a valid class and alert level', () {
      final result = mapDeviceAlert(
        stateClass: dozClassDrowsiness,
        alertLevel: dozAlertWarning,
        confidencePercent: 87,
        spo2: 97,
      );
      expect(result.alertLevel, 'Warning');
      expect(result.detectedSigns.join(' '), contains('ความมั่นใจ 87%'));
    });
  });
}
