import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Validate and normalize the account namespace shared by secure local stores.
/// / ตรวจและปรับรูปแบบ namespace บัญชีที่ secure local stores ใช้ร่วมกัน
String validateStorageScope(String scope) {
  final normalized = scope
      .trim(); // EN: Normalize surrounding whitespace. TH: ตัดช่องว่างหัวท้ายก่อนตรวจ
  final safeCharacters = normalized.codeUnits.every(
      (unit) => // EN: Check each ASCII code unit explicitly. TH: ตรวจ code unit ASCII ทีละตัวอย่างชัดเจน
          (unit >= 0x30 &&
              unit <= 0x39) || // EN: Allow digits. TH: อนุญาตตัวเลข
          (unit >= 0x41 &&
              unit <=
                  0x5A) || // EN: Allow uppercase Latin letters. TH: อนุญาตอักษรละตินตัวพิมพ์ใหญ่
          (unit >= 0x61 &&
              unit <=
                  0x7A) || // EN: Allow lowercase Latin letters. TH: อนุญาตอักษรละตินตัวพิมพ์เล็ก
          unit == 0x5F || // EN: Allow underscore. TH: อนุญาตขีดล่าง
          unit == 0x2D); // EN: Allow hyphen. TH: อนุญาตขีดกลาง
  if (normalized.isEmpty || normalized.length > 128 || !safeCharacters) {
    // EN: Reject invalid identifiers before using them in storage keys. TH: ปฏิเสธ identifier ที่ผิดก่อนนำไปสร้าง storage key
    throw ArgumentError(
        'Storage scope must be a safe 1–128 character identifier.'); // EN: Keep the error generic so it does not echo account data. TH: ใช้ error ทั่วไปโดยไม่สะท้อนข้อมูลบัญชีกลับ
  }
  return normalized; // EN: Return the canonical validated namespace. TH: คืน namespace มาตรฐานที่ผ่านการตรวจ
}

/// Secure key/value boundary for sensitive data. / ขอบเขต secure storage สำหรับข้อมูลอ่อนไหว
abstract interface class SecureKeyValueStore {
  /// Read one value by its already-scoped key. / อ่านค่าด้วย key ที่ผูก scope แล้ว
  Future<String?> read(String key);

  /// Write one value by its already-scoped key. / เขียนค่าด้วย key ที่ผูก scope แล้ว
  Future<void> write(String key, String value);

  /// Delete one value by its already-scoped key. / ลบค่าด้วย key ที่ผูก scope แล้ว
  Future<void> delete(String key);
}

/// Platform-backed implementation using Keychain/Keystore. / ใช้ Keychain/Keystore ของระบบ
class PlatformSecureKeyValueStore implements SecureKeyValueStore {
  PlatformSecureKeyValueStore({FlutterSecureStorage? storage}) // EN: Allow injecting the platform adapter in controlled contexts. TH: อนุญาต inject adapter ในบริบทที่ควบคุมได้
      : _storage = storage ?? const FlutterSecureStorage(); // EN: Default to the operating-system secure store. TH: ใช้ secure store ของระบบปฏิบัติการเป็นค่าเริ่มต้น

  final FlutterSecureStorage _storage; // EN: Hold the platform-backed encrypted key/value API. TH: เก็บ API key/value แบบเข้ารหัสของ platform

  @override
  Future<String?> read(String key) => // EN: Read one secure value without logging its contents. TH: อ่านค่า secure หนึ่งค่าโดยไม่ log เนื้อหา
      _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => // EN: Store one value using the platform secure-storage plugin. TH: บันทึกค่าหนึ่งค่าผ่าน plugin secure storage ของระบบ
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => // EN: Delete one scoped secure value. TH: ลบค่า secure ที่ผูก scope หนึ่งรายการ
      _storage.delete(key: key);
}

/// Per-account encrypted storage for profile/health and alert records.
/// / พื้นที่เข้ารหัสแยกตามบัญชีสำหรับโปรไฟล์/สุขภาพและประวัติแจ้งเตือน
class SecureProfileStorage {
  // EN: Allow a controlled store in tests while defaulting production to platform secure storage.
  // TH: รองรับ store ที่กำหนดเองสำหรับทดสอบ และใช้ secure storage ของระบบใน production
  SecureProfileStorage({SecureKeyValueStore? store})
      : _store = store ?? PlatformSecureKeyValueStore();

