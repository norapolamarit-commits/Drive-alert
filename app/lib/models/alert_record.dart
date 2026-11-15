import 'sensor_data.dart'; // EN: Include the sensor snapshot saved with an alert. TH: ใช้ snapshot sensor ที่บันทึกพร้อม alert
import 'risk_result.dart'; // EN: Include the risk result saved with an alert. TH: ใช้ผล risk ที่บันทึกพร้อม alert

class AlertRecord {
  // EN: Represent one persisted alert-history entry. TH: แทนรายการประวัติ alert ที่บันทึกไว้หนึ่งรายการ
  const AlertRecord({
    // EN: Create an immutable alert record. TH: สร้าง alert record ที่แก้ไขภายหลังไม่ได้
    required this.id, // EN: Require a stable record identifier. TH: บังคับระบุรหัส record ที่คงที่
    required this.timestamp, // EN: Require the event time. TH: บังคับระบุเวลา event
    required this.sensorData, // EN: Require the associated sensor snapshot. TH: บังคับระบุ snapshot sensor ที่เกี่ยวข้อง
    required this.riskResult, // EN: Require the associated risk result. TH: บังคับระบุผล risk ที่เกี่ยวข้อง
    this.userResponse =
        '', // EN: Default an absent user response to empty text. TH: ตั้งคำตอบผู้ใช้เป็นข้อความว่างเมื่อไม่มี
  }); // EN: Finish constructing the alert record. TH: จบการสร้าง alert record

  final String id; // EN: Store the record identifier. TH: เก็บรหัส record
  final DateTime
      timestamp; // EN: Store when the event occurred. TH: เก็บเวลาเกิด event
  final SensorData
      sensorData; // EN: Store the associated sensor values. TH: เก็บค่าจาก sensor ที่เกี่ยวข้อง
  final RiskResult
      riskResult; // EN: Store the associated classified result. TH: เก็บผลจำแนกที่เกี่ยวข้อง
  final String
      userResponse; // EN: Store the user's optional response. TH: เก็บคำตอบเสริมจากผู้ใช้

  AlertRecord copyWith({String? userResponse}) => AlertRecord(
        // EN: Copy this record while optionally updating the response. TH: คัดลอก record และอัปเดตคำตอบได้ตามต้องการ
        id: id, // EN: Preserve the stable record identifier. TH: คงรหัส record เดิม
        timestamp:
            timestamp, // EN: Preserve the event time. TH: คงเวลา event เดิม
        sensorData:
            sensorData, // EN: Preserve the associated sensor snapshot. TH: คง snapshot sensor เดิม
        riskResult:
            riskResult, // EN: Preserve the associated risk result. TH: คงผล risk เดิม
        userResponse: userResponse ??
            this.userResponse, // EN: Use the new response only when provided. TH: ใช้คำตอบใหม่เมื่อส่งมาเท่านั้น
      ); // EN: Finish creating the copied alert record. TH: จบการสร้าง alert record สำเนา

  Map<String, dynamic> toJson() => {
        // EN: Serialize the record using stable storage keys. TH: serialize record ด้วย key storage ที่คงที่
        'id':
            id, // EN: Serialize the stable identifier. TH: serialize รหัส record
        'timestamp': timestamp
            .toIso8601String(), // EN: Serialize event time in ISO-8601 format. TH: serialize เวลา event เป็น ISO-8601
        'sensorData': sensorData
            .toJson(), // EN: Serialize the sensor snapshot. TH: serialize snapshot sensor
        'riskResult': riskResult
            .toJson(), // EN: Serialize the risk result. TH: serialize ผล risk
        'userResponse':
            userResponse, // EN: Serialize the optional user response. TH: serializeคำตอบเสริมจากผู้ใช้
      }; // EN: Finish record serialization. TH: จบการ serialize record

