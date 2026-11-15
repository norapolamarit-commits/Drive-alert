import 'dart:async'; // EN: Cancel response streams after their total deadline. TH: ยกเลิก response stream เมื่อเกิน deadline รวม
import 'dart:convert'; // EN: Encode requests and decode JSON responses. TH: เข้ารหัสคำขอและถอดรหัส JSON ตอบกลับ
import 'dart:typed_data'; // EN: Buffer only bounded response bytes. TH: buffer เฉพาะ byte ของ response ที่อยู่ในเพดาน

import 'package:flutter/foundation.dart'; // EN: Restrict development HTTP and debug-only diagnostics. TH: จำกัด HTTP แบบ development และข้อความ debug
import 'package:http/http.dart'
    as http; // EN: Send HTTPS requests through an injectable HTTP client. TH: ส่ง HTTPS ผ่าน HTTP client ที่ฉีดทดสอบได้

import '../models/alert_record.dart'; // EN: Serialize alert records for the API. TH: แปลง alert record สำหรับส่ง API
import '../models/risk_result.dart'; // EN: Serialize the current risk result. TH: แปลงผล risk ปัจจุบัน
import '../models/sensor_data.dart'; // EN: Serialize sensor measurements. TH: แปลงค่าการวัด sensor

/// Advice returned by `/advice`; it is guidance, not a diagnosis. / คำแนะนำจาก `/advice` ซึ่งไม่ใช่การวินิจฉัย
class AdviceResult {
  // EN: Represent the bounded advice response fields. TH: เก็บ field คำแนะนำที่รับจาก server
  const AdviceResult({
    // EN: Create an immutable advice value. TH: สร้างค่าคำแนะนำที่แก้ไขภายหลังไม่ได้
    required this.advice, // EN: Require the primary advice text. TH: บังคับให้มีข้อความคำแนะนำหลัก
    this.cause =
        '', // EN: Default an omitted cause to empty text. TH: กำหนด cause ว่างเมื่อไม่มีข้อมูล
    this.disclaimer =
        '', // EN: Default an omitted disclaimer to empty text. TH: กำหนด disclaimer ว่างเมื่อไม่มีข้อมูล
    this.mode =
        '', // EN: Default an omitted response mode to empty text. TH: กำหนด mode ว่างเมื่อไม่มีข้อมูล
  }); // EN: Finish constructing the immutable result. TH: จบการสร้างผลลัพธ์แบบ immutable

  final String
      advice; // EN: Store the user-facing advice. TH: เก็บคำแนะนำที่แสดงให้ผู้ใช้
  final String
      cause; // EN: Store an optional explanation of cause. TH: เก็บคำอธิบายสาเหตุเมื่อมี
  final String
      disclaimer; // EN: Store an optional safety disclaimer. TH: เก็บข้อความข้อจำกัดเพื่อความปลอดภัย
  final String
      mode; // EN: Store the server response mode, such as fallback. TH: เก็บโหมดตอบกลับ เช่น fallback
} // EN: Finish the advice response model. TH: จบ model ผลลัพธ์คำแนะนำ

enum AccountDeletionResult {
  // EN: Enumerate safe account-deletion outcomes. TH: กำหนดผลลัพธ์การลบบัญชีที่ปลอดภัย
  deleted, // EN: The API confirmed deletion. TH: API ยืนยันว่าลบแล้ว
  notConfigured, // EN: The server or endpoint is not configured. TH: server หรือ endpoint ยังไม่พร้อม
  failed, // EN: The request failed without exposing provider details. TH: คำขอล้มเหลวโดยไม่เปิดเผยรายละเอียด provider
  deletedLocalCleanupFailed, // EN: Remote deletion succeeded but at least one local cleanup step failed. TH: ลบฝั่ง server แล้วแต่ล้างข้อมูลในเครื่องบางส่วนไม่สำเร็จ
} // EN: Finish the account-deletion outcomes. TH: จบ enum ผลลบบัญชี

class CloudService {
  // EN: Own authenticated requests from the app to the cloud API. TH: รวมการเรียก API cloud แบบยืนยันตัวตนจากแอป
  CloudService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client ==
            null; // EN: Allow tests to inject a mock and track client ownership. TH: ให้ test ใส่ mock และติดตามเจ้าของ client

  static const int _maxBaseUrlChars =
      2048; // EN: Bound configured URL parsing and storage. TH: จำกัดความยาว URL ตั้งต้น
  static const int _maxBearerTokenChars =
      8192; // EN: Bound the credential placed in an HTTP header. TH: จำกัดความยาว credential ใน HTTP header
  static const int _maxEventBodyBytes = 32 *
      1024; // EN: Match the API cap for sensor and alert requests. TH: ให้ตรงกับเพดาน API สำหรับ sensor และ alert
  static const int _maxAiBodyBytes = 64 *
      1024; // EN: Match the API cap for advice requests. TH: ให้ตรงกับเพดาน API สำหรับ advice
  static const int _maxAdviceTextChars =
      8000; // EN: Bound each returned text field. TH: จำกัดความยาว field ข้อความที่ตอบกลับ
  static const int _maxAdviceResponseBytes = 32 *
      1024; // EN: Bound memory used to receive advice JSON. TH: จำกัดหน่วยความจำที่ใช้รับ JSON advice

