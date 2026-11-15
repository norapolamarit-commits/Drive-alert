import 'dart:convert'; // EN: Decode the public JWT payload only for privilege screening. TH: ถอดรหัส public JWT payload เพื่อตรวจระดับสิทธิ์เท่านั้น

import 'package:flutter/foundation.dart'; // EN: Detect release/debug build policy. TH: ตรวจนโยบาย build แบบ release/debug
import 'package:supabase_flutter/supabase_flutter.dart'; // EN: Use Supabase Auth SDK for user sessions. TH: ใช้ Supabase Auth SDK จัดการ session ผู้ใช้

const int _maxSupabaseConfigUrlChars =
    2048; // EN: Bound project URL parsing. TH: จำกัดความยาว URL ของ project
const int _maxSupabaseAppKeyChars =
    8192; // EN: Bound key validation and JWT payload decoding. TH: จำกัดการตรวจ key และ decode JWT payload

// EN: Accept only modern public keys or legacy JWTs whose payload role is anon.
// TH: รับเฉพาะ public key รุ่นใหม่หรือ JWT เดิมที่ payload ระบุ role เป็น anon
bool _isAllowedSupabaseAppKey(String key) {
  // EN: Screen app configuration keys for privileged roles. TH: คัดกรอง key ใน app ว่ามี role สูงหรือไม่
  final normalized = key
      .trim(); // EN: Ignore surrounding configuration whitespace. TH: ตัดช่องว่างรอบ config
  if (normalized.isEmpty ||
      normalized.length > _maxSupabaseAppKeyChars ||
      normalized.codeUnits.any((unit) => unit <= 0x20 || unit >= 0x7f)) {
    // EN: Reject oversized keys and non-printable/non-ASCII header characters.
    // TH: ปฏิเสธ key ที่ยาวเกินหรือมีอักขระ header ที่ไม่พิมพ์ได้/ไม่ใช่ ASCII
    return false; // EN: Fail closed before prefix checks or JWT decoding. TH: ปฏิเสธก่อนตรวจ prefix หรือ decode JWT
  }
  if (normalized.startsWith('sb_publishable_')) {
    // EN: Check a modern public-key prefix. TH: ตรวจ prefix ของ public key รุ่นใหม่
    return normalized.length >
        'sb_publishable_'
            .length; // EN: Require a nonempty key value after the prefix. TH: บังคับให้มีค่า key ต่อจาก prefix
  } // EN: Finish modern public-key validation. TH: จบการตรวจ public key รุ่นใหม่

  final parts = normalized.split(
      '.'); // EN: Separate the three legacy JWT segments. TH: แยก JWT รุ่นเก่าเป็นสามส่วน
  if (parts.length != 3 || parts.any((part) => part.isEmpty)) {
    // EN: Require three nonempty JWT segments. TH: บังคับ JWT มีสามส่วนและไม่ว่าง
    return false; // EN: Reject malformed token structure. TH: ปฏิเสธโครงสร้าง token ที่ผิด
  } // EN: Finish legacy-token structure check. TH: จบการตรวจโครงสร้าง token รุ่นเก่า
  try {
    // EN: Decode only to check public role; this does not verify a signature. TH: ถอดรหัสเพื่อตรวจ role สาธารณะเท่านั้น ไม่ได้ยืนยัน signature
    // EN: JWT payload is base64url JSON; never accept a role from the header.
    // TH: payload JWT เป็น JSON แบบ base64url; ห้ามอ่าน role จาก header
    final payloadBytes = base64Url.decode(base64Url.normalize(parts[
        1])); // EN: Decode the JWT payload segment. TH: ถอดรหัสส่วน payload ของ JWT
    final payload = jsonDecode(utf8.decode(
        payloadBytes)); // EN: Parse payload JSON without trusting it for user authentication. TH: parse payload JSON โดยไม่ใช้แทนการยืนยันตัวผู้ใช้
    return payload is Map<String, dynamic> &&
        payload['role'] ==
            'anon'; // EN: Allow only the legacy anonymous project key role. TH: อนุญาตเฉพาะ role anon ของ project key รุ่นเก่า
  } on FormatException {
    // EN: Reject invalid base64, UTF-8, or JSON. TH: ปฏิเสธ base64, UTF-8 หรือ JSON ที่ผิดรูป
    return false; // EN: Fail closed for malformed legacy keys. TH: ปฏิเสธ key ที่ผิดรูป
  } // EN: Finish legacy-key decoding. TH: จบการถอดรหัส key รุ่นเก่า
}