  final SecureKeyValueStore _store;
  static const int _maxProfileBytes =
      64 * 1024; // EN: Bound encrypted profile size to 64 KiB. TH: จำกัดขนาด profile ที่เข้ารหัสไว้ 64 KiB
  static const List<String> _sensitiveFields = [ // EN: Allow only these explicitly reviewed profile keys. TH: อนุญาตเฉพาะ key โปรไฟล์ที่ระบุและตรวจแล้ว
    'userName',
    'emergencyContactName',
    'emergencyContactPhone',
    'weight',
    'height',
    'age',
    'profileDetailsProvided',
    'birthDate',
    'gender',
    'conditions',
    'privacyPolicyAcceptedAt',
    'latitude',
    'longitude',
  ];

  String _validatedScope(String scope) { // EN: Apply one shared account-key validation rule. TH: ใช้กฎตรวจ account key ที่ใช้ร่วมกัน
    // EN: Reuse the same strict namespace validation as the alert store.
    // TH: ใช้กฎ namespace ที่เข้มงวดชุดเดียวกับ alert store
    return validateStorageScope(scope);
  }

  String _key(String scope) => // EN: Build the versioned encrypted profile key for one account. TH: สร้าง key profile เข้ารหัสแบบมี version ของบัญชีหนึ่งราย
      'doz.${_validatedScope(scope)}.secure_profile.v1';

  String _legacyKey(String scope, String field) => // EN: Address a prior scoped plaintext preference for migration. TH: ระบุ preference ข้อความธรรมดาแบบ scoped รุ่นเก่าเพื่อย้ายข้อมูล
      'doz.${_validatedScope(scope)}.$field';

  /// Move scoped plaintext values only after the encrypted write succeeds.
  /// ย้ายค่าข้อความธรรมดาเมื่อเขียนข้อมูลเข้ารหัสสำเร็จแล้วเท่านั้น
  Future<void> migrateLegacyPreferences({
    required SharedPreferences preferences,
    required String scope,
    bool removeUnscopedLegacy = false,
  }) async {
    // EN: Resolve the validated namespace once before the first await.
    // TH: ตรวจและเก็บ namespace ไว้ครั้งเดียวก่อน await แรก
    final key = _key(scope);
    final normalizedScope = _validatedScope(scope);
    final current = await _store.read(key);
    if (current != null && !_isValidProfileJson(current)) return;
    final originalValues = current ==
            null // EN: Start empty when no secure profile exists. TH: เริ่มจากค่าว่างเมื่อยังไม่มี secure profile
        ? <String, Object?>{}
        : Map<String, Object?>.from(jsonDecode(current) as Map);
    final values = Map<String, Object?>.from(
        originalValues); // EN: Copy decoded values before sanitizing. TH: คัดลอกค่าที่ถอดรหัสก่อน sanitize
    values.removeWhere((field, value) => !_isValidProfileEntry(field,
        value)); // EN: Drop unsupported or invalid fields from the in-memory copy. TH: ตัด field ที่ไม่รองรับหรือผิดออกจากสำเนาในหน่วยความจำ
    var changed = values.length !=
        originalValues
            .length; // EN: Rewrite storage if invalid fields were removed. TH: เขียน storage ใหม่เมื่อมี field ผิดถูกตัด
    for (final field in _sensitiveFields) {
      final value = preferences.get(_legacyKey(normalizedScope, field)) ??
          (removeUnscopedLegacy ? preferences.get(field) : null);
      if (!values.containsKey(field) &&
          value != null &&
          _isValidProfileEntry(field, value)) {
        // EN: Copy only validated legacy values missing from secure storage. TH: ย้ายเฉพาะค่า legacy ที่ผ่านตรวจและยังไม่มีใน secure storage
        values[field] =
            value; // EN: Add the validated value to the secure profile copy. TH: เพิ่มค่าที่ผ่านตรวจลงสำเนา secure profile
        changed =
            true; // EN: Mark the profile for encrypted persistence. TH: ทำเครื่องหมายให้บันทึก profile แบบเข้ารหัส
      }
    }
    var verified = current;
    if (changed) {
      final encoded = jsonEncode(values);
      // EN: Preserve plaintext when migrated profile data exceeds its storage budget.
      // TH: คงข้อมูล plaintext ไว้เมื่อข้อมูล profile ที่ย้ายมีขนาดเกินเพดาน
      if (!_fitsProfileLimit(encoded)) return;
      await _store.write(key, encoded);
      verified = await _store.read(key);
      if (verified != encoded) return;
    }
    // EN: Delete old values only after the secure copy is present and readable.
    // TH: ลบค่าเก่าหลังตรวจว่าคัดลอกใน secure storage และอ่านกลับได้แล้ว
    if (verified != null && _isValidProfileJson(verified)) {
      final verifiedValues =
          Map<String, Object?>.from(jsonDecode(verified) as Map);
      for (final field in _sensitiveFields) {
        if (!verifiedValues.containsKey(field) ||
            !_isValidProfileEntry(field, verifiedValues[field])) {
          // EN: Keep legacy data unless its secure copy is valid. TH: คง legacy ไว้หากสำเนา secure ยังไม่ผ่านตรวจ
          continue; // EN: Preserve plaintext that was not verified in secure storage. TH: เก็บ plaintext ที่ยังยืนยันใน secure storage ไม่ได้
        } // EN: Continue cleanup only for verified fields. TH: ล้างต่อเฉพาะ field ที่ยืนยันแล้ว
        await preferences.remove(_legacyKey(normalizedScope,
            field)); // EN: Remove the matching scoped plaintext value. TH: ลบ plaintext แบบ scoped ที่ตรงกัน
        if (removeUnscopedLegacy) {
          // EN: Clean the unscoped source only when migration was authorized. TH: ล้างแหล่งที่ไม่มี scope เมื่ออนุญาต migration เท่านั้น
          await preferences.remove(
              field); // EN: Remove the verified unscoped plaintext value. TH: ลบ plaintext ที่ไม่มี scope ซึ่งยืนยันแล้ว
        } // EN: Finish optional unscoped cleanup. TH: จบการล้างข้อมูลที่ไม่มี scope แบบ optional
      }
    }
  }

