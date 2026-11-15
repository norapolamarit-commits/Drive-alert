import 'dart:convert'; // EN: Decode serialized sensor records. TH: ถอดรหัส record sensor ที่ serialize ไว้
import 'dart:math'; // EN: Calculate vector magnitudes. TH: คำนวณขนาดเวกเตอร์

const double
    _maxFiniteSensorValue = // EN: Set a defensive numeric bound for persisted or remote fields. TH: กำหนดขอบเขตตัวเลขป้องกันข้อมูลจาก storage หรือ network
    1e12; // EN: Keep values far below floating-point overflow during magnitude calculations. TH: จำกัดค่าให้ห่างจาก overflow ของ floating point ระหว่างคำนวณ magnitude

class SensorData {
  // EN: Represent one wearable sensor snapshot. TH: แทน snapshot จาก sensor ของอุปกรณ์สวมใส่หนึ่งชุด
  SensorData({
    // EN: Construct a sensor snapshot from parsed or live measurements. TH: สร้าง snapshot จากค่าที่อ่านสดหรือแปลงจากข้อมูล
    required this.heartRate, // EN: Require the heart-rate field, using zero when unavailable. TH: บังคับระบุ heart rate และใช้ศูนย์เมื่อไม่มีค่า
    required this.spo2, // EN: Require the SpO2 field, using zero when unavailable. TH: บังคับระบุ SpO2 และใช้ศูนย์เมื่อไม่มีค่า
    required this.gsr, // EN: Require the GSR measurement. TH: บังคับระบุค่าการนำไฟฟ้าผิวหนัง
    required this.temperature, // EN: Require the temperature measurement. TH: บังคับระบุอุณหภูมิ
    this.ecgRate =
        0, // EN: Default unavailable ECG rate to zero. TH: ตั้ง ECG rate เป็นศูนย์เมื่อไม่มีค่า
    this.ecgRrInterval =
        0, // EN: Default unavailable ECG interval to zero. TH: ตั้งช่วง RR จาก ECG เป็นศูนย์เมื่อไม่มีค่า
    this.ecgHrv =
        0, // EN: Default unavailable ECG HRV to zero. TH: ตั้ง HRV จาก ECG เป็นศูนย์เมื่อไม่มีค่า
    required this.accelX, // EN: Require the acceleration X axis. TH: บังคับระบุความเร่งแกน X
    required this.accelY, // EN: Require the acceleration Y axis. TH: บังคับระบุความเร่งแกน Y
    required this.accelZ, // EN: Require the acceleration Z axis. TH: บังคับระบุความเร่งแกน Z
    required this.gyroX, // EN: Require the angular-rate X axis. TH: บังคับระบุอัตราการหมุนแกน X
    required this.gyroY, // EN: Require the angular-rate Y axis. TH: บังคับระบุอัตราการหมุนแกน Y
    required this.gyroZ, // EN: Require the angular-rate Z axis. TH: บังคับระบุอัตราการหมุนแกน Z
    this.rawRed, // EN: Preserve the optional MAX30102 Red ADC mean. TH: เก็บค่าเฉลี่ย ADC ช่อง Red ของ MAX30102 เมื่อมี
    this.rawIr, // EN: Preserve the optional MAX30102 IR ADC mean. TH: เก็บค่าเฉลี่ย ADC ช่อง IR ของ MAX30102 เมื่อมี
    this.deviceTimestampMs, // EN: Preserve the optional device-clock timestamp. TH: เก็บ timestamp จากนาฬิกาอุปกรณ์เมื่อมี
    DateTime?
        timestamp, // EN: Accept the source timestamp when available. TH: รับ timestamp จากต้นทางเมื่อมี
  }) : timestamp = timestamp ??
            DateTime
                .now(); // EN: Use local receive time only when the caller provides no timestamp. TH: ใช้เวลารับในเครื่องเมื่อ caller ไม่ส่ง timestamp มา

