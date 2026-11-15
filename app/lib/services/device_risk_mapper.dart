import '../models/risk_result.dart';

/// EN: Legacy 15-byte BLE compatibility map only; the active v1 JSON firmware sends ai=false.
/// TH: ตารางแปลงนี้รองรับ BLE binary รุ่นเก่าเท่านั้น; firmware JSON v1 ปัจจุบันส่ง ai=false
/// EN: Keep these IDs aligned with the legacy firmware packet; do not use them for the 2-class
///     wearable trainer until a versioned inference protocol is implemented and tested.
/// TH: คง ID ให้ตรงกับ packet firmware รุ่นเก่า; ห้ามใช้กับ trainer สองคลาสจนกว่าจะมี
///     inference protocol ที่ระบุ version และผ่าน integration test
const int dozClassNormal =
    0; // EN: Legacy ID for normal. TH: ID legacy ของคลาสปกติ
const int dozClassDrowsiness =
    1; // EN: Legacy ID for drowsiness. TH: ID legacy ของคลาสง่วง
const int dozClassHighStress =
    2; // EN: Legacy ID for high stress. TH: ID legacy ของความเครียดสูง

const int dozAlertSafe = 0; // EN: Legacy ID for Safe. TH: ID legacy ของ Safe
const int dozAlertWatch = 1; // EN: Legacy ID for Watch. TH: ID legacy ของ Watch
const int dozAlertWarning =
    2; // EN: Legacy ID for Warning. TH: ID legacy ของ Warning
const int dozAlertEmergency =
    3; // EN: Legacy ID for Emergency. TH: ID legacy ของ Emergency