String? authConfigurationError({
  // EN: Return a safe explanation when Auth configuration is invalid. TH: คืนคำอธิบายที่ปลอดภัยเมื่อ config Auth ไม่ถูกต้อง
  required String
      url, // EN: Receive the configured Supabase project URL. TH: รับ URL project Supabase ที่ตั้งค่า
  required String
      publishableKey, // EN: Receive the app-safe Supabase public key. TH: รับ public key ที่ปลอดภัยสำหรับแอป
  required bool
      releaseMode, // EN: Apply stricter rules to distributable builds. TH: ใช้กฎเข้มงวดกับ build สำหรับแจกจ่าย
}) {
  // EN: Normalize configuration inputs before validating or initializing Auth.
  // TH: ปรับรูปแบบ config ให้คงที่ก่อนตรวจหรือเริ่มระบบ Auth
  final normalizedUrl =
      url.trim(); // EN: Normalize the project URL. TH: ปรับรูปแบบ URL project
  final normalizedKey = publishableKey
      .trim(); // EN: Normalize the public key. TH: ปรับรูปแบบ public key
  if (normalizedUrl.length > _maxSupabaseConfigUrlChars ||
      normalizedUrl.codeUnits.any((unit) => unit <= 0x20 || unit == 0x7f)) {
    // EN: Bound URL parsing and reject whitespace/control characters.
    // TH: จำกัด URL ก่อน parse และปฏิเสธช่องว่าง/อักขระควบคุม
    return 'Supabase URL is malformed or too long.'; // EN: Return a safe configuration error. TH: คืน config error ที่ไม่เปิดเผยข้อมูลลับ
  }
  if (normalizedUrl.isEmpty && normalizedKey.isEmpty) {
    // EN: Detect an entirely unconfigured Auth service. TH: ตรวจกรณียังไม่ตั้งค่า Auth ทั้งคู่
    return releaseMode
        ? 'Supabase Auth must be configured for release builds; local demo mode is debug-only.' // EN: Require Auth in a distributable release. TH: บังคับตั้งค่า Auth ใน release ที่แจกจ่าย
        : null;
  } // EN: Finish the no-configuration branch. TH: จบกรณีไม่มี config
  if (normalizedUrl.isEmpty || normalizedKey.isEmpty) {
    // EN: Require URL and key as a matched pair. TH: บังคับให้ URL และ key มาคู่กัน
    return 'Set both DOZ_SUPABASE_URL and DOZ_SUPABASE_PUBLISHABLE_KEY.'; // EN: Name the missing build defines. TH: แจ้งชื่อตัวแปร build ที่ต้องตั้ง
  } // EN: Finish partial-configuration rejection. TH: จบการปฏิเสธ config ที่ขาดส่วน
  // EN: Parse once so malformed origins fail closed instead of reaching the SDK.
  // TH: parse URL ครั้งเดียวเพื่อปิดการทำงานเมื่อ origin ผิดรูปแบบ
  final uri = Uri.tryParse(
      normalizedUrl); // EN: Parse without throwing on invalid build configuration. TH: parse โดยไม่ throw เมื่อ build config ผิด
  // EN: Treat IPv4/IPv6 loopback and localhost names as local-only destinations.
  // TH: ถือ localhost และ loopback ทั้ง IPv4/IPv6 เป็นปลายทางสำหรับ local เท่านั้น
  final isLoopbackHost = uri !=
          null && // EN: Require a successfully parsed URI before inspecting its host. TH: ต้อง parse URI สำเร็จก่อนตรวจ host
      (uri.host ==
              'localhost' || // EN: Match the IPv4 localhost hostname. TH: ตรวจ hostname localhost
          uri.host ==
              '127.0.0.1' || // EN: Match the IPv4 loopback address. TH: ตรวจ IPv4 loopback
          uri.host ==
              '::1' || // EN: Match the IPv6 loopback address. TH: ตรวจ IPv6 loopback
          uri.host.endsWith(
              '.localhost')); // EN: Match local subdomains reserved for development. TH: ตรวจ subdomain localhost สำหรับ development
  if (releaseMode && isLoopbackHost) {
    // EN: Forbid local Auth endpoints in release builds. TH: ห้ามใช้ Auth endpoint ในเครื่องใน release
    return 'Localhost Supabase URLs are debug-only.'; // EN: Explain the release-only restriction. TH: แจ้งข้อจำกัดของ release
  } // EN: Finish local-host release validation. TH: จบการตรวจ local host สำหรับ release
  // EN: Permit loopback HTTP only for debug builds; remote services require HTTPS.
  // TH: อนุญาต HTTP เฉพาะ loopback ใน debug; service ระยะไกลต้องใช้ HTTPS
  final localDevelopmentUrl =
      !releaseMode && // EN: Limit the exception to non-release builds. TH: จำกัดข้อยกเว้นเฉพาะ build ที่ไม่ใช่ release
          uri !=
              null && // EN: Require a parsed URL. TH: บังคับให้ URL parse สำเร็จ
          isLoopbackHost && // EN: Permit the exception only for loopback hosts. TH: อนุญาตข้อยกเว้นเฉพาะ loopback host
          (uri.scheme == 'http' ||
              uri.scheme ==
                  'https'); // EN: Allow local HTTP/HTTPS during development. TH: อนุญาต HTTP/HTTPS ในเครื่องระหว่างพัฒนา
  // EN: Accept only a project root URL with no embedded credentials/query/fragment.
  // TH: รับเฉพาะ URL ระดับ project root และห้าม credential/query/fragment ฝังใน URL
  if (uri ==
          null || // EN: Reject invalid URL syntax. TH: ปฏิเสธ syntax URL ที่ผิด
      uri.host
          .isEmpty || // EN: Require a destination host. TH: บังคับให้มี host ปลายทาง
      (uri.scheme != 'https' &&
          !localDevelopmentUrl) || // EN: Require TLS except for debug loopback. TH: บังคับ TLS ยกเว้น loopback ใน debug
      uri.userInfo
          .isNotEmpty || // EN: Forbid credentials embedded in the URL. TH: ห้ามฝัง credential ใน URL
      (uri.path.isNotEmpty &&
          uri.path !=
              '/') || // EN: Require the project root, not an API subpath. TH: บังคับ project root ไม่ใช่ API subpath
      uri.hasQuery || // EN: Reject query parameters in project configuration. TH: ปฏิเสธ query parameter ใน config
      uri.hasFragment) {
    // EN: Reject URL fragments. TH: ปฏิเสธ URL fragment
    return 'Supabase URL must be a project-root HTTPS URL (localhost is debug-only).'; // EN: Explain the accepted project URL shape. TH: แจ้งรูปแบบ URL project ที่รับได้
  } // EN: Finish URL-origin validation. TH: จบการตรวจ origin ของ URL
  // EN: Allow only public key formats; reject malformed and privileged JWTs.
  // TH: อนุญาตเฉพาะรูปแบบ public key และปฏิเสธ JWT ที่ผิดหรือมีสิทธิ์สูง
  if (!_isAllowedSupabaseAppKey(normalizedKey)) {
    // EN: Reject privileged or malformed client keys. TH: ปฏิเสธ key ที่มีสิทธิ์สูงหรือผิดรูป
    return 'Use a Supabase publishable key or legacy anon JWT; never embed secret keys.'; // EN: Explain the app-safe key formats. TH: แจ้งรูปแบบ key ที่ปลอดภัยสำหรับแอป
  } // EN: Finish public-key validation. TH: จบการตรวจ public key
  return null; // EN: Indicate that the configuration passed validation. TH: ระบุว่า config ผ่านการตรวจ
}