  final int
      heartRate; // EN: Store heart rate in beats per minute when available. TH: เก็บ heart rate หน่วยครั้งต่อนาทีเมื่อมีค่า
  final int
      spo2; // EN: Store SpO2 as a percentage when available. TH: เก็บ SpO2 เป็นเปอร์เซ็นต์เมื่อมีค่า
  final double
      gsr; // EN: Store the GSR value in the source-defined unit. TH: เก็บค่า GSR ตามหน่วยที่ต้นทางกำหนด
  final double
      temperature; // EN: Store temperature in the source-defined unit. TH: เก็บอุณหภูมิตามหน่วยที่ต้นทางกำหนด
  final int
      ecgRate; // EN: Store ECG-derived rate when a source provides it. TH: เก็บอัตราที่คำนวณจาก ECG เมื่อแหล่งข้อมูลส่งมา
  final double
      ecgRrInterval; // EN: Store ECG-derived RR interval when available. TH: เก็บช่วง RR จาก ECG เมื่อมีค่า
  final double
      ecgHrv; // EN: Store ECG-derived HRV when available. TH: เก็บ HRV จาก ECG เมื่อมีค่า
  final double
      accelX; // EN: Store acceleration on the X axis. TH: เก็บความเร่งแกน X
  final double
      accelY; // EN: Store acceleration on the Y axis. TH: เก็บความเร่งแกน Y
  final double
      accelZ; // EN: Store acceleration on the Z axis. TH: เก็บความเร่งแกน Z
  final double
      gyroX; // EN: Store angular rate on the X axis. TH: เก็บอัตราการหมุนแกน X
  final double
      gyroY; // EN: Store angular rate on the Y axis. TH: เก็บอัตราการหมุนแกน Y
  final double
      gyroZ; // EN: Store angular rate on the Z axis. TH: เก็บอัตราการหมุนแกน Z
  final int?
      rawRed; // EN: Store the raw Red ADC mean without converting it to a physiological measure. TH: เก็บค่าเฉลี่ย ADC Red โดยไม่แปลงเป็นค่าทางสรีรวิทยา
  final int?
      rawIr; // EN: Store the raw IR ADC mean without converting it to a physiological measure. TH: เก็บค่าเฉลี่ย ADC IR โดยไม่แปลงเป็นค่าทางสรีรวิทยา
  final int?
      deviceTimestampMs; // EN: Store the device timestamp in milliseconds when sent. TH: เก็บ timestamp อุปกรณ์หน่วยมิลลิวินาทีเมื่อมี
  final DateTime
      timestamp; // EN: Store the acquisition or fallback receive time. TH: เก็บเวลาที่อ่านข้อมูลหรือเวลารับสำรอง

  double
      get motionMagnitude => // EN: Calculate the Euclidean magnitude of acceleration. TH: คำนวณ magnitude แบบ Euclidean ของความเร่ง
          sqrt((accelX * accelX) +
              (accelY * accelY) +
              (accelZ *
                  accelZ)); // EN: Combine the three axis squares before taking the square root. TH: รวมกำลังสองของสามแกนก่อนหารากที่สอง

  double
      get gyroMagnitude => // EN: Calculate the Euclidean magnitude of angular rate. TH: คำนวณ magnitude แบบ Euclidean ของอัตราการหมุน
          sqrt((gyroX * gyroX) +
              (gyroY * gyroY) +
              (gyroZ *
                  gyroZ)); // EN: Combine the three angular-rate axis squares. TH: รวมกำลังสองของอัตราการหมุนทั้งสามแกน

  int get stressLevel => gsr
      .clamp(0, 100)
      .round(); // EN: Clamp the legacy GSR-derived display score to 0–100; this is not a validated stress classifier. TH: จำกัดคะแนนแสดงผลจาก GSR รุ่นเก่าไว้ 0–100 ซึ่งไม่ใช่ตัวจำแนกความเครียดที่ผ่านการยืนยัน