/// EN: Translate a supported legacy device inference packet into user-facing text.
/// TH: แปลงผล inference จาก packet อุปกรณ์รุ่นเก่าเป็นข้อความที่ผู้ใช้อ่านได้
/// EN: Current raw-stream firmware does not call this map and does not claim AI output.
/// TH: firmware raw-stream ปัจจุบันไม่เรียก mapper นี้และไม่อ้างว่ามีผล AI
RiskResult mapDeviceAlert({
  required int stateClass,
  required int alertLevel,
  required int confidencePercent,
  required double spo2,
}) {
  // EN: Validate protocol enums and confidence instead of clamping corruption into a real state.
  // TH: ตรวจ enum และความมั่นใจ แทนการ clamp ค่าที่เสียให้กลายเป็นสถานะจริง
  final validConfidence = confidencePercent >= 0 &&
      confidencePercent <=
          100; // EN: Accept confidence only as a percentage. TH: รับ confidence เฉพาะช่วงเปอร์เซ็นต์
  final safeConfidence = validConfidence
      ? confidencePercent
      : 0; // EN: Keep invalid values from appearing as confidence. TH: กันค่าผิดไม่ให้แสดงเป็น confidence
  final validSpo2 = spo2.isFinite &&
      spo2 > 0 &&
      spo2 <=
          100; // EN: Accept only finite SpO2 percentages. TH: รับเฉพาะ SpO2 เปอร์เซ็นต์ที่เป็น finite

  // EN: Reject unknown IDs and malformed confidence as an unavailable warning, never as Safe.
  // TH: ปฏิเสธ ID ที่ไม่รู้จักหรือ confidence ผิดช่วงเป็น Warning ที่ใช้วิเคราะห์ไม่ได้ ไม่ใช่ Safe
  if (!_isKnownClass(stateClass) ||
      !_isKnownAlertLevel(alertLevel) ||
      !validConfidence) {
    // EN: Collect reasons for rejecting this legacy device result.
    // TH: รวมสาเหตุที่ต้องปฏิเสธผลจากอุปกรณ์รุ่นเก่านี้
    final reasons = <String>[
      if (!_isKnownClass(stateClass))
        'class ID ไม่รู้จัก ($stateClass)', // EN: Explain an unknown class ID. TH: ระบุสาเหตุเมื่อ class ID ไม่รู้จัก
      if (!_isKnownAlertLevel(alertLevel))
        'alert level ไม่รู้จัก ($alertLevel)', // EN: Explain an unsupported alert ID. TH: ระบุสาเหตุเมื่อ alert ID ไม่รองรับ
      if (!validConfidence)
        'confidence อยู่นอกช่วง 0–100 ($confidencePercent)', // EN: Include the invalid range condition. TH: แจ้งว่า confidence อยู่นอกช่วงที่รับได้
    ];
    return RiskResult(
      riskClass:
          'ผลจากอุปกรณ์ไม่ถูกต้อง', // EN: Mark the result as invalid. TH: ทำเครื่องหมายว่าผลไม่ถูกต้อง
      alertLevel:
          'Warning', // EN: Avoid labeling rejected data as Safe. TH: ไม่ติดป้ายข้อมูลที่ปฏิเสธว่า Safe
      detectedSigns: [
        'งดใช้ผลนี้ประเมินความเสี่ยง: ${reasons.join('; ')}', // EN: Expose why the device result was rejected. TH: แสดงเหตุผลที่ปฏิเสธผลจากอุปกรณ์
        if (validConfidence)
          'ความมั่นใจ $safeConfidence%' // EN: Show confidence only when valid. TH: แสดง confidence เมื่อผ่านการตรวจเท่านั้น
        else
          'ไม่มีค่าความมั่นใจที่ใช้ได้', // EN: State that confidence cannot be used. TH: ระบุว่าไม่มี confidence ที่ใช้ได้
        if (validSpo2)
          'SpO2 = ${spo2.toStringAsFixed(0)}%', // EN: Add SpO2 only when it passed range checks. TH: เพิ่ม SpO2 เมื่อผ่านการตรวจช่วงค่าเท่านั้น
      ],
      recommendation:
          'ตรวจสอบการเชื่อมต่อและเวอร์ชันเฟิร์มแวร์/โมเดล แล้ววิเคราะห์ใหม่ อย่าใช้ผลนี้ยืนยันว่าปลอดภัย', // EN: Tell the user to verify the source before relying on a new result. TH: แนะนำให้ตรวจต้นทางก่อนเชื่อผลใหม่
    );
  }

  // EN: Use only a validated protocol alert enum.
  // TH: ใช้ alert enum หลังยืนยันว่าอยู่ในค่าที่ protocol รองรับเท่านั้น
  final level =
      alertLevel; // EN: Preserve the validated legacy alert level. TH: ใช้ alert level legacy ที่ผ่านการตรวจ
  final classInfo = _classText(
      stateClass); // EN: Resolve labels and guidance for the validated class. TH: หา label และคำแนะนำของคลาสที่ผ่านการตรวจ

  final signs = <String>[
    'โมเดลบนอุปกรณ์ทำนาย: ${classInfo.label} (ความมั่นใจ $safeConfidence%)', // EN: Describe the legacy model result. TH: อธิบายผลจากโมเดล legacy
    if (validSpo2)
      'SpO2 = ${spo2.toStringAsFixed(0)}%', // EN: Include only an in-range SpO2 value. TH: ใส่ SpO2 เฉพาะค่าที่อยู่ในช่วง
  ];

  // SpO2 วิกฤต: เฟิร์มแวร์เองก็ยกระดับเป็น Emergency ให้แล้วผ่าน alertLevel (R5 override
  // แบบทันที ไม่รอ consecutive window) — ที่นี่แค่เติมข้อความอธิบายสาเหตุให้ชัดเจนขึ้น
  if (validSpo2 && spo2 < 90 && level == dozAlertEmergency) {
    // EN: Explain an already-raised emergency result; do not create one from SpO2 alone. TH: อธิบาย Emergency ที่อุปกรณ์ยกระดับมาแล้ว ไม่สร้างระดับนี้จาก SpO2 อย่างเดียว
    return RiskResult(
      riskClass:
          'ออกซิเจนในเลือดต่ำ ควรหยุดทันที', // EN: Name the reported emergency condition. TH: ระบุภาวะฉุกเฉินที่รายงาน
      alertLevel:
          'Emergency', // EN: Preserve the device's emergency classification. TH: คงระดับ Emergency จากอุปกรณ์
      detectedSigns: [
        ...signs, // EN: Retain validated evidence already assembled. TH: คงหลักฐานที่ประกอบและตรวจแล้ว
        'ค่าออกซิเจนในเลือดต่ำวิกฤต (SpO2 < 90%) — ตรวจจับโดยอุปกรณ์', // EN: Explain the device-provided threshold event. TH: อธิบายเหตุการณ์ตามเกณฑ์ที่อุปกรณ์รายงาน
      ],
      recommendation:
          'หยุดกิจกรรมทันที หายใจช้า ๆ ในที่อากาศถ่ายเท หากไม่ดีขึ้นใน 2 นาที โทร 1669', // EN: Provide the legacy emergency guidance string. TH: ให้ข้อความแนะนำฉุกเฉินของ legacy
    );
  }

  switch (level) {
    case dozAlertSafe:
      return RiskResult(
        riskClass: 'ปกติ',
        alertLevel: 'Safe',
        detectedSigns: signs,
        recommendation: 'ค่าปัจจุบันอยู่ในช่วงปลอดภัย ติดตามต่อเนื่องตามปกติ',
      );
    case dozAlertWatch:
      return RiskResult(
        riskClass: classInfo.watchLabel,
        alertLevel: 'Watch',
        detectedSigns: signs,
        recommendation: classInfo.watchRecommendation,
      );
    case dozAlertWarning:
      return RiskResult(
        riskClass: classInfo.warningLabel,
        alertLevel: 'Warning',
        detectedSigns: signs,
        recommendation: classInfo.warningRecommendation,
      );
    case dozAlertEmergency:
    default:
      return RiskResult(
        riskClass: classInfo.emergencyLabel,
        alertLevel: 'Emergency',
        detectedSigns: [
          ...signs,
          'ระดับ Emergency (อาจเกิดจากความมั่นใจสูงต่อเนื่อง, SpO2 วิกฤต, '
              'หรือไม่มีการตอบรับ Warning ภายใน 30 วินาที)',
        ],
        recommendation: classInfo.emergencyRecommendation,
      );
  }
}