  bool _isValidProfileJson(String? raw) { // EN: Check size and top-level JSON shape before migration. TH: ตรวจขนาดและโครงสร้าง JSON ชั้นบนก่อน migration
    if (raw == null || !_fitsProfileLimit(raw)) return false; // EN: Reject absent or oversized profile text. TH: ปฏิเสธข้อความ profile ที่หายหรือใหญ่เกิน
    try { // EN: Parse the bounded JSON to confirm it is a map. TH: parse JSON ที่จำกัดขนาดเพื่อยืนยันว่าเป็น map
      return jsonDecode(raw) is Map<String, dynamic>; // EN: Accept only a top-level string-keyed JSON object. TH: รับเฉพาะ JSON object ชั้นบนที่ใช้ key เป็นข้อความ
    } on FormatException { // EN: Treat malformed JSON as invalid without deleting it. TH: ถือ JSON ผิดรูปว่าไม่ถูกต้องโดยไม่ลบทิ้ง
      return false; // EN: Keep malformed storage closed to normal reads. TH: ปิดการอ่านปกติเมื่อข้อมูลผิดรูป
    }
  }

  Future<Map<String, dynamic>> readProfile(String scope) async { // EN: Read and validate one account's encrypted profile. TH: อ่านและตรวจ profile เข้ารหัสของบัญชีหนึ่งราย
    final key = _key(scope); // EN: Derive the secure key from the validated account scope. TH: สร้าง secure key จาก account scope ที่ตรวจแล้ว
    final raw = await _store.read(key); // EN: Read only this account's secure profile blob. TH: อ่าน blob secure profile ของบัญชีนี้เท่านั้น
    if (raw == null || raw.isEmpty) return <String, dynamic>{}; // EN: Represent an uninitialized profile as an empty map. TH: แทน profile ที่ยังไม่มีด้วย map ว่าง
    if (!_fitsProfileLimit(raw)) {
      throw StateError('Encrypted profile data exceeds its size limit.'); // EN: Fail closed instead of decoding an oversized value. TH: ปิดการอ่านแทนการ decode ค่าที่ใหญ่เกิน
    }
    try { // EN: Parse only after enforcing the storage byte cap. TH: parse หลังบังคับเพดาน byte ของ storage
      final decoded = jsonDecode(raw); // EN: Decode the profile object from JSON. TH: decode object profile จาก JSON
      if (decoded is Map<String, dynamic>) { // EN: Require the expected object shape. TH: บังคับโครงสร้างเป็น object ตามที่คาด
        decoded.removeWhere((field, value) => !_isValidProfileEntry(field,
            value)); // EN: Expose only allowlisted, validated values. TH: เปิดเผยเฉพาะค่าที่ผ่าน allowlist และ validation
        return decoded; // EN: Preserve invalid stored bytes on disk for possible recovery. TH: คง byte ที่ผิดใน disk ไว้เผื่อกู้คืน
      }
    } on FormatException {
      // EN: Preserve the value for recovery; startup catches this and fails closed.
      // TH: คงข้อมูลไว้กู้คืน; startup จะจับ error และหยุดแบบ fail-closed
    }
    throw StateError('Encrypted profile data is invalid.'); // EN: Report invalid shape without returning partial profile data. TH: แจ้งโครงสร้างผิดโดยไม่คืน profile บางส่วน
  }