class AuthService {
  // EN: Centralize Supabase session and credential operations. TH: รวมการจัดการ session และ credential ของ Supabase
  // EN: Prevent external construction; Supabase Auth is a process-wide singleton.
  // TH: ป้องกันการสร้าง instance ภายนอก เพราะ Supabase Auth เป็น singleton ของ process
  AuthService._(); // EN: Keep callers from constructing duplicate Auth wrappers. TH: ป้องกัน caller สร้าง wrapper Auth ซ้ำ

  // EN: Read the public project origin from compile-time build defines.
  // TH: อ่าน project origin แบบ public จาก build define ตอน compile
  static const _url = String.fromEnvironment(
      'DOZ_SUPABASE_URL'); // EN: Read only the public project origin from build-time configuration. TH: อ่านเฉพาะ origin project แบบ public จาก build config
  // EN: This key must be publishable/anon, never a server secret.
  // TH: key นี้ต้องเป็น publishable/anon ห้ามเป็น secret สำหรับ server
  static const _publishableKey = // EN: Keep the client key in the publishable/anon role only. TH: ใช้เฉพาะ client key ระดับ publishable/anon
      String.fromEnvironment(
          'DOZ_SUPABASE_PUBLISHABLE_KEY'); // EN: Never place a service-role key in app defines. TH: ห้ามใส่ service-role key ใน app define
  // EN: Track successful SDK initialization before accessing its singleton.
  // TH: ติดตามว่า SDK เริ่มต้นสำเร็จแล้วก่อนเรียก singleton
  static bool initialized =
      false; // EN: Track successful SDK startup for guarded operations. TH: ติดตามการเริ่ม SDK สำเร็จเพื่อใช้ guard operation
  static Future<void>?
      _initialization; // EN: Share one in-flight initialization among concurrent callers. TH: ใช้ future เดียวร่วมกันเมื่อมี caller เริ่มพร้อมกัน