  factory SensorData.fromJson(Map<String, dynamic> json) {
    // EN: Parse a persisted or network-provided sensor object. TH: แปลง object sensor จาก storage หรือ network
    return SensorData(
      // EN: Build the strongly typed model. TH: สร้าง model ที่ระบุชนิดข้อมูล
      heartRate: _num(json, 'heart_rate', 'heartRate')
          .round(), // EN: Accept snake_case and legacy camelCase heart-rate keys. TH: รองรับ key heart rate แบบ snake_case และ camelCase รุ่นเก่า
      spo2: _num(json, 'spo2')
          .round(), // EN: Parse SpO2 and use zero for missing or invalid numbers. TH: แปลง SpO2 และใช้ศูนย์เมื่อข้อมูลหายหรือไม่ถูกต้อง
      gsr: _num(json,
          'gsr'), // EN: Parse a bounded finite GSR number. TH: แปลง GSR ที่เป็น finite และอยู่ในขอบเขต
      temperature: _num(json,
          'temperature'), // EN: Parse a bounded finite temperature number. TH: แปลงอุณหภูมิที่เป็น finite และอยู่ในขอบเขต
      ecgRate: _num(json, 'ecg_rate', 'ecgRate')
          .round(), // EN: Accept both ECG-rate key styles. TH: รองรับ key ECG rate ทั้งสองรูปแบบ
      ecgRrInterval: _num(json, 'ecg_rr_interval',
          'ecgRrInterval'), // EN: Parse the optional RR interval. TH: แปลงช่วง RR ที่เป็นตัวเลือก
      ecgHrv: _num(json, 'ecg_hrv',
          'ecgHrv'), // EN: Parse the optional ECG HRV value. TH: แปลงค่า ECG HRV ที่เป็นตัวเลือก
      accelX: _num(json, 'accel_x',
          'accelX'), // EN: Parse acceleration X with a camelCase fallback. TH: แปลงความเร่ง X พร้อม key camelCase สำรอง
      accelY: _num(json, 'accel_y',
          'accelY'), // EN: Parse acceleration Y with a camelCase fallback. TH: แปลงความเร่ง Y พร้อม key camelCase สำรอง
      accelZ: _num(json, 'accel_z',
          'accelZ'), // EN: Parse acceleration Z with a camelCase fallback. TH: แปลงความเร่ง Z พร้อม key camelCase สำรอง
      gyroX: _num(json, 'gyro_x',
          'gyroX'), // EN: Parse angular rate X with a camelCase fallback. TH: แปลงอัตราการหมุน X พร้อม key camelCase สำรอง
      gyroY: _num(json, 'gyro_y',
          'gyroY'), // EN: Parse angular rate Y with a camelCase fallback. TH: แปลงอัตราการหมุน Y พร้อม key camelCase สำรอง
      gyroZ: _num(json, 'gyro_z',
          'gyroZ'), // EN: Parse angular rate Z with a camelCase fallback. TH: แปลงอัตราการหมุน Z พร้อม key camelCase สำรอง
      rawRed: json['red_adc_mean'] is int
          ? json['red_adc_mean'] as int
          : null, // EN: Keep Red only when its JSON value is an integer. TH: เก็บ Red เมื่อค่า JSON เป็นจำนวนเต็มเท่านั้น
      rawIr: json['ir_adc_mean'] is int
          ? json['ir_adc_mean'] as int
          : null, // EN: Keep IR only when its JSON value is an integer. TH: เก็บ IR เมื่อค่า JSON เป็นจำนวนเต็มเท่านั้น
      deviceTimestampMs: json['device_timestamp_ms']
              is int // EN: Validate the optional device timestamp's runtime type. TH: ตรวจชนิดจริงของ timestamp อุปกรณ์ที่เป็นตัวเลือก
          ? json['device_timestamp_ms']
              as int // EN: Preserve an integer device timestamp. TH: คง timestamp อุปกรณ์ที่เป็นจำนวนเต็ม
          : null, // EN: Omit malformed or absent device timestamps. TH: เว้น timestamp ที่ผิดรูปหรือไม่มี
      timestamp: _parseTimestamp(json[
          'timestamp']), // EN: Preserve legacy missing-time behavior but reject supplied malformed timestamps. TH: คง fallback เวลาให้ข้อมูลรุ่นเก่า แต่ปฏิเสธ timestamp ที่ส่งมาแล้วผิดรูป
    ); // EN: Finish sensor-model construction. TH: จบการสร้าง sensor model
  } // EN: Finish JSON object parsing. TH: จบการแปลง JSON object

  factory SensorData.fromJsonString(String raw) {
    // EN: Decode a JSON string into a sensor model. TH: ถอดรหัสข้อความ JSON เป็น sensor model
    return SensorData.fromJson(jsonDecode(raw) as Map<String,
        dynamic>); // EN: Require a JSON object and parse its fields. TH: บังคับให้ JSON เป็น object แล้วแปลง field
  } // EN: Finish JSON string parsing. TH: จบการแปลงข้อความ JSON