  Future<void> writeProfile( // EN: Validate and save an allowlisted profile under one account key. TH: ตรวจและบันทึก profile ที่อยู่ใน allowlist ใต้ key บัญชี
    String scope,
    Map<String, Object?> profile,
  ) async {
    final key = _key(scope); // EN: Capture this account's secure key before validation or writes. TH: จับ secure key ของบัญชีก่อนตรวจและเขียน
    if (profile.keys.any((field) => !_sensitiveFields.contains(field))) {
      // EN: Enforce the profile field allowlist. TH: บังคับ allowlist ของ field โปรไฟล์
      throw ArgumentError('Profile contains an unsupported field.');
    }
    if (profile.entries
        .any((entry) => !_isValidProfileEntry(entry.key, entry.value))) {
      // EN: Validate every value before serialization. TH: ตรวจทุกค่าก่อน serialize
      throw ArgumentError('Profile contains an invalid field value.');
    }
    final encoded = jsonEncode(profile); // EN: Serialize only the allowlisted, validated fields. TH: serialize เฉพาะ field ที่ผ่าน allowlist และ validation
    if (!_fitsProfileLimit(encoded)) {
      throw ArgumentError('Profile data exceeds its size limit.'); // EN: Reject the write before reaching secure storage. TH: ปฏิเสธการเขียนก่อนส่งข้อมูลเข้า secure storage
    }
    await _store.write(key, encoded); // EN: Persist the bounded profile under the captured account key. TH: บันทึก profile ที่จำกัดขนาดใต้ key ของบัญชีที่จับไว้
  }

  Future<void> clearProfile(String scope) => // EN: Delete only this account's encrypted profile record. TH: ลบเฉพาะ profile เข้ารหัสของบัญชีนี้
      _store.delete(_key(scope));

