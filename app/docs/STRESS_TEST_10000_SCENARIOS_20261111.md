# รายงานทดสอบแอป 10,000 สถานการณ์ — 11 พฤศจิกายน 2569

## ผลการรันทดสอบ

- หลังแก้ unknown-class fallback: `flutter test test/app_scenario_stress_test.dart` ผ่าน 10,000 สถานการณ์แบบ deterministic ด้วย seed `20261109`.
- Revalidation 12 พ.ย. 2569: full Flutter suite `flutter test --no-pub` ผ่าน 135 tests และ `flutter analyze` ผ่าน หลังเพิ่ม BLE fragment bounds; generator ใช้ payload ขนาด 10–14 bytes เพื่อจำลอง firmware ปัจจุบัน.
- Static analysis หลังแก้ล่าสุด: `flutter analyze` รายงาน `No issues found`.
- Backend revalidation 12 พ.ย. 2569: `app/cloud_api/.venv/bin/python -m unittest discover -s app/cloud_api -p 'test_*.py' -v` ผ่าน 48 tests บน Python 3.11 หลังเพิ่มการตรวจ Firestore read isolation, merge ordering และ transactional device registry. มี Starlette/httpx TestClient deprecation warning.

กรณีจำลองครอบคลุม Auth config บางชุด, การเลือก local/remote chatbot, BLE advertisement filtering, telemetry JSON ที่ถูกต้องและ firmware version ที่ไม่รองรับ, BLE fragment ที่สลับลำดับ, การ map ระดับแจ้งเตือน และ input backend ด้าน token/payload/rate limit/concurrency.

## ประเด็นที่พบจากการทบทวนโค้ด

1. **BLE ปลอมชื่อ/เล่นซ้ำข้อมูลได้ (ความเสี่ยงสูงต่อความถูกต้องของข้อมูล):** `BleService.matchesDozAdvertisement` ยอมรับอุปกรณ์ที่ชื่อมี substring `doz` หรือประกาศ UUID ตรงกัน แต่การ discover และ telemetry decoder ไม่ได้ยืนยันตัวตนอุปกรณ์ด้วย authenticated pairing/MAC. อุปกรณ์ BLE อื่นจึงอาจปลอมชื่อ/UUID และส่ง JSON ตาม schema ได้; อาจทำให้ผู้ใช้เห็นข้อมูลหรือสถานะที่ไม่ใช่จากบอร์ดจริง. Stress test ยืนยันเฉพาะตรรกะกรองแบบ offline ไม่ได้พิสูจน์การโจมตีผ่าน radio.
2. **แก้แล้ว — ค่า class ที่ไม่รู้จักเคยถูกแปลเป็น Normal:** `lib/services/device_risk_mapper.dart` ตอนนี้ fail-closed เป็น “ไม่ทราบสถานะจากอุปกรณ์”, Warning และคำแนะนำไม่ให้ใช้ผลนี้ยืนยันความปลอดภัย. Stress test ตรวจ class เดิมที่สุ่มได้ว่าห้ามกลายเป็น Safe/Normal. ยังต้องให้ firmware และแอปใช้ enum/version ตรงกัน.
3. **Rate limit/concurrency ของ API จำกัดเฉพาะ process:** ตัวนับใน `app/cloud_api/main.py` อยู่ในหน่วยความจำ process; หลาย worker/replica หรือ restart ทำให้เพดานรวมไม่คงที่. ใช้ gateway/shared store ก่อน scale production.
4. **ยังไม่มีหลักฐานทดสอบ end-to-end กับบริการและบอร์ดจริง:** รอบนี้ไม่เชื่อม Supabase/LLM จริง ไม่ทดสอบ BLE radio กับ firmware, ไม่ทำ penetration test หรือ load test และไม่ยืนยันการลบข้อมูลจริง.

## ข้อสรุป

ไม่พบ test failure. แก้ fallback ของ unknown class แล้ว แต่ยังไม่ควรตีความว่าแอปปลอดภัยหรือพร้อมใช้งานจริง: ต้องเพิ่มการผูกตัวตน/ความถูกต้องของ telemetry ระหว่างบอร์ดกับแอป และทดสอบกับอุปกรณ์จริงก่อนใช้ผลเป็นข้อมูลสุขภาพ. ผล 10,000 เคสนี้เป็นชุดตรรกะจำลอง ไม่ใช่ผู้ใช้หรืออุปกรณ์จริง 10,000 ราย.

## คำสั่งรันซ้ำ

```bash
cd /Users/norapol/Downloads/Doz/app
flutter test test/app_scenario_stress_test.dart
flutter test
flutter analyze
cd cloud_api
python3 -m pytest -q test_chat_auth.py test_preflight_chat.py
```