bool _isKnownClass(
        int
            stateClass) => // EN: Validate the legacy class enum. TH: ตรวจ enum คลาส legacy
    stateClass == dozClassNormal ||
    stateClass == dozClassDrowsiness ||
    stateClass == dozClassHighStress;

// EN: Accept only the four explicitly defined legacy alert levels.
// TH: ยอมรับเฉพาะระดับเตือน legacy สี่ค่าที่ประกาศไว้อย่างชัดเจน
bool _isKnownAlertLevel(
        int alertLevel) => // EN: Validate the legacy alert enum. TH: ตรวจ enum alert legacy
    alertLevel >= dozAlertSafe && alertLevel <= dozAlertEmergency;

class _ClassText {
  // EN: Group labels and recommendations for one class. TH: รวม label และคำแนะนำของคลาสหนึ่ง
  const _ClassText({
    // EN: Build an immutable class-text record. TH: สร้างระเบียนข้อความคลาสที่แก้ไขไม่ได้
    required this.label,
    required this.watchLabel,
    required this.watchRecommendation,
    required this.warningLabel,
    required this.warningRecommendation,
    required this.emergencyLabel,
    required this.emergencyRecommendation,
  });

  final String
      label; // EN: General label for the predicted class. TH: ชื่อทั่วไปของคลาสที่ทำนาย
  final String
      watchLabel; // EN: User-facing label at Watch level. TH: label สำหรับระดับ Watch
  final String
      watchRecommendation; // EN: Guidance at Watch level. TH: คำแนะนำระดับ Watch
  final String
      warningLabel; // EN: User-facing label at Warning level. TH: label สำหรับระดับ Warning
  final String
      warningRecommendation; // EN: Guidance at Warning level. TH: คำแนะนำระดับ Warning
  final String
      emergencyLabel; // EN: User-facing label at Emergency level. TH: label สำหรับระดับ Emergency
  final String
      emergencyRecommendation; // EN: Guidance at Emergency level. TH: คำแนะนำระดับ Emergency
}