  // EN: Expose configuration state without revealing key contents.
  // TH: เปิดเผยสถานะ config โดยไม่เผยเนื้อหา key
  static bool get isConfigured =>
      initialized; // EN: Expose initialization state, not credential contents. TH: เปิดเผยสถานะเริ่มระบบ ไม่เปิดเผย credential
  // EN: Return the current account ID only after initialization.
  // TH: คืน ID บัญชีปัจจุบันหลัง SDK เริ่มต้นแล้วเท่านั้น
  static String?
      get currentUserId => // EN: Read the authenticated identity only when initialized. TH: อ่าน identity ที่ยืนยันแล้วเมื่อ SDK เริ่มเท่านั้น
          initialized
              ? Supabase.instance.client.auth.currentUser?.id
              : null; // EN: Return null in debug demo mode. TH: คืน null ในโหมด demo debug
  // EN: Return the current session token only after initialization.
  // TH: คืน access token เฉพาะเมื่อ SDK เริ่มต้นแล้ว
  static String? get currentAccessToken =>
      initialized // EN: Expose an access token only after SDK initialization. TH: เปิดเผย access token หลัง SDK เริ่มแล้วเท่านั้น
          ? Supabase.instance.client.auth.currentSession
              ?.accessToken // EN: Return the token from the active session. TH: คืน token จาก session ปัจจุบัน
          : null; // EN: Return null when Auth is not configured. TH: คืน null เมื่อยังไม่ได้ตั้งค่า Auth
  // EN: Stream authentication state changes to app session handlers.
  // TH: ส่ง stream การเปลี่ยนสถานะ auth ให้ส่วนจัดการ session ของแอป
  static Stream<AuthState> get authChanges {
    // EN: Expose SDK auth events only after initialization. TH: เปิดเผย event auth หลัง SDK เริ่มแล้ว
    _requireInitialized(); // EN: Fail with a clear error instead of SDK singleton failure. TH: แจ้ง error ชัดเจนแทน singleton SDK ล้มเหลว
    return Supabase.instance.client.auth
        .onAuthStateChange; // EN: Return the SDK's session-change stream. TH: คืน stream เปลี่ยน session จาก SDK
  } // EN: Finish the guarded auth stream getter. TH: จบ getter stream auth ที่มี guard

