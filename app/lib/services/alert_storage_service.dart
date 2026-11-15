import 'dart:convert'; // EN: Encode and decode bounded alert-history JSON. TH: เข้ารหัสและถอดรหัส JSON ประวัติแจ้งเตือนแบบจำกัดขนาด

import 'package:shared_preferences/shared_preferences.dart'; // EN: Read and remove legacy plaintext history during migration. TH: อ่านและลบประวัติ plaintext รุ่นเก่าระหว่างย้ายข้อมูล

import '../models/alert_record.dart'; // EN: Validate saved alert records before display. TH: ตรวจระเบียนแจ้งเตือนก่อนแสดงผล
import 'secure_local_storage.dart'; // EN: Store account-scoped history in platform secure storage. TH: เก็บประวัติแยกบัญชีใน secure storage ของเครื่อง

/// EN: Store alert history under validated account-scoped encrypted keys.
/// TH: จัดเก็บประวัติแจ้งเตือนด้วย key เข้ารหัสที่แยกตามบัญชีและผ่าน validation
class AlertStorageService {
  // EN: Bound both row count and encoded storage to avoid unbounded local growth.
  // TH: จำกัดจำนวนและขนาดข้อมูลเพื่อป้องกันประวัติในเครื่องโตไม่จำกัด
  static const int maxEntries = 500;
  static const int maxEncodedBytes = 1024 *
      1024; // EN: Cap serialized history at one MiB of UTF-8. TH: จำกัดประวัติที่ serialize แล้วไม่เกินหนึ่ง MiB UTF-8
  // EN: Keep the old public name for source compatibility; the limit is now UTF-8 bytes.
  // TH: คงชื่อ public เดิมเพื่อ compatibility แต่ขีดจำกัดนับเป็น UTF-8 bytes
  @Deprecated('Use maxEncodedBytes; the limit is measured in UTF-8 bytes.')
  static const int maxEncodedCharacters = maxEncodedBytes;

  /// EN: Allow a test/platform adapter while defaulting to encrypted storage.
  /// TH: รองรับ adapter สำหรับทดสอบ/แพลตฟอร์ม และใช้ secure storage เป็นค่าเริ่มต้น
  AlertStorageService({SecureKeyValueStore? secureStore})
      : _secureStore = secureStore ?? PlatformSecureKeyValueStore();

  // EN: Keep the injected secure-storage boundary private to this service. TH: เก็บขอบเขต secure storage ที่ inject ไว้เป็น private
  final SecureKeyValueStore _secureStore;
  final Map<String, Future<void>> _storageQueues = <String,
      Future<
          void>>{}; // EN: Serialize writes and migrations by account. TH: จัดลำดับ write และ migration แยกตามบัญชี
  final Set<String> _invalidatedScopes =
      <String>{}; // EN: Fence storage writes after account deletion. TH: กั้นการเขียนหลังลบบัญชี

  String _scopeId =
      'local-demo'; // EN: Start in the isolated demo namespace. TH: เริ่มใน namespace demo ที่แยกไว้

  /// EN: Switch future reads/writes to a validated account namespace.
  /// TH: เปลี่ยนการอ่าน/เขียนถัดไปไปยัง namespace บัญชีที่ผ่านการตรวจ
  void setScope(String scopeId) {
    // EN: Use the shared strict validator to keep account-key rules consistent.
    // TH: ใช้ตัวตรวจกลางเพื่อให้กฎ key ของบัญชีสอดคล้องกัน
    _scopeId = validateStorageScope(scopeId);
  }

  /// EN: Fence a deleted account so queued saves cannot recreate or expose its history.
  /// TH: กั้นบัญชีที่ลบแล้วเพื่อไม่ให้ save ที่ค้างสร้างหรือเผยประวัติกลับมา
  void invalidateScope(String scopeId) {
    // EN: Permanently block history writes for a deleted account. TH: ปิดการเขียนประวัติของบัญชีที่ลบแล้ว
    _invalidatedScopes.add(validateStorageScope(
        scopeId)); // EN: Validate before recording the deleted scope. TH: ตรวจ scope ก่อนบันทึกบัญชีที่ลบ
  } // EN: Finish account-scope invalidation. TH: จบการปิดกั้น scope