  bool _isValidProfileEntry(String field, Object? value) {
    // EN: Validate one sensitive profile field. TH: ตรวจ field โปรไฟล์อ่อนไหวหนึ่งรายการ
    // EN: Reject unknown profile keys before data is used or persisted. TH: ปฏิเสธ key โปรไฟล์ที่ไม่รู้จักก่อนนำไปใช้หรือบันทึก
    if (!_sensitiveFields.contains(field)) {
      // EN: Reject fields outside the explicit allowlist. TH: ปฏิเสธ field นอก allowlist
      return false; // EN: Do not expose or persist unknown profile data. TH: ไม่เปิดเผยหรือบันทึกข้อมูลโปรไฟล์ที่ไม่รู้จัก
    } // EN: Continue validating an allowed field. TH: ตรวจ field ที่อนุญาตต่อ
    // EN: Null represents a cleared optional value. TH: null หมายถึงค่าที่ไม่บังคับถูกล้าง
    if (value == null) {
      // EN: Accept null for cleared optional profile values. TH: รับ null สำหรับค่าทางเลือกที่ถูกล้าง
      return true; // EN: Preserve the explicit cleared state. TH: คงสถานะที่ล้างแล้วอย่างชัดเจน
    } // EN: Validate non-null values by field type. TH: ตรวจค่าที่ไม่ใช่ null ตามชนิด field
    // EN: Validate values according to the profile field's expected type and range. TH: ตรวจชนิดและช่วงตาม field โปรไฟล์
    switch (field) {
      // EN: Apply a type and bounds rule for each field. TH: ใช้กฎชนิดและขอบเขตตาม field
      case 'userName':
      case 'emergencyContactName':
        return value is String &&
            value.length <=
                128; // EN: Bound profile/contact names. TH: จำกัดความยาวชื่อโปรไฟล์และผู้ติดต่อ
      case 'emergencyContactPhone':
        return value is String &&
            value.length <=
                64; // EN: Bound the stored phone string. TH: จำกัดความยาวเบอร์โทรที่เก็บ
      case 'gender':
        return value is String &&
            value.length <=
                64; // EN: Bound the gender label. TH: จำกัดความยาวป้ายเพศ
      case 'conditions':
        return value is String &&
            value.length <=
                4096; // EN: Bound free-text condition notes. TH: จำกัดข้อความภาวะสุขภาพ
      case 'birthDate':
      case 'privacyPolicyAcceptedAt':
        return value is String &&
            value.length <= 64 &&
            DateTime.tryParse(value) !=
                null; // EN: Require a parseable bounded timestamp. TH: บังคับ timestamp ที่ parse ได้และมีขนาดจำกัด
      case 'weight':
        return value is num &&
            value.isFinite &&
            value >= 0 &&
            value <=
                500; // EN: Require finite weight from 0 to 500 kg. TH: บังคับน้ำหนัก finite ช่วง 0–500 kg
      case 'height':
        return value is num &&
            value.isFinite &&
            value >= 0 &&
            value <=
                300; // EN: Require finite height from 0 to 300 cm. TH: บังคับส่วนสูง finite ช่วง 0–300 cm
      case 'age':
        return value is int &&
            value >= 0 &&
            value <=
                130; // EN: Bound age to a nonnegative human range. TH: จำกัดอายุในช่วงที่ไม่ติดลบ
      case 'profileDetailsProvided':
        return value
            is bool; // EN: Accept only an explicit completion flag. TH: รับเฉพาะ flag ที่เป็น boolean
      case 'latitude':
        return value is num &&
            value.isFinite &&
            value >= -90 &&
            value <=
                90; // EN: Enforce valid geographic latitude. TH: บังคับละติจูดตามช่วงพิกัดโลก
      case 'longitude':
        return value is num &&
            value.isFinite &&
            value >= -180 &&
            value <=
                180; // EN: Enforce valid geographic longitude. TH: บังคับลองจิจูดตามช่วงพิกัดโลก
      default:
        return false; // EN: Reject fields without a validation rule. TH: ปฏิเสธ field ที่ไม่มีกฎตรวจ
    } // EN: Finish field-specific validation. TH: จบการตรวจตาม field
  } // EN: Finish profile-entry validation. TH: จบการตรวจค่าโปรไฟล์

  bool _fitsProfileLimit(String value) { // EN: Reject profiles over the UTF-8 byte budget. TH: ปฏิเสธ profile ที่เกินเพดาน byte UTF-8
    // EN: Check characters first, then enforce the UTF-8 byte budget.
    // TH: ตรวจจำนวนตัวอักษรก่อน แล้วจึงบังคับเพดาน byte UTF-8
    if (value.length > _maxProfileBytes) return false; // EN: Reject obviously oversized text before UTF-8 allocation. TH: ปฏิเสธข้อความใหญ่ชัดเจนก่อนสร้าง byte UTF-8
    try { // EN: Count the exact encoded byte size. TH: นับขนาด byte หลัง encode จริง
      return utf8.encode(value).length <= _maxProfileBytes; // EN: Accept only values within the secure-store budget. TH: รับเฉพาะค่าที่อยู่ในงบ secure storage
    } on FormatException { // EN: Reject text that cannot be encoded as valid UTF-8. TH: ปฏิเสธข้อความที่ encode เป็น UTF-8 ไม่ได้
      return false; // EN: Fail closed for malformed strings. TH: ปฏิเสธ string ที่ผิดรูปแบบ
    } on ArgumentError { // EN: Normalize encoder argument failures into validation failure. TH: แปลง encoder argument error เป็นผล validation ไม่ผ่าน
      return false; // EN: Keep malformed input out of encrypted storage. TH: กัน input ผิดรูปออกจาก encrypted storage
    }
  }
}