  static void _requireInitialized() {
    // EN: Guard Auth operations against use before startup. TH: ป้องกันการใช้ Auth ก่อนเริ่มระบบ
    if (!initialized) {
      // EN: Detect missing Auth initialization. TH: ตรวจว่า Auth ยังไม่เริ่ม
      throw StateError(
          'Supabase Auth is not initialized.'); // EN: Stop before touching the SDK singleton. TH: หยุดก่อนเรียก singleton ของ SDK
    } // EN: Finish initialization guard. TH: จบ guard การเริ่มระบบ
  } // EN: Finish the shared Auth readiness check. TH: จบการตรวจความพร้อม Auth ส่วนกลาง

  static String _validatedEmail(String value) {
    // EN: Normalize and bound email input before network use. TH: ปรับรูปแบบและจำกัด email ก่อนส่ง network
    final email = value
        .trim(); // EN: Remove surrounding whitespace. TH: ตัดช่องว่างรอบ email
    if (email
            .isEmpty || // EN: Reject an empty email address. TH: ปฏิเสธ email ว่าง
        email.length >
            320 || // EN: Bound email length before sending it to the SDK. TH: จำกัดความยาว email ก่อนส่งให้ SDK
        email.contains(RegExp(r'[\r\n]'))) {
      // EN: Reject empty, oversized, or header-line-breaking input. TH: ปฏิเสธค่าว่าง ยาวเกิน หรือมี newline
      throw ArgumentError(
          'Email must be nonempty and at most 320 characters.'); // EN: Report validation without echoing the email. TH: แจ้ง validation โดยไม่สะท้อน email กลับ
    } // EN: Finish email validation. TH: จบการตรวจ email
    return email; // EN: Return the normalized value for the SDK. TH: คืนค่าที่ปรับแล้วให้ SDK
  } // EN: Finish email normalization. TH: จบการปรับ email

  static String _validatedPassword(String value) {
    // EN: Bound password size without logging or echoing secrets. TH: จำกัดขนาด password โดยไม่ log หรือสะท้อน secret
    if (value.isEmpty || value.length > 1024) {
      // EN: Reject missing or excessively large passwords. TH: ปฏิเสธ password ว่างหรือใหญ่เกิน
      throw ArgumentError(
          'Password must be nonempty and at most 1024 characters.'); // EN: Report the limit without including the password. TH: แจ้งขอบเขตโดยไม่ใส่ password ใน error
    } // EN: Finish password-size validation. TH: จบการตรวจขนาด password
    return value; // EN: Preserve the exact password, including intentional spaces. TH: คง password ตามเดิม รวมช่องว่างที่ตั้งใจใช้
  } // EN: Finish password validation. TH: จบการตรวจ password

  // EN: Validate configuration, then initialize Supabase once during app startup.
  // TH: ตรวจ config แล้วเริ่ม Supabase ระหว่างเปิดแอป
  static Future<void> initialize() {
    // EN: Return the same startup future to concurrent callers. TH: คืน future startup เดียวกันให้ caller ที่เรียกพร้อมกัน
    if (initialized) {
      // EN: Skip work after successful SDK initialization. TH: ข้ามงานเมื่อ SDK เริ่มสำเร็จแล้ว
      return Future<
          void>.value(); // EN: Return an already-completed future. TH: คืน future ที่เสร็จแล้ว
    } // EN: Finish the successful-initialization guard. TH: จบ guard เมื่อเริ่มสำเร็จแล้ว
    return _initialization ??=
        _initializeOnce(); // EN: Create at most one in-flight SDK initialization. TH: สร้างการเริ่ม SDK ที่กำลังทำงานได้เพียงครั้งเดียว
  } // EN: Finish concurrency-safe initialization entry point. TH: จบ entry point เริ่มระบบที่รองรับ caller พร้อมกัน