  /// EN: Migrate legacy plaintext only after a verified secure write.
  /// TH: ย้าย plaintext รุ่นเก่าเมื่อเขียน secure และอ่านกลับยืนยันได้แล้วเท่านั้น
  Future<void> migrateLegacyHistoryIfNeeded({String? scopeId}) async {
    // EN: Snapshot scope-derived keys before the first await to prevent account-switch races.
    // TH: เก็บ key ของ scope ไว้ก่อน await แรก เพื่อป้องกัน race ตอนสลับบัญชี
    final scope = validateStorageScope(scopeId ?? _scopeId);
    if (_invalidatedScopes.contains(scope)) {
      // EN: Check whether deletion fenced this scope. TH: ตรวจว่า scope นี้ถูกกั้นหลังลบหรือไม่
      return; // EN: Skip migration for deleted accounts. TH: ข้าม migration ของบัญชีที่ถูกลบ
    } // EN: Continue migration for an active scope. TH: ทำ migration ต่อสำหรับ scope ที่ active
    await _enqueueStorageOperation(
      // EN: Serialize migration with save and clear operations. TH: จัดลำดับ migration ร่วมกับการบันทึกและลบ
      scope, // EN: Keep this operation bound to its captured account. TH: ผูก operation นี้กับบัญชีที่ snapshot
      () => _migrateLegacyHistoryForScope(
          scope), // EN: Run migration using only captured keys. TH: ทำ migration ด้วย key ที่ snapshot ไว้เท่านั้น
    ); // EN: Finish the queued migration request. TH: จบคำขอ migration ที่เข้าคิว
  }

  Future<void> _migrateLegacyHistoryForScope(String scope) async {
    // EN: Perform migration while holding this account's queue. TH: ทำ migration ภายในคิวของบัญชีนี้
    final secureKey =
        'doz.$scope.alert_history.secure.v1'; // EN: Address the secure key for the captured scope. TH: ระบุ secure key ตาม scope ที่ snapshot
    final legacyKey =
        'doz.$scope.alert_history'; // EN: Address only the matching legacy key. TH: ระบุ legacy key ของ scope เดียวกัน
    final prefs = await SharedPreferences
        .getInstance(); // EN: Open preferences for legacy migration sources. TH: เปิด preferences เพื่ออ่านแหล่ง legacy
    final current = await _secureStore.read(
        secureKey); // EN: Read the secure destination before merging. TH: อ่านปลายทาง secure ก่อนรวมข้อมูล
    if (current != null && !_isValidEncodedHistory(current)) {
      // EN: Preserve all legacy sources if the secure destination is malformed.
      // TH: คงแหล่ง legacy ไว้ทั้งหมดหากปลายทาง secure ผิดรูป
      return; // EN: Avoid overwriting data that may need manual recovery. TH: ป้องกันการเขียนทับข้อมูลที่อาจต้องกู้คืน
    }
    final legacySources = <String, String>{
      if (prefs.getString(legacyKey) case final value?) legacyKey: value,
      if (scope == 'local-demo')
        if (prefs.getString('doz_alert_history') case final value?)
          'doz_alert_history': value,
    };
    if (legacySources.isEmpty) {
      // EN: Stop when there is nothing to migrate. TH: หยุดเมื่อไม่มีข้อมูลให้ย้าย
      return; // EN: Avoid rewriting an unchanged secure record. TH: ไม่เขียน secure record เดิมซ้ำโดยไม่จำเป็น
    }
    final sources = <String>[
      if (current != null) current,
      ...legacySources.values,
    ];
    final merged = _mergeLegacyHistories(sources);
    if (merged == null) {
      // EN: Keep plaintext sources when none has a valid history shape. TH: คง plaintext เมื่อไม่มีแหล่งใดมีโครงสร้างประวัติที่ใช้ได้
      return; // EN: Do not erase the only recoverable copy. TH: อย่าลบสำเนาเดียวที่อาจกู้คืนได้
    }
    final encoded = jsonEncode(merged); // EN: Serialize the bounded, deduplicated history. TH: serialize ประวัติที่จำกัดขนาดและตัดรายการซ้ำแล้ว
    if (!_fitsStorageLimit(encoded)) {
      // EN: Refuse migration rather than store beyond the byte budget. TH: ปฏิเสธ migration แทนการเก็บเกินเพดาน byte
      return; // EN: Leave plaintext available for a later migration attempt. TH: คง plaintext ไว้ให้ลองย้ายภายหลัง
    }
    await _secureStore.write(secureKey, encoded);
    // EN: Remove only valid plaintext sources after verified secure readback.
    // TH: ลบเฉพาะแหล่ง plaintext ที่ถูกต้องหลังตรวจข้อมูล secure ที่อ่านกลับ
    final migrated = await _secureStore.read(secureKey);
    if (migrated != encoded || !_isValidEncodedHistory(migrated!)) {
      // EN: Keep plaintext unless readback exactly matches the secure write.
      // TH: คง plaintext ไว้ เว้นแต่ข้อมูล secure ที่อ่านกลับตรงกับที่เขียนทุกประการ
      return; // EN: Avoid deleting the recoverable source after a failed write. TH: ป้องกันการลบต้นทางที่กู้คืนได้เมื่อเขียนไม่สำเร็จ
    }
    for (final entry in legacySources.entries) {
      // EN: Remove only sources independently validated as history JSON. TH: ลบเฉพาะแหล่งที่ตรวจแล้วว่าเป็น JSON ประวัติที่ใช้ได้
      if (_isValidEncodedHistory(entry.value)) await prefs.remove(entry.key);
    }
  }

