import '../models/risk_result.dart'; // EN: Build typed risk results for legacy BLE packets. TH: สร้างผลความเสี่ยงแบบกำหนดชนิดจาก packet BLE รุ่นเก่า

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
RiskResult mapDeviceAlert({ // EN: Translate a legacy device prediction into app status. TH: แปลงผลทำนายจากอุปกรณ์รุ่นเก่าเป็นสถานะแอป
  required int stateClass, // EN: Read the legacy class ID. TH: อ่านรหัสคลาสรุ่นเก่า
  required int alertLevel, // EN: Read the legacy four-level alert ID. TH: อ่านรหัสเตือนสี่ระดับรุ่นเก่า
  required int confidencePercent, // EN: Read confidence as an integer percentage. TH: อ่านความมั่นใจเป็นเปอร์เซ็นต์จำนวนเต็ม
  required double spo2, // EN: Read an optional oxygen estimate from the old packet. TH: อ่านค่าออกซิเจนประมาณจาก packet เก่า
}) { // EN: Begin validation before displaying a state. TH: เริ่มตรวจค่าก่อนแสดงสถานะ
  // EN: Validate protocol enums and confidence instead of clamping corruption into a real state.
  // TH: ตรวจ enum และความมั่นใจ แทนการ clamp ค่าที่เสียให้กลายเป็นสถานะจริง
  final validConfidence = confidencePercent >= 0 && // EN: Require a nonnegative confidence percentage. TH: บังคับเปอร์เซ็นต์ความมั่นใจไม่ติดลบ
      confidencePercent <=
          100; // EN: Accept confidence only as a percentage. TH: รับ confidence เฉพาะช่วงเปอร์เซ็นต์
  final safeConfidence = validConfidence // EN: Select a value safe to show to the user. TH: เลือกค่าที่ปลอดภัยสำหรับแสดงผู้ใช้
      ? confidencePercent // EN: Keep the original percentage when valid. TH: คงเปอร์เซ็นต์เดิมเมื่อถูกต้อง
      : 0; // EN: Keep invalid values from appearing as confidence. TH: กันค่าผิดไม่ให้แสดงเป็น confidence
  final validSpo2 = spo2.isFinite && // EN: Reject NaN and infinite oxygen values. TH: ปฏิเสธค่าออกซิเจน NaN และอนันต์
      spo2 > 0 && // EN: Require a positive percentage. TH: บังคับเปอร์เซ็นต์เป็นค่าบวก
      spo2 <=
          100; // EN: Accept only finite SpO2 percentages. TH: รับเฉพาะ SpO2 เปอร์เซ็นต์ที่เป็น finite

  // EN: Reject unknown IDs and malformed confidence as an unavailable warning, never as Safe.
  // TH: ปฏิเสธ ID ที่ไม่รู้จักหรือ confidence ผิดช่วงเป็น Warning ที่ใช้วิเคราะห์ไม่ได้ ไม่ใช่ Safe
  if (!_isKnownClass(stateClass) || // EN: Reject class codes outside the legacy enum. TH: ปฏิเสธรหัสคลาสที่ไม่อยู่ใน enum รุ่นเก่า
      !_isKnownAlertLevel(alertLevel) || // EN: Reject undefined alert levels. TH: ปฏิเสธระดับเตือนที่ไม่กำหนดไว้
      !validConfidence) { // EN: Reject confidence outside 0 to 100. TH: ปฏิเสธความมั่นใจนอกช่วง 0 ถึง 100
    // EN: Collect reasons for rejecting this legacy device result.
    // TH: รวมสาเหตุที่ต้องปฏิเสธผลจากอุปกรณ์รุ่นเก่านี้
    final reasons = <String>[ // EN: Collect all protocol errors for diagnostic text. TH: รวบรวมข้อผิดพลาดของโปรโตคอลไว้แจ้งผู้ใช้
      if (!_isKnownClass(stateClass)) // EN: Add a reason when the class ID is unknown. TH: เพิ่มเหตุผลเมื่อรหัสคลาสไม่รู้จัก
        'class ID ไม่รู้จัก ($stateClass)', // EN: Explain an unknown class ID. TH: ระบุสาเหตุเมื่อ class ID ไม่รู้จัก
      if (!_isKnownAlertLevel(alertLevel)) // EN: Add a reason when the level is unknown. TH: เพิ่มเหตุผลเมื่อระดับเตือนไม่รู้จัก
        'alert level ไม่รู้จัก ($alertLevel)', // EN: Explain an unsupported alert ID. TH: ระบุสาเหตุเมื่อ alert ID ไม่รองรับ
      if (!validConfidence) // EN: Add a reason when confidence is invalid. TH: เพิ่มเหตุผลเมื่อค่าความมั่นใจผิด
        'confidence อยู่นอกช่วง 0–100 ($confidencePercent)', // EN: Include the invalid range condition. TH: แจ้งว่า confidence อยู่นอกช่วงที่รับได้
    ]; // EN: Finish the list of protocol violations. TH: จบรายการค่าที่ผิดโปรโตคอล
    return RiskResult( // EN: Return an unavailable warning instead of a trusted class. TH: คืน Warning ที่ใช้วิเคราะห์ไม่ได้แทนคลาสที่เชื่อถือได้
      riskClass:
          'ผลจากอุปกรณ์ไม่ถูกต้อง', // EN: Mark the result as invalid. TH: ทำเครื่องหมายว่าผลไม่ถูกต้อง
      alertLevel:
          'Warning', // EN: Avoid labeling rejected data as Safe. TH: ไม่ติดป้ายข้อมูลที่ปฏิเสธว่า Safe
      detectedSigns: [ // EN: Explain why this packet cannot establish safety. TH: อธิบายว่าทำไม packet นี้ใช้ยืนยันความปลอดภัยไม่ได้
        'งดใช้ผลนี้ประเมินความเสี่ยง: ${reasons.join('; ')}', // EN: Expose why the device result was rejected. TH: แสดงเหตุผลที่ปฏิเสธผลจากอุปกรณ์
        if (validConfidence) // EN: Show confidence only when its range is valid. TH: แสดงความมั่นใจเมื่อช่วงค่าถูกต้องเท่านั้น
          'ความมั่นใจ $safeConfidence%' // EN: Show confidence only when valid. TH: แสดง confidence เมื่อผ่านการตรวจเท่านั้น
        else // EN: Mark confidence unavailable when invalid. TH: ระบุว่าความมั่นใจใช้ไม่ได้เมื่อค่าผิด
          'ไม่มีค่าความมั่นใจที่ใช้ได้', // EN: State that confidence cannot be used. TH: ระบุว่าไม่มี confidence ที่ใช้ได้
        if (validSpo2) // EN: Show only an oxygen estimate within range. TH: แสดงค่าออกซิเจนประมาณเฉพาะที่อยู่ในช่วง
          'SpO2 = ${spo2.toStringAsFixed(0)}%', // EN: Add SpO2 only when it passed range checks. TH: เพิ่ม SpO2 เมื่อผ่านการตรวจช่วงค่าเท่านั้น
      ], // EN: Finish the rejected-packet evidence list. TH: จบรายการหลักฐานของ packet ที่ปฏิเสธ
      recommendation:
          'ตรวจสอบการเชื่อมต่อและเวอร์ชันเฟิร์มแวร์/โมเดล แล้ววิเคราะห์ใหม่ อย่าใช้ผลนี้ยืนยันว่าปลอดภัย', // EN: Tell the user to verify the source before relying on a new result. TH: แนะนำให้ตรวจต้นทางก่อนเชื่อผลใหม่
    ); // EN: Finish the fail-closed result. TH: จบผลลัพธ์ที่ปฏิเสธแบบปลอดภัย
  } // EN: Finish invalid-packet handling. TH: จบการจัดการ packet ที่ผิด

  // EN: Use only a validated protocol alert enum.
  // TH: ใช้ alert enum หลังยืนยันว่าอยู่ในค่าที่ protocol รองรับเท่านั้น
  final level =
      alertLevel; // EN: Preserve the validated legacy alert level. TH: ใช้ alert level legacy ที่ผ่านการตรวจ
  final classInfo = _classText(
      stateClass); // EN: Resolve labels and guidance for the validated class. TH: หา label และคำแนะนำของคลาสที่ผ่านการตรวจ

  final signs = <String>[ // EN: Build the evidence shown with a valid legacy inference. TH: สร้างหลักฐานที่แสดงกับผลทำนายรุ่นเก่าที่ผ่านตรวจ
    'โมเดลบนอุปกรณ์ทำนาย: ${classInfo.label} (ความมั่นใจ $safeConfidence%)', // EN: Describe the legacy model result. TH: อธิบายผลจากโมเดล legacy
    if (validSpo2) // EN: Include only an in-range oxygen estimate. TH: ใส่ค่าออกซิเจนประมาณเฉพาะที่อยู่ในช่วง
      'SpO2 = ${spo2.toStringAsFixed(0)}%', // EN: Include only an in-range SpO2 value. TH: ใส่ SpO2 เฉพาะค่าที่อยู่ในช่วง
  ]; // EN: Finish the evidence list for the recognized result. TH: จบรายการหลักฐานสำหรับผลที่รู้จัก

  // SpO2 วิกฤต: เฟิร์มแวร์เองก็ยกระดับเป็น Emergency ให้แล้วผ่าน alertLevel (R5 override
  // แบบทันที ไม่รอ consecutive window) — ที่นี่แค่เติมข้อความอธิบายสาเหตุให้ชัดเจนขึ้น
  if (validSpo2 && spo2 < 90 && level == dozAlertEmergency) { // EN: Describe an emergency already declared by legacy firmware. TH: อธิบายฉุกเฉินที่เฟิร์มแวร์รุ่นเก่าประกาศมาแล้ว
    // EN: Explain an already-raised emergency result; do not create one from SpO2 alone. TH: อธิบาย Emergency ที่อุปกรณ์ยกระดับมาแล้ว ไม่สร้างระดับนี้จาก SpO2 อย่างเดียว
    return RiskResult( // EN: Preserve the old device's emergency level. TH: คงระดับฉุกเฉินที่อุปกรณ์เก่ารายงาน
      riskClass:
          'ออกซิเจนในเลือดต่ำ ควรหยุดทันที', // EN: Name the reported emergency condition. TH: ระบุภาวะฉุกเฉินที่รายงาน
      alertLevel:
          'Emergency', // EN: Preserve the device's emergency classification. TH: คงระดับ Emergency จากอุปกรณ์
      detectedSigns: [ // EN: Add the threshold event to valid evidence. TH: เพิ่มเหตุการณ์ตามเกณฑ์ในหลักฐานที่ตรวจแล้ว
        ...signs, // EN: Retain validated evidence already assembled. TH: คงหลักฐานที่ประกอบและตรวจแล้ว
        'ค่าออกซิเจนในเลือดต่ำวิกฤต (SpO2 < 90%) — ตรวจจับโดยอุปกรณ์', // EN: Explain the device-provided threshold event. TH: อธิบายเหตุการณ์ตามเกณฑ์ที่อุปกรณ์รายงาน
      ], // EN: Finish emergency evidence. TH: จบรายการหลักฐานฉุกเฉิน
      recommendation:
          'หยุดกิจกรรมทันที หายใจช้า ๆ ในที่อากาศถ่ายเท หากไม่ดีขึ้นใน 2 นาที โทร 1669', // EN: Provide the legacy emergency guidance string. TH: ให้ข้อความแนะนำฉุกเฉินของ legacy
    ); // EN: Finish the emergency result. TH: จบผลลัพธ์ฉุกเฉิน
  } // EN: Finish legacy SpO2 override explanation. TH: จบคำอธิบายการยกระดับ SpO2 รุ่นเก่า

  switch (level) { // EN: Choose the user-facing text for the validated alert enum. TH: เลือกข้อความแสดงผลตาม enum เตือนที่ผ่านตรวจ
    case dozAlertSafe: // EN: Handle the legacy Safe level. TH: จัดการระดับ Safe รุ่นเก่า
      return RiskResult( // EN: Build the Safe result. TH: สร้างผล Safe
        riskClass: 'ปกติ', // EN: Show the normal class. TH: แสดงคลาสปกติ
        alertLevel: 'Safe', // EN: Preserve the Safe level. TH: คงระดับ Safe
        detectedSigns: signs, // EN: Attach validated evidence. TH: แนบหลักฐานที่ตรวจแล้ว
        recommendation: 'ค่าปัจจุบันอยู่ในช่วงปลอดภัย ติดตามต่อเนื่องตามปกติ', // EN: Show legacy follow-up guidance. TH: แสดงคำแนะนำติดตามผลรุ่นเก่า
      ); // EN: Finish the Safe result. TH: จบผล Safe
    case dozAlertWatch: // EN: Handle the legacy Watch level. TH: จัดการระดับ Watch รุ่นเก่า
      return RiskResult( // EN: Build the Watch result. TH: สร้างผล Watch
        riskClass: classInfo.watchLabel, // EN: Use the class-specific Watch label. TH: ใช้ชื่อ Watch ตามคลาส
        alertLevel: 'Watch', // EN: Preserve the Watch level. TH: คงระดับ Watch
        detectedSigns: signs, // EN: Attach validated evidence. TH: แนบหลักฐานที่ตรวจแล้ว
        recommendation: classInfo.watchRecommendation, // EN: Use class-specific guidance. TH: ใช้คำแนะนำตามคลาส
      ); // EN: Finish the Watch result. TH: จบผล Watch
    case dozAlertWarning: // EN: Handle the legacy Warning level. TH: จัดการระดับ Warning รุ่นเก่า
      return RiskResult( // EN: Build the Warning result. TH: สร้างผล Warning
        riskClass: classInfo.warningLabel, // EN: Use the class-specific Warning label. TH: ใช้ชื่อ Warning ตามคลาส
        alertLevel: 'Warning', // EN: Preserve the Warning level. TH: คงระดับ Warning
        detectedSigns: signs, // EN: Attach validated evidence. TH: แนบหลักฐานที่ตรวจแล้ว
        recommendation: classInfo.warningRecommendation, // EN: Use class-specific guidance. TH: ใช้คำแนะนำตามคลาส
      ); // EN: Finish the Warning result. TH: จบผล Warning
    case dozAlertEmergency: // EN: Handle the legacy Emergency level. TH: จัดการระดับ Emergency รุ่นเก่า
    default: // EN: Keep the switch exhaustive for Dart while enums were checked above. TH: คง switch ให้ครบตาม Dart แม้ตรวจ enum แล้ว
      return RiskResult( // EN: Build the emergency result. TH: สร้างผลฉุกเฉิน
        riskClass: classInfo.emergencyLabel, // EN: Use the class-specific emergency label. TH: ใช้ชื่อฉุกเฉินตามคลาส
        alertLevel: 'Emergency', // EN: Preserve the device's emergency level. TH: คงระดับฉุกเฉินจากอุปกรณ์
        detectedSigns: [ // EN: Add a legacy reason summary to the evidence. TH: เพิ่มสรุปสาเหตุรุ่นเก่าในหลักฐาน
          ...signs, // EN: Keep already validated evidence. TH: คงหลักฐานที่ตรวจแล้ว
          'ระดับ Emergency (อาจเกิดจากความมั่นใจสูงต่อเนื่อง, SpO2 วิกฤต, '
              'หรือไม่มีการตอบรับ Warning ภายใน 30 วินาที)',
        ], // EN: Finish emergency evidence. TH: จบหลักฐานฉุกเฉิน
        recommendation: classInfo.emergencyRecommendation, // EN: Show class-specific emergency guidance. TH: แสดงคำแนะนำฉุกเฉินตามคลาส
      ); // EN: Finish the emergency result. TH: จบผลฉุกเฉิน
  } // EN: Finish validated alert-level mapping. TH: จบการแปลงระดับเตือนที่ผ่านตรวจ
} // EN: Finish legacy device result mapping. TH: จบการแปลงผลจากอุปกรณ์รุ่นเก่า

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