  Map<String, dynamic> toJson() => {
        // EN: Serialize the model for persistence and API requests. TH: serialize model สำหรับ storage และคำขอ API
        'heart_rate':
            heartRate, // EN: Serialize heart rate in the canonical API key. TH: serialize heart rate ด้วย key มาตรฐาน API
        'spo2': spo2, // EN: Serialize SpO2. TH: serialize SpO2
        'ecg_rate':
            ecgRate, // EN: Serialize ECG-derived rate. TH: serialize อัตราจาก ECG
        'ecg_rr_interval':
            ecgRrInterval, // EN: Serialize the ECG RR interval. TH: serialize ช่วง RR จาก ECG
        'ecg_hrv':
            ecgHrv, // EN: Serialize ECG-derived HRV. TH: serialize HRV จาก ECG
        'gsr': gsr, // EN: Serialize the GSR value. TH: serialize ค่า GSR
        'temperature':
            temperature, // EN: Serialize temperature. TH: serialize อุณหภูมิ
        'accel_x':
            accelX, // EN: Serialize acceleration X. TH: serialize ความเร่ง X
        'accel_y':
            accelY, // EN: Serialize acceleration Y. TH: serialize ความเร่ง Y
        'accel_z':
            accelZ, // EN: Serialize acceleration Z. TH: serialize ความเร่ง Z
        'gyro_x':
            gyroX, // EN: Serialize angular rate X. TH: serialize อัตราการหมุน X
        'gyro_y':
            gyroY, // EN: Serialize angular rate Y. TH: serialize อัตราการหมุน Y
        'gyro_z':
            gyroZ, // EN: Serialize angular rate Z. TH: serialize อัตราการหมุน Z
        'red_adc_mean':
            rawRed, // EN: Serialize the optional raw Red ADC mean. TH: serialize ค่าเฉลี่ย ADC Red ดิบที่เป็นตัวเลือก
        'ir_adc_mean':
            rawIr, // EN: Serialize the optional raw IR ADC mean. TH: serialize ค่าเฉลี่ย ADC IR ดิบที่เป็นตัวเลือก
        'device_timestamp_ms':
            deviceTimestampMs, // EN: Serialize the optional device-clock timestamp. TH: serialize timestamp จากนาฬิกาอุปกรณ์ที่เป็นตัวเลือก
        'motion_magnitude':
            motionMagnitude, // EN: Include the derived acceleration magnitude. TH: ใส่ magnitude ความเร่งที่คำนวณแล้ว
        'gyro_magnitude':
            gyroMagnitude, // EN: Include the derived angular-rate magnitude. TH: ใส่ magnitude อัตราการหมุนที่คำนวณแล้ว
        'heartRate':
            heartRate, // EN: Preserve a legacy alias for older app consumers. TH: คง alias รุ่นเก่าให้ consumer เดิม
        'ecgRate':
            ecgRate, // EN: Preserve the ECG camelCase alias. TH: คง alias camelCase ของ ECG
        'ecgRrInterval':
            ecgRrInterval, // EN: Preserve the RR camelCase alias. TH: คง alias camelCase ของ RR
        'ecgHrv':
            ecgHrv, // EN: Preserve the HRV camelCase alias. TH: คง alias camelCase ของ HRV
        'accelX':
            accelX, // EN: Preserve the acceleration X alias. TH: คง alias ความเร่ง X
        'accelY':
            accelY, // EN: Preserve the acceleration Y alias. TH: คง alias ความเร่ง Y
        'accelZ':
            accelZ, // EN: Preserve the acceleration Z alias. TH: คง alias ความเร่ง Z
        'gyroX':
            gyroX, // EN: Preserve the angular-rate X alias. TH: คง alias อัตราการหมุน X
        'gyroY':
            gyroY, // EN: Preserve the angular-rate Y alias. TH: คง alias อัตราการหมุน Y
        'gyroZ':
            gyroZ, // EN: Preserve the angular-rate Z alias. TH: คง alias อัตราการหมุน Z
        'timestamp': timestamp
            .toIso8601String(), // EN: Serialize the snapshot time as ISO-8601. TH: serialize เวลาของ snapshot เป็น ISO-8601
      }; // EN: Finish JSON serialization. TH: จบการ serialize JSON
} // EN: Finish the sensor-data model. TH: จบ model ข้อมูล sensor