_ClassText _classText(int stateClass) {
  // EN: Map one validated class ID to its localized legacy copy. TH: map class ID ที่ตรวจแล้วเป็นข้อความ legacy
  switch (stateClass) {
    // EN: Select the copy set for this class. TH: เลือกชุดข้อความตามคลาส
    case dozClassDrowsiness: // EN: Return copy for drowsiness. TH: คืนข้อความสำหรับคลาสง่วง
      return const _ClassText(
        label: 'ง่วง (Drowsiness)',
        watchLabel: 'เริ่มมีสัญญาณง่วง',
        watchRecommendation:
            'เริ่มมีสัญญาณง่วง วางแผนหยุดพักใน 15 นาที ดื่มน้ำ และเพิ่มความระมัดระวัง',
        warningLabel: 'เสี่ยงหลับใน ควรพักทันที',
        warningRecommendation:
            'พบสัญญาณหลับในชัดเจน จอดในจุดปลอดภัยทันที งีบ 15-20 นาที '
            'ดื่มกาแฟแล้วรอ 20 นาทีก่อนขับต่อ',
        emergencyLabel: 'เสี่ยงหลับในขั้นวิกฤต ควรหยุดทันที',
        emergencyRecommendation:
            'หยุดรถ/กิจกรรมทันทีในพื้นที่ปลอดภัย กดตอบรับการแจ้งเตือนถ้ายังตื่นอยู่ '
            'หากไม่ตอบสนอง ให้ผู้ดูแล/ฉุกเฉินเข้าตรวจสอบ',
      );
    case dozClassHighStress: // EN: Return copy for high stress/fatigue. TH: คืนข้อความสำหรับความเครียด/อ่อนล้าสูง
      return const _ClassText(
        label: 'เครียด/อ่อนล้าสูง (High-Stress)',
        watchLabel: 'เริ่มอ่อนล้า ควรระวัง',
        watchRecommendation:
            'ลดความเร็วของกิจกรรม ดื่มน้ำ และพักสั้น ๆ เพื่อประเมินความพร้อม',
        warningLabel: 'ควรพัก (ร่างกายอ่อนล้า/เครียด)',
        warningRecommendation:
            'พักหายใจช้า ๆ 3-5 นาที ลดสิ่งกระตุ้น และติดตามค่าซ้ำอีกครั้ง',
        emergencyLabel: 'ความเครียด/ความอ่อนล้าขั้นวิกฤต',
        emergencyRecommendation:
            'หยุดกิจกรรมทันที อยู่ในพื้นที่ปลอดภัย และให้ผู้ดูแลตรวจสอบสถานการณ์',
      );
    case dozClassNormal: // EN: Return copy for the normal class. TH: คืนข้อความสำหรับคลาสปกติ
    default: // EN: Keep a fallback for callers outside the validated path. TH: คง fallback สำหรับกรณีเรียกนอกเส้นทางที่ตรวจแล้ว
      return const _ClassText(
        label: 'ปกติ (Normal)',
        watchLabel: 'ระดับความเสี่ยงเริ่มขยับ ควรสังเกตอาการ',
        watchRecommendation:
            'ยังอยู่ในเกณฑ์ปกติแต่เริ่มมีความผันผวน ติดตามต่อเนื่อง',
        warningLabel: 'ควรพัก แม้ผลทำนายเป็นปกติ',
        warningRecommendation:
            'ค่าสัญญาณชีพผันผวนสูงกว่าปกติ (เช่น SpO2 ต่ำ) พักสั้น ๆ และประเมินอาการ',
        emergencyLabel: 'ค่าฉุกเฉินจากอุปกรณ์ (สัญญาณชีพวิกฤต)',
        emergencyRecommendation:
            'หยุดกิจกรรมทันที ตรวจสอบอาการ และติดต่อผู้ดูแล/1669 หากไม่ดีขึ้น',
      );
  }
}