  List<Map<String, dynamic>>? _mergeLegacyHistories(Iterable<String> sources) {
    // EN: Merge valid records while preserving first-seen IDs and enforcing the row cap.
    // TH: รวม record ที่ถูกต้อง คง ID ที่พบก่อน และบังคับเพดานจำนวนรายการ
    final merged = <Map<String, dynamic>>[];
    final seenIds = <String>{};
    var sawValidSource = false;
    for (final source in sources) {
      if (!_isValidEncodedHistory(source)) {
        // EN: Ignore a malformed source without deleting or trusting it. TH: ข้ามแหล่งผิดรูปโดยไม่ลบหรือเชื่อถือข้อมูล
        continue; // EN: Inspect the next candidate source. TH: ตรวจแหล่งข้อมูลถัดไป
      }
      sawValidSource = true;
      final decoded = jsonDecode(source) as List<dynamic>;
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) {
          // EN: Skip list entries that are not JSON objects. TH: ข้ามรายการที่ไม่ใช่ JSON object
          continue; // EN: Continue with the next history entry. TH: ตรวจประวัติรายการถัดไป
        }
        final id = item['id'];
        if (id is! String || id.isEmpty || !seenIds.add(id)) {
          // EN: Reject missing, empty, or duplicate stable IDs. TH: ปฏิเสธ ID ที่หาย ว่าง หรือซ้ำ
          continue; // EN: Continue without admitting this entry. TH: ข้ามโดยไม่รับรายการนี้
        }
        try {
          AlertRecord.fromJson(item);
          merged.add(item);
        } on FormatException {
          seenIds.remove(id);
        } on TypeError {
          seenIds.remove(id);
        } on UnsupportedError {
          seenIds.remove(id);
        }
        if (merged.length >= maxEntries) {
          // EN: Stop scanning once the retention cap is reached. TH: หยุดสแกนเมื่อถึงเพดานเก็บข้อมูล
          break; // EN: Keep memory and output bounded. TH: จำกัดหน่วยความจำและผลลัพธ์
        }
      }
      if (merged.length >= maxEntries) {
        // EN: Do not inspect more sources after filling the capped result. TH: ไม่อ่านแหล่งเพิ่มเมื่อผลลัพธ์เต็มเพดาน
        break; // EN: Finish the bounded merge. TH: จบการรวมข้อมูลแบบจำกัด
      }
    }
    if (!sawValidSource) {
      // EN: Distinguish no usable source from a valid empty history. TH: แยกกรณีไม่มีแหล่งใช้ได้จากประวัติว่างที่ถูกต้อง
      return null; // EN: Preserve source data when migration has no valid input. TH: คงข้อมูลต้นทางเมื่อไม่มี input สำหรับ migration ที่ถูกต้อง
    }
    return merged; // EN: Return valid merged entries, including a valid empty list. TH: คืนรายการที่รวมแล้ว แม้เป็น list ว่างที่ถูกต้อง
  }

  bool _isValidEncodedHistory(String raw) {
    // EN: Reject oversized strings before allocating a UTF-8 copy.
    // TH: ปฏิเสธ string ที่ใหญ่เกินก่อนสร้างสำเนา UTF-8 ในหน่วยความจำ
    if (!_fitsStorageLimit(raw)) return false;
    try {
      return jsonDecode(raw) is List<dynamic>;
    } on FormatException {
      return false;
    }
  }

  Future<List<AlertRecord>> loadAlerts() async {
    // EN: Read only the currently scoped encrypted record. TH: อ่านเฉพาะ record เข้ารหัสของ scope ปัจจุบัน
    final scope = _scopeId; // EN: Capture the current account before any asynchronous read. TH: จับบัญชีปัจจุบันไว้ก่อนอ่านข้อมูลแบบ async
    if (_invalidatedScopes.contains(scope)) { // EN: Refuse history for an account already deleted remotely. TH: งดอ่านประวัติของบัญชีที่ลบจาก server แล้ว
      return []; // EN: Do not expose a stale record if local cleanup failed. TH: ไม่แสดง record เก่าหากล้างข้อมูลในเครื่องไม่สำเร็จ
    } // EN: Finish the account-deletion read fence. TH: จบการกั้นการอ่านหลังลบบัญชี
    final raw = await _secureStore.read( // EN: Read the captured account's encrypted history. TH: อ่านประวัติเข้ารหัสของบัญชีที่จับไว้
        'doz.$scope.alert_history.secure.v1'); // EN: Never switch to another account's key after awaiting. TH: ไม่เปลี่ยนไปอ่าน key ของบัญชีอื่นหลัง await
    if (_invalidatedScopes.contains(scope)) { // EN: Catch account deletion that occurred during the read. TH: ตรวจว่าบัญชีถูกลบระหว่างรออ่านหรือไม่
      return []; // EN: Hide stale history after a concurrent deletion. TH: ซ่อนประวัติเก่าหลังการลบที่เกิดพร้อมกัน
    } // EN: Finish the post-read deletion check. TH: จบการตรวจการลบหลังอ่าน
    if (raw == null || raw.isEmpty) {
      // EN: Treat absent storage as an empty history. TH: ถือ storage ที่ไม่มีข้อมูลเป็นประวัติว่าง
      return []; // EN: Avoid decoding a missing value. TH: ไม่ decode ค่าที่ไม่มี
    }
    // EN: Check size and container shape before decoding persisted user data.
    // TH: ตรวจขนาดและชนิด container ก่อนถอดรหัสข้อมูลผู้ใช้ที่บันทึกไว้
    if (!_fitsStorageLimit(raw)) {
      // EN: Refuse oversized persisted data before JSON decoding. TH: ปฏิเสธข้อมูลที่เกินเพดานก่อน decode JSON
      return []; // EN: Keep an invalid large value out of app state. TH: กันค่าขนาดใหญ่ที่ผิดออกจาก state ของแอป
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        // EN: Require the expected top-level history list. TH: บังคับโครงสร้างชั้นบนเป็น list ประวัติ
        return []; // EN: Do not interpret another JSON shape as alert history. TH: อย่าตีความ JSON รูปแบบอื่นเป็นประวัติแจ้งเตือน
      }
      final records = <AlertRecord>[];
      for (final item in decoded.take(maxEntries)) {
        if (item is! Map<String, dynamic>) {
          // EN: Skip entries that cannot represent a record object. TH: ข้ามรายการที่ไม่ใช่ object ของ record
          continue; // EN: Continue loading valid neighboring records. TH: โหลด record ที่ถูกต้องรายการถัดไป
        }
        try {
          records.add(AlertRecord.fromJson(item));
        } on FormatException {
          continue;
        } on TypeError {
          continue;
        } on UnsupportedError {
          continue;
        }
      }
      return records; // EN: Return only records that passed model validation. TH: คืนเฉพาะ record ที่ผ่าน validation ของ model
    } on FormatException {
      // EN: Preserve the malformed value for recovery, but keep the app usable.
      // TH: คงข้อมูลที่ผิดรูปแบบไว้ให้กู้คืนได้ แต่ไม่ให้แอปหยุดทำงาน
      return [];
    }
  }

  Future<void> saveAlerts(List<AlertRecord> alerts) async {
    // EN: Capture the account before building asynchronous work. TH: จับบัญชีก่อนสร้างงาน asynchronous
    final scope = _scopeId;
    if (_invalidatedScopes.contains(scope)) {
      // EN: Check whether deletion fenced this scope. TH: ตรวจว่า scope นี้ถูกกั้นหลังลบหรือไม่
      return; // EN: Refuse to recreate deleted history. TH: ปฏิเสธการสร้างประวัติของบัญชีที่ลบแล้วกลับมา
    } // EN: Continue only for an active scope. TH: ทำต่อเฉพาะ scope ที่ active
    // EN: Keep newest-first entries and trim old rows until under the byte budget.
    // TH: เก็บรายการใหม่ก่อนและตัดรายการเก่าจนอยู่ในงบขนาดข้อมูล
    final retained = alerts.take(maxEntries).toList(); // EN: Keep only the newest bounded input entries. TH: เก็บเฉพาะรายการใหม่สุดตามเพดาน
    var encoded = jsonEncode(retained.map((alert) => alert.toJson()).toList());
    while (!_fitsStorageLimit(encoded) && retained.isNotEmpty) {
      retained.removeLast();
      encoded = jsonEncode(retained.map((alert) => alert.toJson()).toList());
    }
    await _enqueueStorageOperation(scope, () async {
      // EN: Serialize the secure history write. TH: จัดลำดับการเขียนประวัติแบบ secure
      await _secureStore.write('doz.$scope.alert_history.secure.v1',
          encoded); // EN: Store history under the captured account. TH: เก็บประวัติใต้บัญชีที่ snapshot
    }); // EN: Wait until the queued write finishes. TH: รอจน write ที่เข้าคิวเสร็จ
  }

  Future<void> clearAlerts({String? scopeId}) async {
    // EN: Snapshot both account-scoped keys before asynchronous storage operations.
    // TH: เก็บ key ของบัญชีทั้งสองแหล่งไว้ก่อนเริ่มงาน storage แบบ async
    final scope = validateStorageScope(scopeId ?? _scopeId);
    final secureKey = 'doz.$scope.alert_history.secure.v1';
    final legacyKey = 'doz.$scope.alert_history';
    await _enqueueStorageOperation(scope, () async {
      // EN: Wait behind earlier writes before deleting history. TH: รอ write ก่อนหน้าก่อนลบประวัติ
      await _secureStore.delete(
          secureKey); // EN: Delete the captured account's secure history. TH: ลบประวัติ secure ของบัญชีที่ snapshot
      final prefs = await SharedPreferences
          .getInstance(); // EN: Open preferences for legacy cleanup. TH: เปิด preferences เพื่อล้าง legacy
      await prefs.remove(
          legacyKey); // EN: Remove only the captured account's legacy history. TH: ลบเฉพาะ legacy history ของบัญชีที่ snapshot
      if (scope == 'local-demo') {
        // EN: Clean the unscoped legacy key only for the demo scope. TH: ลบ legacy key ที่ไม่มี scope เฉพาะ local-demo
        await prefs.remove(
            'doz_alert_history'); // EN: Remove the demo-only legacy value. TH: ลบค่า legacy เฉพาะ demo
      } // EN: Finish conditional legacy cleanup. TH: จบการล้าง legacy ตามเงื่อนไข
    },
        allowInvalidated:
            true); // EN: Allow the authorized cleanup operation. TH: อนุญาต operation ล้างข้อมูลที่จำเป็น
  }

  Future<void> _enqueueStorageOperation(
      // EN: Serialize secure history operations per account. TH: จัดลำดับงาน secure history แยกตามบัญชี
      String
          scope, // EN: Identify the queue for the captured account. TH: ระบุคิวของบัญชีที่ snapshot
      Future<void> Function()
          operation, // EN: Accept one asynchronous storage operation. TH: รับ storage operation แบบ async หนึ่งรายการ
      {bool allowInvalidated =
          false} // EN: Permit clear while blocking normal writes. TH: อนุญาต clear แต่บล็อก write ปกติ
      ) async {
    // EN: Complete after this operation leaves the queue. TH: ทำงานเสร็จเมื่อ operation นี้ออกจากคิว
    final previous = _storageQueues[scope] ??
        Future<
            void>.value(); // EN: Chain after the previous account operation. TH: ต่อท้าย operation ก่อนหน้าของบัญชี
    final next = previous.catchError((Object _) {}).then((_) async {
      // EN: Recover the queue after a previous failure. TH: กู้คิวหลังงานก่อนหน้าล้มเหลว
      if (!allowInvalidated && _invalidatedScopes.contains(scope)) {
        // EN: Check the deletion fence before running normal storage work. TH: ตรวจตัวกั้นการลบก่อนทำ storage ปกติ
        return; // EN: Skip work that could recreate deleted data. TH: ข้ามงานที่อาจสร้างข้อมูลที่ลบแล้วกลับมา
      } // EN: Continue for normal scopes or authorized cleanup. TH: ทำต่อสำหรับ scope ปกติหรือการล้างที่อนุญาต
      await operation(); // EN: Run the queued storage operation. TH: ทำ storage operation ที่เข้าคิว
    }); // EN: Build the future representing this queued operation. TH: สร้าง future แทน operation ที่เข้าคิว
    _storageQueues[scope] =
        next; // EN: Publish the pending operation so clear can wait for it. TH: เผยแพร่ operation ที่ค้างเพื่อให้ clear รอได้
    try {
      // EN: Preserve operation errors for the caller. TH: ส่ง error ของ operation กลับให้ caller
      await next; // EN: Wait for this serialized operation. TH: รอ operation ที่จัดลำดับนี้
    } finally {
      // EN: Clean up the queue entry even on failure. TH: ล้างรายการคิวแม้งานล้มเหลว
      if (identical(_storageQueues[scope], next)) {
        // EN: Do not remove a newer operation queued behind this one. TH: อย่าลบ operation ใหม่ที่เข้าคิวต่อจากรายการนี้
        _storageQueues.remove(
            scope); // EN: Release the completed account queue. TH: คืนคิวของบัญชีที่ทำเสร็จ
      } // EN: Finish checking the current queue future. TH: จบการตรวจ future ปัจจุบันของคิว
    } // EN: Finish serialized-operation cleanup. TH: จบการล้างหลัง operation แบบจัดลำดับ
  } // EN: Finish the queue helper. TH: จบ helper ของคิว

  bool _fitsStorageLimit(
          String
              value) => // EN: Check a cheap character bound before the exact byte count. TH: ตรวจขอบเขตจำนวนตัวอักษรที่คำนวณง่ายก่อนนับ byte จริง
      value.length <= maxEncodedBytes &&
      _utf8Length(value) <=
          maxEncodedBytes; // EN: Enforce the actual UTF-8 storage budget. TH: บังคับงบพื้นที่เก็บ UTF-8 จริง

  int _utf8Length(String value) {
    // EN: Measure encoded bytes and fail closed on malformed text. TH: วัด byte หลังเข้ารหัสและปฏิเสธข้อความผิดรูป
    try {
      // EN: Attempt strict UTF-8 encoding. TH: ทดลองเข้ารหัส UTF-8 แบบ strict
      return utf8
          .encode(value)
          .length; // EN: Return the exact encoded-byte count. TH: คืนจำนวน byte หลังเข้ารหัสจริง
    } on FormatException {
      // EN: Treat malformed Unicode as over the storage limit. TH: ถือ Unicode ที่ผิดรูปว่าเกินขนาด storage
      return maxEncodedBytes +
          1; // EN: Force rejection without retaining malformed data. TH: บังคับปฏิเสธโดยไม่เก็บข้อมูลผิดรูป
    } on ArgumentError {
      // EN: Fail closed on encoder argument errors. TH: ปฏิเสธเมื่อ encoder พบ argument ผิด
      return maxEncodedBytes +
          1; // EN: Keep invalid strings out of secure storage. TH: กัน string ที่ไม่ถูกต้องออกจาก secure storage
    }
  } // EN: Finish UTF-8 length calculation. TH: จบการคำนวณความยาว UTF-8
}