  final http.Client
      _client; // EN: Store the caller-provided or default HTTP client. TH: เก็บ HTTP client ที่รับมาหรือสร้างเป็นค่าเริ่มต้น
  final bool
      _ownsClient; // EN: Close only clients created by this service. TH: ปิดเฉพาะ client ที่ service นี้สร้าง

  // EN: Read a streaming response with a byte cap and strict UTF-8 decoding.
  // TH: อ่าน response แบบ stream โดยจำกัด byte และถอดรหัส UTF-8 แบบเข้มงวด
  static Future<String?> _readBoundedResponse(
    http.StreamedResponse response, {
    required int maxBytes,
    required Duration timeout,
  }) async {
    final iterator = StreamIterator<List<int>>(response
        .stream); // EN: Keep control of cancellation on timeout. TH: ควบคุมการยกเลิก stream เมื่อ timeout
    final bytes = BytesBuilder(
        copy:
            false); // EN: Avoid an extra copy after collecting bounded chunks. TH: ลดการคัดลอกซ้ำหลังรวม chunk ที่จำกัดแล้ว
    var length =
        0; // EN: Count actual bytes independently of Content-Length. TH: นับ byte จริงโดยไม่เชื่อ Content-Length อย่างเดียว
    final stopwatch = Stopwatch()
      ..start(); // EN: Measure one total response deadline. TH: วัด deadline รวมของ response
    try {
      if (response.contentLength != null &&
          response.contentLength! > maxBytes) {
        return null; // EN: Reject oversized bodies; finally cancels their stream. TH: ปฏิเสธ body ใหญ่เกินและยกเลิก stream ใน finally
      }
      while (true) {
        // EN: Process one bounded response chunk at a time. TH: ประมวลผล response ทีละ chunk ภายใต้เพดาน
        final remaining = timeout -
            stopwatch
                .elapsed; // EN: Calculate time left before the total deadline. TH: คำนวณเวลาที่เหลือก่อน deadline รวม
        if (remaining <= Duration.zero) {
          return null; // EN: Stop when the total deadline has elapsed. TH: หยุดเมื่อหมดเวลาโดยรวม
        }
        final hasChunk = await iterator.moveNext().timeout(
            remaining); // EN: Wait only for the remaining deadline. TH: รอไม่เกินเวลาที่เหลือ
        if (!hasChunk) {
          break; // EN: Finish when the stream has no more data. TH: จบเมื่อ stream ไม่มีข้อมูลต่อ
        }
        final chunk = iterator
            .current; // EN: Access the next received byte chunk. TH: อ่าน byte chunk ที่เพิ่งได้รับ
        length += chunk
            .length; // EN: Accumulate the size received so far. TH: รวมขนาด byte ที่รับมาแล้ว
        if (length > maxBytes) {
          return null; // EN: Reject and cancel a response that exceeds its cap. TH: ปฏิเสธและยกเลิก response ที่เกินเพดาน
        }
        bytes.add(
            chunk); // EN: Buffer only chunks that remain under the cap. TH: buffer เฉพาะ chunk ที่ยังไม่เกินเพดาน
      }
      return utf8.decode(bytes.takeBytes(),
          allowMalformed:
              false); // EN: Reject malformed UTF-8. TH: ปฏิเสธ UTF-8 ที่ผิดรูป
    } on Object {
      return null; // EN: Fail closed on timeout, stream, or decoding errors. TH: ปฏิเสธเมื่อ timeout, stream หรือ decode ผิดพลาด
    } finally {
      await iterator
          .cancel(); // EN: Release the stream on success, size limit, or timeout. TH: ปิด stream เมื่อสำเร็จ เกินขนาด หรือ timeout
    }
  }

  // EN: Validate opaque server request IDs before including them in debug logs.
  // TH: ตรวจ request ID จาก server ก่อนนำไปใส่ debug log
  static String _safeRequestId(String? value) =>
      value != null && RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(value)
          ? value
          : 'unavailable';

  // EN: Release the owned network client when the application state is disposed.
  // TH: ปิด network client ที่ service เป็นเจ้าของเมื่อ state ของแอปถูก dispose
  void dispose() {
    if (_ownsClient) {
      _client
          .close(); // EN: Leave injected clients open for their test owner. TH: ไม่ปิด client ที่ test เป็นเจ้าของ
    }
  }

  // EN: Keep optional response metadata text-only and bounded.
  // TH: บังคับ metadata response แบบ optional ให้เป็นข้อความและจำกัดขนาด
  static String _boundedResponseField(Object? value) =>
      value is String && value.length <= 8000 ? value.trim() : '';

  Map<String, dynamic> _minimalDeviceProfile(Map<String, dynamic> profile) {
    // EN: Read only the device identifier needed to route and partition an event. TH: อ่านเฉพาะ device ID ที่จำเป็นต่อการจัด event
    final deviceId = profile[
        'deviceId']; // EN: Ignore names, age, and health details supplied in the profile. TH: ไม่ส่งชื่อ อายุ และข้อมูลสุขภาพจาก profile
    if (deviceId is! String ||
        deviceId.trim().isEmpty ||
        deviceId.length > 128) {
      // EN: Fail closed when the required device ID is absent or malformed. TH: ปฏิเสธแบบปลอดภัยเมื่อ device ID หายหรือผิดรูป
      return const <String,
          dynamic>{}; // EN: Let server validation reject the incomplete event. TH: ให้ server validation ปฏิเสธ event ที่ข้อมูลไม่ครบ
    } // EN: Finish device-ID validation. TH: จบการตรวจ device ID
    return <String, dynamic>{
      'deviceId': deviceId
    }; // EN: Transmit only the minimal device metadata. TH: ส่งเฉพาะ metadata อุปกรณ์ที่จำเป็น
  } // EN: Finish profile minimization. TH: จบการลดข้อมูล profile