  static Future<void> _initializeOnce() async {
    // EN: Validate configuration and initialize the SDK. TH: ตรวจ config และเริ่ม SDK
    final error = authConfigurationError(
      // EN: Validate config before initializing the SDK. TH: ตรวจ config ก่อนเริ่ม SDK
      url:
          _url, // EN: Supply the compile-time project URL. TH: ส่ง URL project จาก compile-time
      publishableKey:
          _publishableKey, // EN: Supply only the app-safe public key. TH: ส่งเฉพาะ public key ที่ปลอดภัยสำหรับแอป
      releaseMode:
          kReleaseMode, // EN: Apply release-only URL rules when appropriate. TH: ใช้กฎ URL สำหรับ release เมื่อเกี่ยวข้อง
    ); // EN: Finish evaluating Auth configuration. TH: จบการประเมิน config Auth
    if (error != null) {
      // EN: Stop startup when configuration fails validation. TH: หยุด startup เมื่อ config ไม่ผ่าน
      throw StateError(
          error); // EN: Surface a safe configuration message without key contents. TH: แจ้ง config error โดยไม่แสดงเนื้อหา key
    } // EN: Finish invalid-configuration handling. TH: จบการจัดการ config ที่ไม่ถูกต้อง
    if (_url.trim().isEmpty && _publishableKey.trim().isEmpty) {
      return; // EN: Allow the debug demo to continue without Auth configuration. TH: อนุญาตโหมด demo debug เมื่อไม่มี config Auth
    } // EN: Finish the no-Auth debug-demo branch. TH: จบกรณี demo debug ที่ไม่มี Auth
    await Supabase.initialize(
      // EN: Initialize the SDK only after the preflight has passed. TH: เริ่ม SDK หลังผ่าน preflight แล้ว
      url: _url
          .trim(), // EN: Pass the normalized project URL. TH: ส่ง URL project ที่ตัดช่องว่างแล้ว
      publishableKey: _publishableKey
          .trim(), // EN: Pass the normalized public key. TH: ส่ง public key ที่ตัดช่องว่างแล้ว
    ); // EN: Wait until Supabase initialization completes. TH: รอจน Supabase เริ่มระบบเสร็จ
    initialized =
        true; // EN: Mark ready only after successful SDK initialization. TH: ตั้งสถานะพร้อมหลัง SDK เริ่มสำเร็จเท่านั้น
  } // EN: Finish one-time SDK initialization. TH: จบการเริ่ม SDK หนึ่งครั้ง

  // EN: Authenticate using a normalized email and the caller's password.
  // TH: เข้าสู่ระบบด้วยอีเมลที่ตัดช่องว่างและรหัสผ่านของผู้ใช้
  static Future<AuthResponse> signIn(String email, String password) {
    // EN: Sign in with bounded user credentials. TH: เข้าสู่ระบบด้วย credential ผู้ใช้ที่จำกัดขนาด
    _requireInitialized(); // EN: Prevent calls when Supabase has not started. TH: ป้องกันการเรียกก่อนเริ่ม Supabase
    return Supabase.instance.client.auth.signInWithPassword(
      // EN: Delegate password authentication to Supabase. TH: ส่งการยืนยัน password ให้ Supabase
      email: _validatedEmail(
          email), // EN: Normalize and validate email input. TH: ปรับและตรวจ email
      password: _validatedPassword(
          password), // EN: Preserve and size-check the password. TH: คงค่าและตรวจขนาด password
    ); // EN: Return the SDK authentication future. TH: คืน future การยืนยันจาก SDK
  } // EN: Finish password sign-in. TH: จบการเข้าสู่ระบบด้วย password

  // EN: Create an account and request the registered deep-link callback.
  // TH: สร้างบัญชีและกำหนด deep link สำหรับ callback ยืนยันบัญชี
  static Future<AuthResponse> signUp(String email, String password) {
    // EN: Create a user with validated credentials and a fixed redirect. TH: สร้างผู้ใช้ด้วย credential ที่ตรวจแล้วและ redirect ตายตัว
    _requireInitialized(); // EN: Prevent calls when Supabase has not started. TH: ป้องกันการเรียกก่อนเริ่ม Supabase
    return Supabase.instance.client.auth.signUp(
      // EN: Delegate account creation to Supabase. TH: ส่งการสร้างบัญชีให้ Supabase
      email: _validatedEmail(
          email), // EN: Normalize and validate email input. TH: ปรับและตรวจ email
      password: _validatedPassword(
          password), // EN: Preserve and size-check the password. TH: คงค่าและตรวจขนาด password
      emailRedirectTo:
          callbackUri, // EN: Return to the current web origin or registered mobile link. TH: กลับสู่ origin เว็บปัจจุบันหรือ deep link มือถือที่ลงทะเบียน
    ); // EN: Return the SDK account-creation future. TH: คืน future การสร้างบัญชีจาก SDK
  } // EN: Finish account registration. TH: จบการสมัครบัญชี