  factory AlertRecord.fromJson(Map<String, dynamic> json) {
    // EN: Parse one persisted or remote record with validation. TH: แปลง record จาก storage หรือ network พร้อมตรวจสอบ
    final rawId = json[
        'id']; // EN: Read the identifier before normalizing its type. TH: อ่านรหัสก่อนปรับชนิดข้อมูล
    final id = rawId ==
            null // EN: Preserve legacy behavior for records without an ID. TH: คงพฤติกรรมเดิมสำหรับ record ที่ไม่มี ID
        ? DateTime.now()
            .microsecondsSinceEpoch
            .toString() // EN: Generate a local fallback ID only when absent. TH: สร้าง ID สำรองในเครื่องเฉพาะเมื่อไม่มี
        : rawId is String ||
                rawId
                    is num // EN: Accept historical string or numeric IDs only. TH: ยอมรับเฉพาะ ID แบบ string หรือตัวเลขที่เคยใช้
            ? rawId
                .toString() // EN: Normalize supported IDs to text. TH: ปรับ ID ที่รองรับให้เป็นข้อความ
            : throw const FormatException(
                'Alert ID has an unsupported type.'); // EN: Reject arbitrary objects as identifiers. TH: ปฏิเสธ object ที่ไม่รองรับเป็นรหัส
    if (id.isEmpty || id.length > 128) {
      // EN: Bound identifiers and reject empty values. TH: จำกัดความยาวรหัสและปฏิเสธค่าว่าง
      throw const FormatException(
          'Alert ID is invalid.'); // EN: Let storage skip malformed records. TH: ให้ storage ข้าม record ที่ผิดรูป
    } // EN: Finish identifier validation. TH: จบการตรวจ ID
    final rawTimestamp = json[
        'timestamp']; // EN: Read the serialized event time. TH: อ่านเวลา event ที่ serialize ไว้
    final DateTime
        timestamp; // EN: Hold the validated event timestamp. TH: เก็บ timestamp event ที่ผ่านการตรวจ
    if (rawTimestamp == null) {
      // EN: Support legacy records that omitted timestamps. TH: รองรับ record รุ่นเก่าที่ไม่มี timestamp
      timestamp = DateTime
          .now(); // EN: Use local time only for a genuinely absent field. TH: ใช้เวลาปัจจุบันเฉพาะกรณีไม่มี field จริง
    } else if (rawTimestamp is String) {
      // EN: Require timestamps to use the serialized string form. TH: บังคับ timestamp ให้อยู่ในรูป string ที่ serialize
      final parsed = DateTime.tryParse(
          rawTimestamp); // EN: Parse without leaking low-level parser details. TH: แปลงโดยไม่เผยรายละเอียด parser ระดับล่าง
      if (parsed == null) {
        // EN: Detect malformed timestamp text. TH: ตรวจข้อความ timestamp ที่ผิดรูป
        throw const FormatException(
            'Alert timestamp is invalid.'); // EN: Avoid silently moving a corrupt event to the present. TH: ป้องกันการย้าย event ที่เสียให้ดูเหมือนเกิดตอนนี้
      } // EN: Finish timestamp parse validation. TH: จบการตรวจการแปลง timestamp
      timestamp =
          parsed; // EN: Preserve the validated source time. TH: คงเวลาต้นทางที่ผ่านการตรวจ
    } else {
      // EN: Reject numeric, object, or other unsupported timestamp types. TH: ปฏิเสธ timestamp ที่เป็นตัวเลข object หรือชนิดอื่น
      throw const FormatException(
          'Alert timestamp must be a string.'); // EN: Keep invalid timestamps out of history. TH: กัน timestamp ที่ไม่ถูกต้องออกจากประวัติ
    } // EN: Finish timestamp selection. TH: จบการเลือก timestamp
    final rawSensorData = json[
        'sensorData']; // EN: Read the nested sensor object. TH: อ่าน object sensor ที่ซ้อนอยู่
    if (rawSensorData is! Map<String, dynamic>) {
      // EN: Validate the sensor object's runtime shape. TH: ตรวจโครงสร้างจริงของ object sensor
      throw const FormatException(
          'Alert sensorData must be an object.'); // EN: Reject missing or malformed sensor data. TH: ปฏิเสธข้อมูล sensor ที่หายหรือผิดรูป
    } // EN: Finish sensor-object validation. TH: จบการตรวจ object sensor
    final rawRiskResult = json[
        'riskResult']; // EN: Read the nested risk object. TH: อ่าน object risk ที่ซ้อนอยู่
    if (rawRiskResult is! Map<String, dynamic>) {
      // EN: Validate the risk object's runtime shape. TH: ตรวจโครงสร้างจริงของ object risk
      throw const FormatException(
          'Alert riskResult must be an object.'); // EN: Reject missing or malformed risk results. TH: ปฏิเสธผล risk ที่หายหรือผิดรูป
    } // EN: Finish risk-object validation. TH: จบการตรวจ object risk
    final rawUserResponse = json[
        'userResponse']; // EN: Read the optional user response. TH: อ่านคำตอบผู้ใช้ที่เป็นตัวเลือก
    if (rawUserResponse != null && rawUserResponse is! String) {
      // EN: Reject non-text response values. TH: ปฏิเสธคำตอบที่ไม่ใช่ข้อความ
      throw const FormatException(
          'Alert userResponse must be text.'); // EN: Avoid converting arbitrary data into UI text. TH: ป้องกันการแปลงข้อมูลใด ๆ เป็นข้อความ UI
    } // EN: Finish response-type validation. TH: จบการตรวจชนิดคำตอบ
    final response = rawUserResponse as String? ??
        ''; // EN: Preserve the empty default when no response exists. TH: คงค่าเริ่มต้นว่างเมื่อไม่มีคำตอบ
    if (response.length > 2000) {
      // EN: Bound user-provided response text. TH: จำกัดความยาวข้อความที่ผู้ใช้ป้อน
      throw const FormatException(
          'Alert userResponse is too long.'); // EN: Reject oversized stored text instead of rendering it. TH: ปฏิเสธข้อความ storage ที่ยาวเกินก่อนนำไปแสดง
    } // EN: Finish response-length validation. TH: จบการตรวจความยาวคำตอบ
    return AlertRecord(
      // EN: Construct the record only after all outer fields validate. TH: สร้าง record หลังตรวจ field ชั้นนอกทั้งหมดแล้ว
      id: id, // EN: Store the validated or legacy fallback identifier. TH: เก็บ ID ที่ผ่านการตรวจหรือ ID สำรองของ record รุ่นเก่า
      timestamp:
          timestamp, // EN: Store the validated event time. TH: เก็บเวลา event ที่ผ่านการตรวจ
      sensorData: SensorData.fromJson(
          rawSensorData), // EN: Parse and validate sensor measurements. TH: แปลงและตรวจค่าจาก sensor
      riskResult: RiskResult.fromJson(
          rawRiskResult), // EN: Parse risk with Unknown-safe defaults. TH: แปลงผล risk โดยใช้ค่าเริ่มต้น Unknown ที่ไม่ทำให้ดูเป็น Safe
      userResponse:
          response, // EN: Store the validated bounded user response. TH: เก็บคำตอบผู้ใช้ที่ตรวจและจำกัดแล้ว
    ); // EN: Finish constructing the validated alert record. TH: จบการสร้าง alert record ที่ผ่านการตรวจ
  } // EN: Finish parsing one alert record. TH: จบการแปลง alert record หนึ่งรายการ
} // EN: Finish the alert-record model. TH: จบ model alert record
