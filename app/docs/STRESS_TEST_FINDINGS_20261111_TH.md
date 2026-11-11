# ผลจำลองสถานะและตรวจช่องโหว่แอป — 11 พ.ย. 2569

## ผลทดสอบที่รันซ้ำ

- `flutter test test/app_scenario_stress_test.dart` — ผ่าน: 10,000 กรณี deterministic, seed `20261109`.
- `flutter test --no-pub` — ผ่าน: 135 tests เมื่อ 12 พ.ย. 2569 (ตรวจซ้ำหลังเพิ่ม BLE fragment bounds และปรับ stress fixture ให้ตรงกับ firmware).
- `flutter analyze` — `No issues found`.
- `app/cloud_api/.venv/bin/python -m unittest discover -s app/cloud_api -p 'test_*.py' -v` — ผ่าน: 48 tests เมื่อ 12 พ.ย. 2569 บน Python 3.11 หลังเพิ่มการตรวจ Firestore read isolation, merge ordering และ transactional device registry; มี Starlette/httpx TestClient deprecation warning แต่ tests ผ่าน.

Stress test สุ่มสถานะ Auth/chat consent, config endpoint, BLE advertisement, ค่าข้อมูล telemetry, BLE fragment ที่สลับลำดับ, firmware version ที่ไม่รองรับ และค่า class/alert ที่อยู่นอกช่วง เพื่อยืนยัน invariant ของโค้ด ไม่มีการเชื่อมต่อบัญชีจริง โทรศัพท์จริง BLE radio, Supabase, LLM หรือ Render ในชุด 10,000 กรณี

## ประเด็นที่พบจากการทบทวน

| ระดับ | ประเด็น | หลักฐาน/ผลกระทบ | ข้อเสนอแนะ |
|---|---|---|---|
| สูงก่อนใช้ข้อมูลสุขภาพจริง | BLE discovery เชื่อชื่อที่มี substring `doz` หรือ service UUID โดยไม่มีการยืนยันตัวอุปกรณ์ | `lib/services/ble_service.dart:182-193`; อุปกรณ์ปลอมชื่อหรือประกาศ UUID เดียวกันอาจถูกเลือกได้ ส่วน decoder ตรวจ schema/range แต่ไม่ยืนยันผู้ส่ง | ทำ authenticated pairing และ message authentication (เช่น HMAC ด้วยกุญแจต่ออุปกรณ์/nonce-counter กัน replay) ก่อนแสดงข้อมูลเป็นอุปกรณ์จริง; ทดสอบ clone บนเครื่องจริงกับ firmware |
| แก้แล้วในเครื่อง | ประวัติ alert เดิมอาจเสียจาก malformed JSON/record และ migration scoped/global อาจทำข้อมูลซ้ำหรือหาย | `lib/services/alert_storage_service.dart`; เพิ่ม per-record validation, limits, secure storage, readback verification และ merge แบบ dedupe ก่อนลบ plaintext; tests ครอบคลุม migration ล้มเหลวและข้อมูลซ้ำ | ทดสอบ migration บนอุปกรณ์จริงและยืนยัน backup/delete behavior ของแต่ละ OS |
| กลางก่อน deploy หลาย replica | AI rate/concurrency limits ทำงานใน process เดียว | `cloud_api/main.py:119-151`; restart หรือเพิ่ม worker/replica ทำให้ quota แยกกัน/รีเซ็ต จึงไม่ใช่ global abuse control | ใช้ shared rate limiter เช่น Redis หรือ gateway/WAF และตั้ง quota ฝั่ง provider; ทดสอบ multi-worker |
| แก้บางส่วนในเครื่อง | โปรไฟล์/พิกัด/alert เคยอยู่ใน plaintext preferences | เพิ่ม Keychain/Keystore adapter และ migration ที่ไม่ลบ plaintext หาก secure write/readback ไม่ผ่าน; ปิด Android backup. ยังต้องทดสอบ lifecycle กับอุปกรณ์จริงทุก OS | ทดสอบ Keychain/Keystore, restore/uninstall, delete-account และ platform ที่รองรับก่อน release |
| แก้บางส่วนในเครื่อง | telemetry decoder เคยรับ `t` ที่ขาด และไม่กัน timestamp ซ้ำ/ย้อน | `lib/services/ble_service.dart`; decoder บังคับ non-negative timestamp และ runtime ปฏิเสธ duplicate/backward time ภายใน connection เดียว; tests ยืนยัน boundary | ยังไม่มี cryptographic authentication/replay protection ต่อผู้ส่งปลอม; ช่วง IMU ±2g/±250°/s ยังสมมติจาก firmware config |

## สรุป

ผล 10,000 กรณีเป็น property/stress test ของตรรกะออฟไลน์ ไม่ใช่ penetration test และไม่ยืนยันความปลอดภัยของการจับคู่ BLE หรือการใช้งานจริง การแก้ storage และ timestamp ลดความเสี่ยง แต่ BLE identity ยังไม่มี cryptographic authentication; อย่าใช้ telemetry จากอุปกรณ์ที่ยังไม่ยืนยันตัวตนเพื่อตัดสินใจด้านสุขภาพ ส่วน rate limit ยังเป็น process-local และต้องมี shared limiter ก่อน scale หลาย instance

## รันซ้ำ

```bash
cd /Users/norapol/Downloads/Doz/app
flutter test test/app_scenario_stress_test.dart
flutter test
flutter analyze
cd cloud_api
python3 -m unittest -v test_chat_auth test_preflight_chat
```
