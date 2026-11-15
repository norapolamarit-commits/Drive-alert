import 'dart:convert'; // EN: Decode only the public role claim in legacy JWT project keys. TH: ถอดรหัสเฉพาะ role สาธารณะใน project key แบบ JWT เดิม
import 'dart:io'; // EN: Read build-time values and return a failure code without printing them. TH: อ่านค่าตอน build และคืนรหัสผิดพลาดโดยไม่แสดงค่า

// EN: Keep deployment URL checks independent of Flutter package initialization.
// TH: แยกการตรวจ URL ตอน deploy ออกจากการเริ่ม package ของ Flutter
bool _validHttpsOrigin(String value) {
  // EN: Accept a bare HTTPS origin only. TH: รับเฉพาะ origin HTTPS ที่ไม่มี path
  if (value.isEmpty || value != value.trim() || value.length > 2048) {
    // EN: Reject absent, padded, or oversized values. TH: ปฏิเสธค่าว่าง มีช่องว่างรอบ หรือยาวเกิน
    return false; // EN: Stop before URI parsing. TH: หยุดก่อน parse URI
  } // EN: Continue with a bounded value. TH: ดำเนินต่อเมื่อค่ามีขนาดจำกัด
  final uri = Uri.tryParse(
      value); // EN: Parse without throwing or exposing the input. TH: parse โดยไม่ throw หรือเปิดเผยค่า
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    // EN: Require a complete HTTPS origin. TH: บังคับ origin HTTPS ที่ครบ
    return false; // EN: Reject malformed or insecure URLs. TH: ปฏิเสธ URL ผิดรูปหรือไม่ปลอดภัย
  } // EN: Continue checking URL components. TH: ตรวจส่วนประกอบ URL ต่อ
  if (uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    // EN: Forbid credentials, routes, queries, and fragments. TH: ห้าม credential, path, query และ fragment
    return false; // EN: Prevent ambiguous build-time destinations. TH: ป้องกันปลายทางที่กำกวมตอน build
  } // EN: Continue with a bare origin. TH: ดำเนินต่อเมื่อเป็น origin ล้วน
  final host = uri.host
      .toLowerCase(); // EN: Normalize host comparisons. TH: ปรับ host เป็นตัวพิมพ์เล็กเพื่อเปรียบเทียบ
  if (host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host.endsWith('.localhost')) {
    // EN: Reject local endpoints in a public release. TH: ปฏิเสธปลายทางในเครื่องสำหรับ release สาธารณะ
    return false; // EN: Avoid deploying a client pointed at its own browser. TH: หลีกเลี่ยงการ deploy client ที่ชี้กลับเครื่องผู้ใช้
  } // EN: Finish loopback checks. TH: จบการตรวจ loopback
  return true; // EN: Accept a remote HTTPS origin. TH: รับ origin HTTPS ระยะไกล
} // EN: Complete URL validation. TH: จบการตรวจ URL