  static Uri? _safeBaseUri(String value) {
    // EN: Accept only bounded HTTPS API base URLs. TH: รับเฉพาะ base URL API แบบ HTTPS ที่มีความยาวจำกัด
    final trimmed = value
        .trim(); // EN: Remove harmless surrounding whitespace before parsing. TH: ตัดช่องว่างรอบ URL ก่อน parse
    if (trimmed.isEmpty || trimmed.length > _maxBaseUrlChars) {
      // EN: Reject empty or oversized configuration early. TH: ปฏิเสธค่าตั้งที่ว่างหรือยาวเกินทันที
      return null; // EN: Prevent requests to malformed configuration. TH: ป้องกันการส่งคำขอด้วยค่าตั้งผิดรูป
    } // EN: Finish the base-URL length check. TH: จบการตรวจความยาว base URL
    final uri = Uri.tryParse(
        trimmed); // EN: Parse without throwing on invalid user configuration. TH: parse โดยไม่ throw เมื่อค่าตั้งไม่ถูกต้อง
    if (uri ==
            null || // EN: Reject parse failures. TH: ปฏิเสธกรณี parse ไม่สำเร็จ
        uri.host
            .isEmpty || // EN: Require an explicit destination host. TH: บังคับให้มี host ปลายทาง
        uri.userInfo
            .isNotEmpty || // EN: Keep credentials out of the URL itself. TH: ห้ามฝัง credential ไว้ใน URL
        uri.hasQuery || // EN: Prevent unreviewed query parameters on the base URL. TH: ป้องกัน query ที่ไม่ได้ตรวจใน base URL
        uri.hasFragment) {
      // EN: Prevent fragments from being mistaken for server paths. TH: ป้องกัน fragment ถูกเข้าใจผิดเป็น path server
      return null; // EN: Fail closed for unsafe URL structure. TH: ปฏิเสธเมื่อโครงสร้าง URL ไม่ปลอดภัย
    } // EN: Finish structural URL validation. TH: จบการตรวจโครงสร้าง URL
    final localDebugHost = // EN: Identify loopback hosts permitted only in debug builds. TH: ระบุ loopback host ที่อนุญาตเฉพาะ debug build
        uri.host ==
                'localhost' || // EN: Allow the localhost hostname in debug mode. TH: อนุญาต hostname localhost ใน debug
            uri.host ==
                '127.0.0.1' || // EN: Allow the IPv4 loopback address in debug mode. TH: อนุญาต IPv4 loopback ใน debug
            uri.host ==
                '::1'; // EN: Allow the IPv6 loopback address in debug mode. TH: อนุญาต IPv6 loopback ใน debug
    if (uri.scheme !=
            'https' && // EN: Require TLS for all remote API calls. TH: บังคับ TLS สำหรับ API ภายนอกทั้งหมด
        !(kDebugMode && localDebugHost && uri.scheme == 'http')) {
      // EN: Permit plain HTTP only for a debug loopback server. TH: อนุญาต HTTP เฉพาะ loopback ใน debug
      return null; // EN: Refuse insecure remote destinations. TH: ปฏิเสธปลายทางภายนอกที่ไม่เข้ารหัส
    } // EN: Finish transport-security validation. TH: จบการตรวจความปลอดภัยของ transport
    return uri.replace(
        path: uri.path.replaceFirst(RegExp(r'/+$'),
            '')); // EN: Remove trailing path slashes so endpoint paths join consistently. TH: ตัด slash ท้าย path เพื่อประกอบ endpoint ให้สม่ำเสมอ
  } // EN: Finish safe base-URL parsing. TH: จบการ parse base URL ที่ปลอดภัย

  static String? _safeBearerToken(String value) {
    // EN: Bound and validate a bearer credential before adding it to headers. TH: จำกัดและตรวจ bearer credential ก่อนใส่ใน header
    final token = value
        .trim(); // EN: Remove surrounding whitespace without altering token contents. TH: ตัดช่องว่างรอบนอกโดยไม่แก้เนื้อหา token
    if (token.isEmpty || token.length > _maxBearerTokenChars) {
      // EN: Reject missing or excessive credentials. TH: ปฏิเสธ credential ที่ไม่มีหรือยาวเกิน
      return null; // EN: Do not send a missing or oversized token. TH: ไม่ส่ง token ที่ไม่มีหรือใหญ่เกิน
    } // EN: Finish credential-size validation. TH: จบการตรวจขนาด credential
    if (token.codeUnits.any((unit) => unit <= 0x20 || unit >= 0x7f)) {
      // EN: Reject whitespace/control and non-ASCII header characters. TH: ปฏิเสธช่องว่าง/control และอักขระ non-ASCII ใน header
      return null; // EN: Prevent malformed or injected Authorization headers. TH: ป้องกัน Authorization header ผิดรูปหรือถูกแทรก
    } // EN: Finish header-safe token validation. TH: จบการตรวจ token ให้ปลอดภัยต่อ header
    return token; // EN: Return the validated opaque bearer token. TH: คืน bearer token ที่ตรวจแล้วโดยไม่แก้ค่า
  } // EN: Finish bearer-token validation. TH: จบการตรวจ bearer token

