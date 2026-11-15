class RiskResult {
  // EN: Represent one risk-analysis result. TH: แทนผลการวิเคราะห์ความเสี่ยงหนึ่งรายการ
  const RiskResult({
    // EN: Create an immutable result. TH: สร้างผลลัพธ์ที่แก้ไขภายหลังไม่ได้
    required this.riskClass, // EN: Require the model or rule's class name. TH: บังคับระบุชื่อคลาสจากโมเดลหรือกฎ
    required this.alertLevel, // EN: Require the user-facing alert level. TH: บังคับระบุระดับแจ้งเตือนที่แสดงผู้ใช้
    required this.detectedSigns, // EN: Require the evidence strings for this result. TH: บังคับระบุสัญญาณประกอบผล
    required this.recommendation, // EN: Require the recommended next action. TH: บังคับระบุคำแนะนำการปฏิบัติต่อ
  }); // EN: Finish constructing the result. TH: จบการสร้างผลลัพธ์

  final String
      riskClass; // EN: Store the result's class label. TH: เก็บ label คลาสของผลลัพธ์
  final String
      alertLevel; // EN: Store Safe, Watch, Warning, Emergency, or Unknown. TH: เก็บระดับ Safe, Watch, Warning, Emergency หรือ Unknown
  final List<String>
      detectedSigns; // EN: Store bounded human-readable evidence. TH: เก็บหลักฐานข้อความที่จำกัดขนาด
  final String
      recommendation; // EN: Store the follow-up guidance. TH: เก็บคำแนะนำให้ดำเนินการต่อ

  bool
      get shouldStoreAlert => // EN: Decide whether this level is a confirmed alert. TH: ตัดสินว่าระดับนี้เป็น alert ที่ยืนยันแล้วหรือไม่
          const {'Watch', 'Warning', 'Emergency'}.contains(
              alertLevel); // EN: Do not treat Unknown as a confirmed alert. TH: ไม่นับ Unknown เป็น alert ที่ยืนยันแล้ว

  int get levelValue => switch (alertLevel) {
        // EN: Map known levels to chart coordinates. TH: แปลงระดับที่รู้จักเป็นพิกัดกราฟ
        'Safe' =>
          0, // EN: Place Safe at the baseline. TH: วาง Safe ที่ค่าฐานกราฟ
        'Watch' => 1, // EN: Place Watch above Safe. TH: วาง Watch เหนือ Safe
        'Warning' =>
          2, // EN: Place Warning above Watch. TH: วาง Warning เหนือ Watch
        'Emergency' =>
          3, // EN: Place Emergency at the highest known level. TH: วาง Emergency ที่ระดับสูงสุดที่รู้จัก
        _ =>
          -1, // EN: Keep Unknown distinct from Safe in charts. TH: แยก Unknown ออกจาก Safe บนกราฟ
      }; // EN: Finish alert-level mapping. TH: จบการแปลงระดับแจ้งเตือน

  Map<String, dynamic> toJson() => {
        // EN: Serialize fields using the app's stable JSON keys. TH: serialize field ด้วย key JSON คงที่ของแอป
        'riskClass': riskClass, // EN: Preserve the class label. TH: คงชื่อคลาส
        'alertLevel':
            alertLevel, // EN: Preserve the alert level. TH: คงระดับแจ้งเตือน
        'detectedSigns':
            detectedSigns, // EN: Preserve the evidence list. TH: คงรายการสัญญาณ
        'recommendation':
            recommendation, // EN: Preserve the guidance text. TH: คงข้อความคำแนะนำ
      }; // EN: Finish JSON serialization. TH: จบการ serialize JSON

  factory RiskResult.fromJson(Map<String, dynamic> json) {
    // EN: Parse an untrusted persisted or remote object. TH: แปลง object จาก storage หรือ network ที่ยังไม่เชื่อถือ
    final rawSigns = json[
        'detectedSigns']; // EN: Read evidence before checking its runtime type. TH: อ่านข้อมูลสัญญาณก่อนตรวจชนิดจริง
    final validLevel = const {
      // EN: Define the only accepted canonical alert levels. TH: กำหนดระดับแจ้งเตือนมาตรฐานที่ยอมรับ
      'Safe', // EN: Accept the known safe level. TH: ยอมรับระดับ Safe
      'Watch', // EN: Accept the known watch level. TH: ยอมรับระดับ Watch
      'Warning', // EN: Accept the known warning level. TH: ยอมรับระดับ Warning
      'Emergency', // EN: Accept the known emergency level. TH: ยอมรับระดับ Emergency
    }.contains(json[
            'alertLevel']) // EN: Reject missing or unknown levels instead of calling them Safe. TH: ปฏิเสธระดับที่หายไปหรือไม่รู้จัก แทนการเรียกว่า Safe
        ? json['alertLevel']
            as String // EN: Keep a validated canonical level. TH: คงระดับมาตรฐานที่ผ่านการตรวจ
        : 'Unknown'; // EN: Fail visibly when the level is absent or malformed. TH: แสดง Unknown เมื่อระดับหายไปหรือผิดรูป
    return RiskResult(
      // EN: Construct the validated result object. TH: สร้าง object ผลลัพธ์ที่ตรวจแล้ว
      riskClass: _boundedText(json['riskClass'], 'Unknown',
          80), // EN: Bound the class text and avoid a false Normal default. TH: จำกัดข้อความคลาสและไม่ตั้งค่าเริ่มต้นเป็น Normal ที่อาจทำให้เข้าใจผิด
      alertLevel:
          validLevel, // EN: Store only a known level or Unknown. TH: เก็บเฉพาะระดับที่รู้จักหรือ Unknown
      detectedSigns: rawSigns
              is List // EN: Require an actual list before reading evidence. TH: บังคับให้ข้อมูลสัญญาณเป็น list ก่อนนำมาใช้
          ? rawSigns // EN: Iterate only after confirming the collection type. TH: วนอ่านหลังยืนยันชนิด collection แล้ว
              .whereType<
                  String>() // EN: Ignore non-text values instead of coercing arbitrary objects. TH: ข้ามค่าที่ไม่ใช่ข้อความ แทนการแปลง object ใด ๆ
              .take(
                  16) // EN: Limit the number of displayed evidence entries. TH: จำกัดจำนวนรายการสัญญาณที่จะแสดง
              .map((item) => _boundedText(item, '',
                  160)) // EN: Bound each evidence string. TH: จำกัดความยาวข้อความสัญญาณแต่ละรายการ
              .toList(
                  growable:
                      false) // EN: Store a fixed-size parsed list. TH: เก็บรายการที่ไม่เพิ่มขนาดภายหลัง
          : const [], // EN: Use no evidence when the field is malformed. TH: ไม่ใส่สัญญาณเมื่อ field ผิดรูป
      recommendation: _boundedText(
        // EN: Bound the user-visible guidance text. TH: จำกัดข้อความคำแนะนำที่แสดงผู้ใช้
        json[
            'recommendation'], // EN: Read the recommendation without trusting its type. TH: อ่านคำแนะนำโดยไม่เชื่อชนิดข้อมูลล่วงหน้า
        '', // EN: Use empty guidance when no valid text exists. TH: ใช้ข้อความว่างเมื่อไม่มีข้อความที่ถูกต้อง
        1000, // EN: Cap a persisted recommendation at 1,000 characters. TH: จำกัดคำแนะนำที่อ่านจาก storage ไม่เกิน 1,000 ตัวอักษร
      ), // EN: Finish recommendation parsing. TH: จบการแปลงคำแนะนำ
    ); // EN: Return the parsed risk result. TH: คืนผลการวิเคราะห์ที่แปลงแล้ว
  } // EN: Finish parsing an external risk result. TH: จบการแปลงผล risk จากภายนอก
} // EN: Finish the risk-result model. TH: จบ model ผลการวิเคราะห์ความเสี่ยง

String _boundedText(Object? value, String fallback, int maxLength) {
  // EN: Accept bounded text and reject non-string values. TH: รับข้อความแบบจำกัดและปฏิเสธค่าที่ไม่ใช่ string
  if (value is! String) {
    // EN: Check the value type before using it as UI text. TH: ตรวจชนิดก่อนใช้เป็นข้อความ UI
    return fallback; // EN: Use the caller's safe fallback for malformed data. TH: ใช้ค่า fallback ที่ปลอดภัยเมื่อข้อมูลผิดรูป
  } // EN: Finish the runtime-type check. TH: จบการตรวจชนิดข้อมูล
  if (value.length <= maxLength) {
    // EN: Keep text that already fits the field limit. TH: คงข้อความที่อยู่ในขอบเขต field
    return value; // EN: Return the validated text unchanged. TH: คืนข้อความที่ผ่านการตรวจโดยไม่เปลี่ยน
  } // EN: Finish the length check. TH: จบการตรวจความยาว
  return value.substring(0,
      maxLength); // EN: Truncate excessive text before display or storage. TH: ตัดข้อความที่ยาวเกินก่อนแสดงหรือเก็บ
} // EN: Finish bounded-text parsing. TH: จบการแปลงข้อความแบบจำกัดความยาว