double _num(Map<String, dynamic> json, String key, [String? fallbackKey]) {
  // EN: Parse finite bounded numbers and reject malformed supplied values. TH: แปลงเลข finite ที่อยู่ในขอบเขตและปฏิเสธค่าที่ส่งมาแต่ผิดรูป
  final value = json[key] ??
      (fallbackKey == null
          ? null
          : json[
              fallbackKey]); // EN: Prefer the canonical key and then the optional legacy key. TH: ใช้ key มาตรฐานก่อนแล้วจึงใช้ key รุ่นเก่าเมื่อมี
  if (value == null) {
    // EN: Distinguish an absent field from a malformed value. TH: แยก field ที่ไม่มีออกจากค่าที่ผิดรูป
    return 0; // EN: Preserve the existing default for unavailable measurements. TH: คงค่าเริ่มต้นเดิมสำหรับค่าที่ไม่มี
  } // EN: Finish missing-value handling. TH: จบการจัดการค่าที่ไม่มี
  if (value is num) {
    // EN: Handle decoded JSON numbers directly. TH: จัดการตัวเลขที่ถอดจาก JSON แล้ว
    final number = value
        .toDouble(); // EN: Normalize integer and decimal values to double. TH: แปลงจำนวนเต็มและทศนิยมเป็น double รูปแบบเดียว
    if (!number.isFinite || number.abs() > _maxFiniteSensorValue) {
      // EN: Reject infinity, NaN, and extreme magnitudes. TH: ปฏิเสธ infinity, NaN และค่าขนาดเกินขอบเขต
      throw FormatException(
          'Sensor field $key is not a finite bounded number.'); // EN: Mark the containing record as malformed. TH: ระบุว่า record ที่ครอบ field นี้ผิดรูป
    } // EN: Finish native-number validation. TH: จบการตรวจตัวเลข JSON
    return number; // EN: Return a valid bounded number. TH: คืนตัวเลขที่ถูกต้องและอยู่ในขอบเขต
  } // EN: Finish handling native JSON numbers. TH: จบการจัดการตัวเลข JSON
  if (value is String) {
    // EN: Allow numeric strings from older persisted records. TH: รองรับ string ตัวเลขจาก record รุ่นเก่า
    final parsed = double.tryParse(
        value); // EN: Parse without throwing for malformed text. TH: แปลงโดยไม่ throw เมื่อข้อความผิดรูป
    if (parsed == null ||
        !parsed.isFinite ||
        parsed.abs() > _maxFiniteSensorValue) {
      // EN: Reject malformed strings and unsafe numeric values. TH: ปฏิเสธ string ผิดรูปและตัวเลขที่ไม่ปลอดภัย
      throw FormatException(
          'Sensor field $key is not a finite bounded number.'); // EN: Let storage skip the invalid record. TH: ให้ storage ข้าม record ที่ไม่ถูกต้อง
    } // EN: Finish string-number validation. TH: จบการตรวจ string ตัวเลข
    return parsed; // EN: Return a valid bounded parsed value. TH: คืนค่าที่แปลงแล้วและอยู่ในขอบเขต
  } // EN: Finish handling legacy numeric strings. TH: จบการจัดการ string ตัวเลขรุ่นเก่า
  throw FormatException(
      'Sensor field $key has an unsupported value type.'); // EN: Reject booleans, objects, and unsupported values. TH: ปฏิเสธ boolean, object และค่าชนิดอื่นที่ไม่รองรับ
} // EN: Finish safe finite-number parsing. TH: จบการแปลงเลข finite อย่างปลอดภัย

DateTime _parseTimestamp(Object? value) {
  // EN: Parse optional event time without disguising malformed timestamps. TH: แปลงเวลา event โดยไม่กลบ timestamp ที่ผิดรูป
  if (value == null) {
    // EN: Preserve compatibility with legacy entries that omitted time. TH: รองรับ entry รุ่นเก่าที่ไม่มีเวลา
    return DateTime
        .now(); // EN: Use current local time only for a missing field. TH: ใช้เวลาปัจจุบันเฉพาะกรณี field หาย
  } // EN: Finish the missing-timestamp branch. TH: จบกรณี timestamp ไม่มี
  if (value is! String) {
    // EN: Require the serialized ISO-8601 string format. TH: บังคับรูปแบบ string ISO-8601 ที่ serialize ไว้
    throw const FormatException(
        'Sensor timestamp must be a string.'); // EN: Reject unexpected timestamp types. TH: ปฏิเสธชนิด timestamp ที่ไม่คาดหมาย
  } // EN: Finish timestamp type validation. TH: จบการตรวจชนิด timestamp
  final parsed = DateTime.tryParse(
      value); // EN: Parse without leaking a low-level parser exception. TH: แปลงโดยไม่ส่ง parser exception ระดับล่างออกไป
  if (parsed == null) {
    // EN: Detect malformed timestamp text. TH: ตรวจข้อความ timestamp ที่ผิดรูป
    throw const FormatException(
        'Sensor timestamp is invalid.'); // EN: Allow storage to skip the malformed record. TH: ให้ storage ข้าม record ที่ผิดรูป
  } // EN: Finish timestamp parsing validation. TH: จบการตรวจ timestamp
  return parsed; // EN: Return the parsed source time. TH: คืนเวลาจากต้นทางที่แปลงแล้ว
} // EN: Finish timestamp parsing. TH: จบการแปลง timestamp