  static String? _encodeBoundedJson(
    // EN: Serialize JSON and enforce the endpoint's UTF-8 body limit. TH: serialize JSON และบังคับเพดาน body UTF-8 ของ endpoint
    Map<String, dynamic>
        value, // EN: Receive the JSON-compatible request object. TH: รับ object คำขอที่แปลงเป็น JSON ได้
    int maximumBytes, // EN: Receive the endpoint-specific UTF-8 size cap. TH: รับเพดานขนาด UTF-8 เฉพาะ endpoint
  ) {
    // EN: Start bounded request serialization. TH: เริ่ม serialize คำขอแบบจำกัดขนาด
    try {
      // EN: Convert serialization errors into a rejected request. TH: แปลง serialization error เป็นการปฏิเสธคำขอ
      final encoded = jsonEncode(
          value); // EN: Encode the request map exactly once. TH: เข้ารหัส map คำขอเพียงครั้งเดียว
      if (utf8.encode(encoded).length > maximumBytes) {
        // EN: Measure wire-size bytes rather than Dart character count. TH: วัดขนาดเป็น byte ที่ส่งจริง ไม่ใช่จำนวนตัวอักษร Dart
        return null; // EN: Reject a body that exceeds the server contract. TH: ปฏิเสธ body ที่เกินข้อกำหนด server
      } // EN: Finish request-size enforcement. TH: จบการบังคับขนาดคำขอ
      return encoded; // EN: Return the validated JSON text for transmission. TH: คืนข้อความ JSON ที่ผ่านการตรวจเพื่อส่ง
    } catch (_) {
      // EN: Reject values that cannot be represented as JSON. TH: ปฏิเสธค่าที่เข้ารหัสเป็น JSON ไม่ได้
      return null; // EN: Fail closed without logging potentially sensitive data. TH: ปฏิเสธโดยไม่ log ข้อมูลที่อาจอ่อนไหว
    } // EN: Finish bounded JSON encoding. TH: จบการเข้ารหัส JSON แบบจำกัดขนาด
  } // EN: Finish JSON body validation. TH: จบการตรวจ JSON body