// EN: Match the app's accepted public Supabase key formats without verifying user identity.
// TH: ตรวจรูปแบบ public Supabase key ให้ตรงกับแอป โดยไม่ใช้แทนการยืนยันตัวผู้ใช้
bool _validPublicKey(String value) {
  // EN: Reject secret and malformed project keys. TH: ปฏิเสธ project key ที่เป็น secret หรือผิดรูป
  if (value.isEmpty ||
      value != value.trim() ||
      value.length > 8192 ||
      value.codeUnits.any((unit) => unit <= 0x20 || unit >= 0x7f)) {
    // EN: Bound length and allow printable ASCII only. TH: จำกัดความยาวและรับเฉพาะ ASCII ที่พิมพ์ได้
    return false; // EN: Refuse unsafe configuration text. TH: ปฏิเสธข้อความ config ที่ไม่ปลอดภัย
  } // EN: Continue with a bounded key. TH: ดำเนินต่อเมื่อ key มีขนาดจำกัด
  if (value.startsWith('sb_publishable_')) {
    // EN: Recognize modern browser-safe project keys. TH: ตรวจ key สาธารณะรุ่นใหม่ที่ใช้ใน browser ได้
    return value.length >
        'sb_publishable_'
            .length; // EN: Require a nonempty suffix. TH: บังคับมีค่าต่อท้าย prefix
  } // EN: Fall through to legacy anon JWT validation. TH: ตรวจ JWT anon รุ่นเก่าต่อ
  final parts = value
      .split('.'); // EN: Separate legacy JWT segments. TH: แยกส่วน JWT รุ่นเก่า
  if (parts.length != 3 || parts.any((part) => part.isEmpty)) {
    // EN: Require three nonempty segments. TH: บังคับมีสามส่วนที่ไม่ว่าง
    return false; // EN: Reject malformed JWT-shaped values. TH: ปฏิเสธค่ารูป JWT ที่ผิด
  } // EN: Continue with the public payload claim. TH: ตรวจ claim ใน payload ต่อ
  try {
    // EN: Catch invalid base64, UTF-8, and JSON. TH: จับข้อผิดพลาด base64, UTF-8 และ JSON
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(
        parts[
            1])))); // EN: Read only the untrusted payload segment. TH: อ่านเฉพาะส่วน payload ที่ยังไม่เชื่อถือ
    return payload is Map<String, dynamic> &&
        payload['role'] ==
            'anon'; // EN: Accept only the public anon role. TH: รับเฉพาะ role anon สาธารณะ
  } on FormatException {
    // EN: Normalize a malformed project key. TH: จัดการ project key ที่ผิดรูป
    return false; // EN: Fail closed without echoing key bytes. TH: ปฏิเสธโดยไม่แสดงเนื้อหา key
  } // EN: Finish payload screening. TH: จบการตรวจ payload
} // EN: Complete public-key validation. TH: จบการตรวจ public key

void main() {
  // EN: Fail before compiling an unusable or misconfigured web app. TH: หยุดก่อน build เว็บที่ config ผิดและใช้ไม่ได้
  final authUrl = Platform.environment['DOZ_SUPABASE_URL'] ??
      ''; // EN: Read the public Auth origin. TH: อ่าน Auth origin สาธารณะ
  final publicKey = Platform.environment['DOZ_SUPABASE_PUBLISHABLE_KEY'] ??
      ''; // EN: Read the browser-safe key. TH: อ่าน key ที่ใช้ใน browser ได้
  final apiUrl = Platform.environment['VITAGAURD_CLOUD_BASE_URL'] ??
      'https://drive-alert.onrender.com'; // EN: Read or default the Cloud API origin. TH: อ่านหรือใช้ค่า Cloud API origin เริ่มต้น
  if (!_validHttpsOrigin(authUrl) ||
      !_validPublicKey(publicKey) ||
      !_validHttpsOrigin(apiUrl)) {
    // EN: Require all three build-time values to pass. TH: บังคับให้ค่าทั้งสามผ่านการตรวจ
    stderr.writeln(
        'Invalid public web configuration: use HTTPS origins and a Supabase publishable or anon key.'); // EN: Explain the fix without printing values. TH: แจ้งวิธีแก้โดยไม่แสดงค่า
    exitCode =
        2; // EN: Stop the Render build before publishing assets. TH: หยุด Render build ก่อนเผยแพร่ไฟล์
    return; // EN: Skip the success message on failure. TH: ไม่แสดงข้อความสำเร็จเมื่อผิด
  } // EN: Finish build configuration gate. TH: จบการตรวจ config ตอน build
  stdout.writeln(
      'Public web configuration validated.'); // EN: Confirm validation without disclosing a key. TH: ยืนยันการตรวจโดยไม่เปิดเผย key
} // EN: Complete the validation program. TH: จบโปรแกรมตรวจ config