  // EN: Ask Supabase to send a password-recovery email to the account owner.
  // TH: ขอให้ Supabase ส่งอีเมลกู้คืนรหัสผ่านให้เจ้าของบัญชี
  static Future<void> sendPasswordReset(String email) {
    // EN: Request a recovery email for a validated address. TH: ขออีเมลกู้คืนไปยัง email ที่ตรวจแล้ว
    _requireInitialized(); // EN: Prevent calls when Supabase has not started. TH: ป้องกันการเรียกก่อนเริ่ม Supabase
    return Supabase.instance.client.auth.resetPasswordForEmail(
      // EN: Delegate recovery delivery to Supabase. TH: ส่งการส่งอีเมลกู้คืนให้ Supabase
      _validatedEmail(
          email), // EN: Normalize and bound the destination email. TH: ปรับและจำกัด email ปลายทาง
      redirectTo:
          callbackUri, // EN: Use a platform-correct recovery callback. TH: ใช้ callback กู้คืนที่ตรงกับแพลตฟอร์ม
    ); // EN: Return the SDK recovery request future. TH: คืน future คำขอกู้คืนจาก SDK
  } // EN: Finish password-reset request. TH: จบคำขอรีเซ็ตรหัสผ่าน

  // EN: Update the password for the currently authenticated session.
  // TH: เปลี่ยนรหัสผ่านของ session ที่ยืนยันตัวตนอยู่
  static Future<void> updatePassword(String password) async {
    // EN: Update the password for the active session. TH: เปลี่ยน password ของ session ปัจจุบัน
    _requireInitialized(); // EN: Prevent calls when Supabase has not started. TH: ป้องกันการเรียกก่อนเริ่ม Supabase
    await Supabase.instance.client.auth.updateUser(
      // EN: Delegate the authenticated update to Supabase. TH: ส่งการเปลี่ยนที่ยืนยันตัวตนแล้วให้ Supabase
      UserAttributes(
          password: _validatedPassword(
              password)), // EN: Bound input without logging the secret. TH: จำกัด input โดยไม่ log secret
    ); // EN: Wait for Supabase to complete the update. TH: รอให้ Supabase เปลี่ยน password เสร็จ
  } // EN: Finish password update. TH: จบการเปลี่ยน password

  // EN: Deep link registered in Android and iOS app manifests.
  // TH: deep link ที่ลงทะเบียนไว้ใน manifest ของ Android และ iOS
  static const String redirectUri =
      'doz://login-callback/'; // EN: Match the Android/iOS registered callback URI. TH: ให้ตรงกับ callback URI ที่ลงทะเบียนใน Android/iOS

  // EN: Browser email callbacks must return to the deployed web app, not a mobile deep link.
  // TH: callback ทางอีเมลบน browser ต้องกลับเว็บที่ deploy ไม่ใช่ deep link ของมือถือ
  static String get callbackUri =>
      callbackUriForPlatform(isWeb: kIsWeb, baseUri: Uri.base);

  // EN: Keep callback selection testable without launching a browser or Supabase.
  // TH: แยกการเลือก callback เพื่อทดสอบได้โดยไม่ต้องเปิด browser หรือ Supabase
  static String callbackUriForPlatform({
    required bool isWeb,
    required Uri baseUri,
  }) =>
      isWeb ? '${baseUri.origin}/' : redirectUri;

  // EN: Revoke the local/remote Supabase session through the SDK.
  // TH: ออกจากระบบและ revoke session ผ่าน SDK ของ Supabase
  static Future<void> signOut() {
    // EN: Revoke the active Supabase session through the SDK. TH: revoke session Supabase ปัจจุบันผ่าน SDK
    _requireInitialized(); // EN: Prevent calls when Supabase has not started. TH: ป้องกันการเรียกก่อนเริ่ม Supabase
    return Supabase.instance.client.auth
        .signOut(); // EN: Return the SDK sign-out future. TH: คืน future การออกจากระบบของ SDK
  } // EN: Finish sign-out. TH: จบการออกจากระบบ
}