  Future<AccountDeletionResult> deleteAccount({
    // EN: Request deletion of the authenticated account. TH: ขอให้ลบบัญชีที่ยืนยันตัวตนแล้ว
    required String
        baseUrl, // EN: Receive the configured cloud API base URL. TH: รับ base URL ของ cloud API
    required String
        bearerToken, // EN: Receive the current user's access token. TH: รับ access token ของผู้ใช้ปัจจุบัน
  }) async {
    // EN: Perform the network operation asynchronously. TH: ทำ network operation แบบ asynchronous
    final uri = _safeBaseUri(
        baseUrl); // EN: Validate the destination before sending credentials. TH: ตรวจปลายทางก่อนส่ง credential
    final token = _safeBearerToken(
        bearerToken); // EN: Validate the credential before placing it in a header. TH: ตรวจ credential ก่อนใส่ header
    if (uri == null || token == null) {
      // EN: Reject invalid endpoint or credential without network access. TH: ปฏิเสธ endpoint หรือ credential ผิดโดยไม่เรียก network
      return AccountDeletionResult
          .notConfigured; // EN: Report that secure deletion is not configured. TH: รายงานว่ายังไม่ได้ตั้งค่าการลบอย่างปลอดภัย
    } // EN: Finish preflight validation. TH: จบการตรวจเบื้องต้น
    try {
      // EN: Convert transport failures into a stable result value. TH: แปลง network failure เป็นผลลัพธ์ที่แน่นอน
      final request = http.Request(
        'DELETE',
        uri.replace(path: '${uri.path}/account'),
      )
        ..followRedirects =
            false // EN: Keep the account token on the approved origin. TH: คง token บัญชีไว้ที่ origin ที่อนุมัติ
        ..headers['Authorization'] = 'Bearer $token';
      final response = await _client.send(request).timeout(
            const Duration(seconds: 20),
          );
      final responseText = await _readBoundedResponse(
        response,
        maxBytes: 4096,
        timeout: const Duration(seconds: 3),
      ); // EN: Read only a small bounded response to classify safe preflight errors. TH: อ่าน response ขนาดจำกัดเพื่อแยก error ก่อนเริ่มลบ
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // EN: Treat any successful HTTP status as deletion success. TH: ถือ status HTTP สำเร็จเป็นการลบสำเร็จ
        return AccountDeletionResult
            .deleted; // EN: Report successful account deletion. TH: รายงานว่าลบบัญชีสำเร็จ
      } // EN: Finish success-status handling. TH: จบการจัดการ status สำเร็จ
      if (response.statusCode == 503) {
        // EN: Only known pre-deletion checks are safe to call unconfigured; other 503s may follow partial deletion. TH: เรียกว่ายังไม่ตั้งค่าเฉพาะ error ก่อนเริ่มลบที่รู้จัก ส่วน 503 อื่นอาจเกิดหลังลบบางส่วน
        return _isKnownPreDeletionConfigurationFailure(responseText)
            ? AccountDeletionResult.notConfigured
            : AccountDeletionResult.failed;
      } // EN: Finish not-configured handling. TH: จบการจัดการกรณียังไม่พร้อม
      return AccountDeletionResult
          .failed; // EN: Hide provider details from the user-facing result. TH: ซ่อนรายละเอียด provider จากผลลัพธ์ที่แสดงผู้ใช้
    } catch (_) {
      // EN: Handle timeouts and transport errors without exposing request data. TH: จัดการ timeout/network error โดยไม่เปิดเผยข้อมูลคำขอ
      return AccountDeletionResult
          .failed; // EN: Report a generic failure for safe UI handling. TH: คืนผลล้มเหลวทั่วไปให้ UI จัดการ
    } // EN: Finish the account-deletion request. TH: จบคำขอลบบัญชี
  } // EN: Finish the account-deletion operation. TH: จบการทำงานลบบัญชี

  // EN: Match only server errors raised before any account records are deleted.
  // TH: จับคู่เฉพาะ error ที่ server ส่งก่อนลบ record ของบัญชี
  bool _isKnownPreDeletionConfigurationFailure(String? responseText) {
    if (responseText == null) return false;
    try {
      final decoded = jsonDecode(responseText);
      if (decoded is! Map<String, dynamic>) return false;
      const safeDetails = <String>{
        'Account deletion is not configured on this server.',
        'Persistent health-data storage is unavailable for account deletion.',
      };
      return safeDetails.contains(decoded['detail']);
    } on FormatException {
      return false;
    }
  }

  Future<bool> uploadSensor({
    // EN: Upload one sensor snapshot only when called by the consent-aware layer. TH: อัปโหลดข้อมูล sensor หนึ่งชุดเมื่อชั้นที่ตรวจ consent เรียกใช้
    required String
        baseUrl, // EN: Receive the cloud API base URL. TH: รับ base URL ของ cloud API
    required String
        bearerToken, // EN: Receive the authenticated user's access token. TH: รับ access token ของผู้ใช้ที่ยืนยันตัวตนแล้ว
    required SensorData
        sensorData, // EN: Receive the measurements being uploaded. TH: รับค่าการวัดที่จะอัปโหลด
    required RiskResult
        riskResult, // EN: Receive the corresponding risk result. TH: รับผล risk ที่สัมพันธ์กับข้อมูล
    required Map<String, dynamic>
        userProfile, // EN: Receive the profile metadata expected by the API. TH: รับ metadata profile ตาม schema API
    int?
        battery, // EN: Accept battery percentage only if the device reported it. TH: รับเปอร์เซ็นต์แบตเมื่ออุปกรณ์รายงานมาเท่านั้น
    required String
        bleStatus, // EN: Receive the BLE connection state. TH: รับสถานะการเชื่อมต่อ BLE
    required String
        sensorStatus, // EN: Receive the sensor-mode description. TH: รับคำอธิบายโหมด sensor
  }) async {
    // EN: Build and send the sensor event asynchronously. TH: สร้างและส่ง sensor event แบบ asynchronous
    return _post(
      // EN: Reuse the shared URL, token, JSON, and body-size guards. TH: ใช้ตัวตรวจ URL, token, JSON และขนาด body ร่วมกัน
      baseUrl:
          baseUrl, // EN: Pass the original base URL for strict validation. TH: ส่ง base URL ให้ตรวจแบบเข้มงวด
      path:
          '/sensor', // EN: Select the fixed sensor endpoint. TH: เลือก endpoint sensor ที่กำหนดตายตัว
      bearerToken:
          bearerToken, // EN: Pass the access token for safe validation. TH: ส่ง access token ให้ตรวจความปลอดภัย
      body: {
        // EN: Construct only the sensor fields supported by the API. TH: สร้างเฉพาะ field sensor ที่ API รองรับ
        'timestamp': sensorData.timestamp
            .toIso8601String(), // EN: Serialize the measurement time in ISO-8601 format. TH: แปลงเวลาวัดเป็นรูปแบบ ISO-8601
        'sensorData': sensorData
            .toJson(), // EN: Serialize the sensor values. TH: แปลงค่าจาก sensor
        'riskResult': riskResult
            .toJson(), // EN: Serialize the associated risk result. TH: แปลงผล risk ที่เกี่ยวข้อง
        'userProfile': _minimalDeviceProfile(
            userProfile), // EN: Send only the device ID; the server derives user identity from the bearer token. TH: ส่งเฉพาะ device ID ส่วน server ระบุผู้ใช้จาก bearer token
        if (battery != null)
          'battery':
              battery, // EN: Omit battery instead of inventing a missing value. TH: ไม่ส่ง battery แทนการเดาค่าที่ไม่มี
        'bleStatus':
            bleStatus, // EN: Include the current BLE status. TH: ใส่สถานะ BLE ปัจจุบัน
        'sensorStatus':
            sensorStatus, // EN: Include the current sensor status. TH: ใส่สถานะ sensor ปัจจุบัน
      }, // EN: Finish the sensor event body. TH: จบ body ของ sensor event
    ); // EN: Return whether the API accepted the event. TH: คืนผลว่า API รับ event หรือไม่
  } // EN: Finish sensor upload. TH: จบการอัปโหลด sensor

  Future<bool> uploadAlert({
    // EN: Upload one alert record for the authenticated user. TH: อัปโหลด alert record หนึ่งรายการของผู้ใช้ที่ยืนยันตัวตน
    required String
        baseUrl, // EN: Receive the cloud API base URL. TH: รับ base URL ของ cloud API
    required String
        bearerToken, // EN: Receive the authenticated user's access token. TH: รับ access token ของผู้ใช้ที่ยืนยันตัวตน
    required AlertRecord
        alert, // EN: Receive the alert to serialize. TH: รับ alert ที่ต้องแปลงข้อมูล
    required Map<String, dynamic>
        userProfile, // EN: Receive required profile metadata. TH: รับ metadata profile ที่จำเป็น
  }) async {
    // EN: Build and send the alert asynchronously. TH: สร้างและส่ง alert แบบ asynchronous
    return _post(
      // EN: Reuse shared validation and transport handling. TH: ใช้การตรวจและส่งข้อมูลส่วนกลาง
      baseUrl:
          baseUrl, // EN: Pass the base URL for validation. TH: ส่ง base URL ไปตรวจ
      path:
          '/alert', // EN: Select the fixed alert endpoint. TH: เลือก endpoint alert ที่กำหนดตายตัว
      bearerToken:
          bearerToken, // EN: Pass the token for safe validation. TH: ส่ง token ไปตรวจความปลอดภัย
      body: {
        // EN: Construct the API alert payload. TH: สร้าง payload alert สำหรับ API
        'alert': alert
            .toJson(), // EN: Serialize the alert model. TH: แปลง alert model
        'userProfile': _minimalDeviceProfile(
            userProfile), // EN: Send only the device ID and keep personal profile fields on-device. TH: ส่งเฉพาะ device ID และเก็บข้อมูลส่วนตัวไว้ในเครื่อง
      }, // EN: Finish the alert body. TH: จบ body ของ alert
    ); // EN: Return whether the API accepted the alert. TH: คืนผลว่า API รับ alert หรือไม่
  } // EN: Finish alert upload. TH: จบการอัปโหลด alert

  /// Ask the advice endpoint; return null when unavailable. / ขอคำแนะนำจาก endpoint และคืน null เมื่อใช้งานไม่ได้
  Future<AdviceResult?> fetchAdvice({
    // EN: Request advice without exposing profile/history. TH: ขอคำแนะนำโดยไม่ส่ง profile หรือ history
    required String
        baseUrl, // EN: Receive the configured cloud API base URL. TH: รับ base URL ของ cloud API
    required String
        status, // EN: Receive the current application status. TH: รับสถานะปัจจุบันของแอป
    required String
        alertLevel, // EN: Receive the current alert level. TH: รับระดับ alert ปัจจุบัน
    required String
        sensor, // EN: Receive only the sensor summary intended for advice. TH: รับเฉพาะสรุป sensor ที่ต้องใช้ขอคำแนะนำ
    required String
        bearerToken, // EN: Receive the signed-in user's access token. TH: รับ access token ของผู้ใช้ที่ลงชื่อเข้าใช้
  }) async {
    // EN: Perform the advice request asynchronously. TH: ทำคำขอ advice แบบ asynchronous
    final baseUri = _safeBaseUri(
        baseUrl); // EN: Validate the remote destination before sending private context. TH: ตรวจปลายทางก่อนส่งบริบทส่วนตัว
    final token = _safeBearerToken(
        bearerToken); // EN: Validate the credential before adding the header. TH: ตรวจ credential ก่อนใส่ header
    if (baseUri == null || token == null) {
      // EN: Abstain if URL or authentication is invalid. TH: งดส่งเมื่อ URL หรือการยืนยันตัวตนไม่ถูกต้อง
      return null; // EN: Do not send a request without a safe destination and credential. TH: ห้ามส่งคำขอเมื่อปลายทางหรือ credential ไม่ปลอดภัย
    } // EN: Finish preflight rejection. TH: จบการปฏิเสธก่อนส่ง
    final requestBody = _encodeBoundedJson({
      // EN: Encode and size-check the advice request before transport. TH: เข้ารหัสและตรวจขนาดคำขอ advice ก่อนส่ง
      'status':
          status, // EN: Include the current app status. TH: ใส่สถานะแอปปัจจุบัน
      'alertLevel':
          alertLevel, // EN: Include the current alert level. TH: ใส่ระดับ alert ปัจจุบัน
      'sensor':
          sensor, // EN: Include the explicitly selected sensor summary. TH: ใส่สรุป sensor ที่เลือกส่ง
    }, _maxAiBodyBytes); // EN: Apply the server's 64 KiB AI-body limit. TH: ใช้เพดาน AI body 64 KiB ให้ตรงกับ server
    if (requestBody == null) {
      // EN: Refuse oversized or unserializable advice payloads. TH: ปฏิเสธ payload advice ที่ใหญ่เกินหรือ serialize ไม่ได้
      return null; // EN: Keep invalid requests off the network. TH: กันคำขอผิดออกจาก network
    } // EN: Finish request-body validation. TH: จบการตรวจ request body
    try {
      // EN: Convert network, timeout, and response errors into null. TH: แปลง network, timeout และ response error เป็น null
      final request = http.Request(
        'POST',
        baseUri.replace(path: '${baseUri.path}/advice'),
      )
        ..followRedirects =
            false // EN: Prevent token and advice context from following redirects. TH: กัน token และบริบทคำแนะนำไม่ให้ตาม redirect
        ..headers.addAll({
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $token',
        })
        ..body = requestBody;
      final response = await _client.send(request).timeout(
            const Duration(seconds: 20),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // EN: Reject non-success HTTP responses. TH: ปฏิเสธ response HTTP ที่ไม่สำเร็จ
        await _readBoundedResponse(
          response,
          maxBytes: 4096,
          timeout: const Duration(seconds: 2),
        ); // EN: Drain only a bounded error body without exposing it. TH: อ่าน error body ทิ้งในขอบเขตโดยไม่เปิดเผยเนื้อหา
        if (kDebugMode) {
          // EN: Log status and opaque server request ID only. TH: log เฉพาะ status และ request ID แบบสุ่มจาก server
          final requestId = _safeRequestId(response.headers[
              'x-request-id']); // EN: Sanitize the server correlation ID. TH: sanitize ID สำหรับค้น server log
          debugPrint(
              'Cloud POST /advice failed: HTTP ${response.statusCode}; request_id=$requestId'); // EN: Keep credentials and health values out of diagnostics. TH: ไม่ใส่ credential หรือค่าสุขภาพใน log
        } // EN: Finish safe failure logging. TH: จบการ log error แบบปลอดภัย
        return null; // EN: Let the caller use its local fallback. TH: ให้ caller ใช้ fallback ภายใน
      } // EN: Finish HTTP status validation. TH: จบการตรวจ HTTP status
      final responseText = await _readBoundedResponse(
        response,
        maxBytes: _maxAdviceResponseBytes,
        timeout: const Duration(seconds: 5),
      );
      if (responseText == null) return null;
      final decoded = jsonDecode(
          responseText); // EN: Decode bounded API JSON. TH: ถอดรหัส JSON API ที่ผ่านการจำกัดขนาด
      if (decoded is! Map<String, dynamic>) {
        // EN: Reject an unexpected response shape. TH: ปฏิเสธรูปแบบ response ที่ไม่ใช่ object
        return null; // EN: Do not pass an invalid response into UI state. TH: ไม่ส่ง response ผิดรูปเข้า state ของ UI
      } // EN: Finish response-shape validation. TH: จบการตรวจรูปแบบ response
      final rawAdvice = decoded['advice'];
      if (rawAdvice is! String || rawAdvice.length > _maxAdviceTextChars) {
        return null; // EN: Require bounded text, not coerced arbitrary JSON. TH: บังคับข้อความที่จำกัดขนาด ไม่แปลง JSON ชนิดอื่น
      }
      final advice = rawAdvice.trim();
      if (advice.isEmpty) {
        // EN: Reject empty advice instead of displaying a blank answer. TH: ปฏิเสธ advice ว่างแทนการแสดงคำตอบเปล่า
        return null; // EN: Keep the caller on its local fallback. TH: ให้ caller ใช้ fallback ภายในต่อ
      } // EN: Finish advice-content validation. TH: จบการตรวจเนื้อหา advice
      return AdviceResult(
        // EN: Build the typed response from validated JSON fields. TH: สร้างผลลัพธ์ชนิดชัดเจนจาก JSON ที่ตรวจแล้ว
        advice:
            advice, // EN: Store the required advice text. TH: เก็บข้อความ advice ที่จำเป็น
        cause: _boundedResponseField(decoded['cause']),
        disclaimer: _boundedResponseField(decoded['disclaimer']),
        mode: _boundedResponseField(decoded['mode']),
      ); // EN: Finish constructing the advice result. TH: จบการสร้างผลลัพธ์ advice
    } catch (error) {
      // EN: Catch malformed JSON and transport exceptions. TH: จับ JSON ผิดรูปและ exception จาก network
      if (kDebugMode) {
        // EN: Keep diagnostics out of release builds. TH: จำกัด diagnostics ไว้เฉพาะ debug build
        debugPrint(
            'Cloud POST /advice failed: ${error.runtimeType}'); // EN: Log only the exception type, never its contents. TH: log เฉพาะชนิด exception ไม่ log เนื้อหา
      } // EN: Finish safe exception logging. TH: จบการ log exception แบบปลอดภัย
      return null; // EN: Let the caller fall back without exposing the failure details. TH: ให้ caller ใช้ fallback โดยไม่เปิดเผยรายละเอียด error
    } // EN: Finish advice request handling. TH: จบการจัดการคำขอ advice
  } // EN: Finish the advice operation. TH: จบการทำงานขอ advice

  Future<bool> _post({
    // EN: Send one bounded event to an explicitly allowed API route. TH: ส่ง event แบบจำกัดขนาดไปยัง route API ที่อนุญาต
    required String
        baseUrl, // EN: Receive the API base URL for validation. TH: รับ base URL ไปตรวจ
    required String
        path, // EN: Receive the endpoint path, which is checked against a fixed allowlist. TH: รับ path endpoint ซึ่งจะตรวจด้วย allowlist ตายตัว
    required String
        bearerToken, // EN: Receive the authenticated user's access token. TH: รับ access token ของผู้ใช้ที่ยืนยันตัวตนแล้ว
    required Map<String, dynamic>
        body, // EN: Receive the event payload to encode. TH: รับ payload event เพื่อเข้ารหัส
  }) async {
    // EN: Perform the upload asynchronously. TH: ทำการอัปโหลดแบบ asynchronous
    if (path != '/sensor' && path != '/alert') {
      // EN: Restrict this helper to its intended event routes. TH: จำกัด helper นี้ให้ใช้กับ route event ที่กำหนดเท่านั้น
      return false; // EN: Prevent accidental requests to arbitrary paths. TH: ป้องกันการส่งไป path อื่นโดยไม่ตั้งใจ
    } // EN: Finish endpoint allowlist check. TH: จบการตรวจ endpoint allowlist
    final baseUri = _safeBaseUri(
        baseUrl); // EN: Validate the destination URL. TH: ตรวจ URL ปลายทาง
    final token = _safeBearerToken(
        bearerToken); // EN: Validate the bearer credential. TH: ตรวจ bearer credential
    if (baseUri == null || token == null) {
      // EN: Refuse network access when preconditions fail. TH: งด network เมื่อเงื่อนไขก่อนส่งไม่ผ่าน
      return false; // EN: Do not transmit data without a safe URL and token. TH: ไม่ส่งข้อมูลเมื่อ URL หรือ token ไม่ปลอดภัย
    } // EN: Finish preflight rejection. TH: จบการปฏิเสธก่อนส่ง
    final requestBody = _encodeBoundedJson(body,
        _maxEventBodyBytes); // EN: Match the event payload size to the server's 32 KiB cap. TH: จำกัด event payload ให้ตรงกับเพดาน server 32 KiB
    if (requestBody == null) {
      // EN: Reject oversize or unserializable event data. TH: ปฏิเสธข้อมูล event ที่ใหญ่เกินหรือ serialize ไม่ได้
      return false; // EN: Keep invalid event data off the network. TH: กันข้อมูล event ที่ผิดออกจาก network
    } // EN: Finish event-body validation. TH: จบการตรวจ event body
    try {
      // EN: Convert transport errors into a stable false result. TH: แปลง network error เป็นผล false ที่แน่นอน
      final request = http.Request(
        'POST',
        baseUri.replace(path: '${baseUri.path}$path'),
      )
        ..followRedirects =
            false // EN: Prevent health events and tokens from following redirects. TH: กัน event สุขภาพและ token ไม่ให้ตาม redirect
        ..headers.addAll({
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $token',
        })
        ..body = requestBody;
      final response = await _client.send(request).timeout(
            const Duration(seconds: 4),
          );
      final succeeded = response.statusCode >= 200 &&
          response.statusCode <
              300; // EN: Convert successful HTTP status codes into a boolean. TH: แปลง HTTP status สำเร็จเป็น boolean
      if (!succeeded && kDebugMode) {
        // EN: Log status and the server's opaque request ID, never the body or token. TH: log status และ request ID แบบสุ่มจาก server โดยไม่ log body หรือ token
        final requestId = _safeRequestId(response.headers[
            'x-request-id']); // EN: Sanitize the API correlation ID. TH: sanitize ID สำหรับค้น log จาก API
        debugPrint(
            'Cloud POST $path failed: HTTP ${response.statusCode}; request_id=$requestId'); // EN: Keep diagnostics useful without exposing request contents. TH: ให้ log ใช้วินิจฉัยได้โดยไม่เปิดเผยเนื้อหาคำขอ
      } // EN: Finish event-upload diagnostics. TH: จบ diagnostics การ upload event
      await _readBoundedResponse(
        response,
        maxBytes: 4096,
        timeout: const Duration(seconds: 2),
      ); // EN: Drain only a bounded response to release the connection. TH: อ่าน response ทิ้งแบบจำกัดเพื่อคืน connection
      return succeeded; // EN: Report whether the cloud accepted the event. TH: คืนผลว่า cloud รับ event หรือไม่
    } catch (error) {
      // EN: Catch timeouts and HTTP transport failures. TH: จับ timeout และความล้มเหลวของ HTTP transport
      if (kDebugMode) {
        // EN: Keep diagnostics out of release builds. TH: จำกัด diagnostics ไว้เฉพาะ debug build
        debugPrint(
            'Cloud POST $path failed: ${error.runtimeType}'); // EN: Log exception type only to avoid leaking private values. TH: log เฉพาะชนิด exception เพื่อกันข้อมูลส่วนตัวรั่ว
      } // EN: Finish safe exception logging. TH: จบการ log exception แบบปลอดภัย
      return false; // EN: Report a generic failure for retry/fallback handling. TH: คืนผลล้มเหลวทั่วไปให้ระบบ retry/fallback
    } // EN: Finish event-upload handling. TH: จบการจัดการ upload event
  } // EN: Finish the shared event POST helper. TH: จบ helper POST event ส่วนกลาง
} // EN: Finish the authenticated cloud API client. TH: จบ client สำหรับเรียก cloud API แบบยืนยันตัวตน
