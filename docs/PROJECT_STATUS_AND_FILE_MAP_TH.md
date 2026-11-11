# Doz / VitaGuard — แผนผังระบบและสถานะความพร้อม

อัปเดต 12 พ.ย. 2026 จากการตรวจไฟล์ใน `/Users/norapol/Downloads/Doz` และผลทดสอบที่รันในเครื่อง

## สถานะสั้น ๆ

**ยังไม่พร้อมใช้งานจริงหรือผลิตเป็นอุปกรณ์ตรวจจับความง่วง** แม้ส่วนแอปและ unit tests หลายส่วนทำงานได้ เหตุผลหลักคือยังไม่มีชุดข้อมูลที่มี ground truth `alert/drowsiness` จากฮาร์ดแวร์จริงที่ยืนยันได้, firmware ยังไม่ได้ทำ signal-processing/feature extraction ให้ตรงกับ trainer แบบครบวงจร และยังไม่มีผลทดสอบบน ESP32-S3/อุปกรณ์ประกอบจริง

| ส่วน | สถานะตรวจได้ | ใช้ทำอะไรได้ตอนนี้ | ยังห้ามสรุปว่า |
|---|---|---|---|
| Flutter app (`app/`) | `flutter analyze` ผ่าน; **135 tests ผ่าน 12 พ.ย. 2026** หลังเพิ่ม BLE fragment bounds | พัฒนา UI, ทดสอบ BLE/UI ด้วย mock และทดสอบการแสดงสถานะ | ผ่านการทดสอบกับบอร์ดจริงหรือใช้เพื่อความปลอดภัยแล้ว |
| Cloud API (`app/cloud_api/`) | API tests 48 ผ่านใน Python 3.11; Render deploy `8612060` Live เมื่อ 12 พ.ย.; `GET /health` และ `/` ตอบ HTTP 200 | ทดสอบ auth, chat, rate-limit, payload cap, nested sensor validation, Firestore device read/write limits, advice guardrail, env bounds และ storage fail-closed | `/chat` ทำงานทุกกรณี หรือข้อมูลสุขภาพพร้อมเปิด sync; ยังไม่ได้ยืนยัน authenticated live `/chat` หลัง deploy |
| Sensor capture / host pipeline | มี sketch อ่านข้อมูลและ host pipeline พร้อม tests | บันทึก/เล่นซ้ำข้อมูลและทดสอบ quality gates | preprocessing บน ESP32 ตรงกับ training แล้ว |
| AI training | มี trainer หลายเส้นทาง; baseline wearable ถูกบล็อกเมื่อไม่มี labeled hardware data | ตรวจ schema/ทดลองงานวิจัยบน dataset ที่ระบุชัดว่า proxy | metric จาก DROZY/WESAD/FatigueSet เป็นประสิทธิภาพบน MAX30102/MPU6050 |
| ESP32 inference | C++ runtime stub ผ่าน compile/test | ทดสอบ guard และ model integration แบบ host/stub | firmware อ่าน sensor→คำนวณ features→predict ได้ครบ หรือผ่าน 100,000 รอบบนฮาร์ดแวร์ |
| FatigueSet export | สร้าง aligned raw-channel export 72 ไฟล์ | ทดลอง data ingestion/เวลา/คุณภาพข้อมูล | เป็น MAX30102/MPU6050 หรือมี drowsiness ground truth |
| PCB / case | มีไฟล์ KiCad/3D หลายรุ่นและสำเนา | เปิดตรวจแบบแยกตามรุ่น | พร้อมผลิตโดยไม่ล็อก revision และตรวจ DRC/DFM/ประกอบจริง |

> การทดสอบที่ผ่านด้านบนเป็นหลักฐานของซอฟต์แวร์เฉพาะชุดที่ระบุ ไม่ใช่การรับรองระบบทั้งหมดหรืออุปกรณ์ทางการแพทย์

## แผนผังไฟล์: เส้นทางใช้งานหลัก

### 1. แอปมือถือ

| ไฟล์/โฟลเดอร์ | บทบาท | สถานะ |
|---|---|---|
| `app/pubspec.yaml` | dependencies และ metadata ของ Flutter | ใช้ build แอป |
| `app/lib/main.dart` | bootstrap, routing และ state หลัก | entry point |
| `app/lib/screens/` | หน้าจอ dashboard, BLE device, graph, history, profile, setup, chat, auth | runtime UI |
| `app/lib/services/ble_service.dart` | scan/connect/รับ notification จาก BLE | runtime service; ต้องยืนยัน protocol กับ firmware รุ่นที่จะใช้ |
| `app/lib/services/ble_frame_assembler.dart` | ประกอบ BLE frame ที่ถูกแบ่งเป็นหลาย packet; จำกัด payload 14 byte/fragment, ไม่เกิน 14 fragments และรวมไม่เกิน 191 bytes | helper ที่ใช้ร่วมกับ BLE; ตรงกับ firmware buffer/protocol ปัจจุบัน |
| `app/lib/services/alert_storage_service.dart` | โหลด/บันทึกประวัติ alert แบบแยก scope | ใช้งาน; platform secure storage, จำกัด 500 รายการ/1 MiB; รวม legacy scoped/global ก่อนลบ plaintext |
| `app/lib/services/secure_local_storage.dart` | Keychain/Keystore adapter และย้าย profile/health fields จาก SharedPreferences | runtime storage; fail closed เมื่อระบบจัดเก็บปลอดภัยล้มเหลว |
| `app/lib/services/device_risk_mapper.dart` | แปลง class/alert จาก BLE binary รุ่นเก่าเป็นข้อความ UI; ปฏิเสธ enum/confidence ผิดช่วงเป็น Warning ที่ใช้วิเคราะห์ไม่ได้ | legacy compatibility เท่านั้น; JSON v1 telemetry ปัจจุบันส่ง `ai:false` และไม่เรียก mapper นี้ |
| `app/lib/services/risk_analyzer.dart` | ตัววิเคราะห์ risk แบบ local รุ่นเก่า | **ไม่พบ reference จาก runtime หรือ tests ใน `app/` ณ 12 พ.ย. 2026**; จัดเป็น unreferenced candidate, ยังไม่ลบจนกว่าจะตรวจทุก platform entry/build flavor |
| `app/lib/services/mock_data_service.dart` | ข้อมูลจำลองสำหรับ UI | **ห้ามใช้เป็นข้อมูล sensor จริงหรือข้อมูล train** |
| `app/test/` | widget, auth, BLE, safety presentation tests | ใช้ `flutter test` |

### 2. Cloud API / Render

| ไฟล์ | บทบาท | สถานะ |
|---|---|---|
| `app/cloud_api/main.py` | FastAPI routes, Supabase token verification, chat, health-data routes | entry point ของ API |
| `app/cloud_api/render.yaml` | Render service config; `rootDir: app/cloud_api` | ใช้ deploy เมื่อ blueprint ผูก repo/branch ถูกต้อง |
| `app/cloud_api/requirements.txt` | Python dependencies | ควร pin/lock หลังตรวจ compatibility ก่อน release |
| `app/cloud_api/.env.example` | รายชื่อตัวแปรตัวอย่าง | ห้ามใส่ secret จริง/ห้าม commit `.env` |
| `app/cloud_api/test_*.py` | API/auth/preflight tests | ใช้ `python3 -m pytest app/cloud_api/test_chat_auth.py app/cloud_api/test_preflight_chat.py -v` |

`app/build_apps.sh` เป็นสคริปต์ canonical สำหรับ release; `app/scripts/build_apps.sh` เป็น compatibility wrapper ที่ส่งต่อ arguments ไปสคริปต์หลัก ไม่ควรแก้ซ้ำสองจุด ตัวตรวจ release และ Auth ในแอปอนุญาต `sb_publishable_` หรือ legacy JWT ที่ payload มี `role=anon` เท่านั้น และปฏิเสธ `service_role`, `sb_secret_` และ URL ที่ไม่ใช่ HTTPS project origin

ค่าเริ่มต้น `HEALTH_DATA_SYNC_ENABLED=false` ปิดการเก็บ/อ่านข้อมูลสุขภาพบน cloud แบบ fail-closed ไว้ เมื่อเปิด sync ต้องมี Firestore พร้อมใช้งาน หรือเลือก `HEALTH_DATA_MEMORY_STORAGE_ENABLED=true` อย่างชัดเจนสำหรับทดสอบเท่านั้น; โหมด memory ตอบ `memory-ephemeral` และหายเมื่อ process restart ส่วน Firestore write failure จะตอบ 503 ก่อนเพิ่ม RAM copy. ห้ามเปิดบน production จนกว่าจะตรวจ retention, access policy, deletion, Firestore rules และ privacy notice ครบ

Render service `Drive-alert` ใช้ repo `norapolamarit-commits/Drive-alert`, branch `render-api-deploy`; commit `8612060` ขึ้น Live เมื่อ 12 พ.ย. และ `GET /health`, `GET /` ตอบ HTTP 200. Log จาก deploy ก่อนหน้าเคยมี `POST /chat` → 503; ยังไม่มีผลยืนยัน `/chat` หลัง deploy. ข้อความ `{"detail":"Bad Request"}` ยังระบุสาเหตุเฉพาะไม่ได้หากไม่มี method/path/status/time ที่ตรงกับ log. ใน source ปัจจุบันจุด HTTP 400 ที่ทราบแน่ชัดคือ `Content-Length` ของ POST ใน middleware ไม่ใช่จำนวนเต็ม; request body ห้ามส่งต่อเพื่อ debug เพราะอาจมีข้อมูลสุขภาพ/token. `/chat` ต้องเป็น POST JSON ที่มี `question`/`prompt` และ Bearer token.

วันที่ 11 พ.ย. 2026 ตรวจ `_apply_guardrails()` พบว่าหากตัวกรองลบทุกบรรทัดที่เสี่ยงออก ฟังก์ชันกลับคืนข้อความต้นฉบับ ซึ่งข้าม guardrail ได้ แก้ให้ fail closed ด้วยข้อความปฏิเสธแบบปลอดภัย และเพิ่ม regression tests สำหรับกรณีข้อความเสี่ยงทั้งหมด/ข้อความผสมแล้ว การกรองคำด้วย regex ยังไม่ใช่การรับรองเนื้อหา AI ว่าปลอดภัยทุกกรณี

เพิ่มการตรวจ payload sensor ซ้อนชั้น: `sensorData` ต้องเป็น object, ตัวเลขต้อง finite และไม่รับ boolean เป็นตัวเลข; `deviceId` ต้องไม่ว่าง ยาวไม่เกิน 128 ตัว และไม่มี `/` ก่อนใช้เป็น Firestore path ทั้ง event sensor/alert ที่ไม่ผ่านถูกปฏิเสธด้วย 422 ก่อนเก็บข้อมูล (API regression suite ปัจจุบัน 48 ผ่าน)

แก้ GET `/sensor`, `/alert`, `/devices` ให้อ่านข้อมูลจาก Firestore ของ user ที่ยืนยัน token แล้ว ไม่พึ่งเฉพาะ RAM ของ worker; จำกัดผลอ่านไม่เกิน 16 device collections และเพิ่ม tests สำหรับการรวมลำดับเวลา, กรอง user อื่น และเพดาน device. การเขียนอุปกรณ์/ข้อมูลใช้ Firestore transaction และ registry ต่อผู้ใช้เพื่อบังคับเพดานข้าม worker; การอ่านยังอาจสูงสุด 8,000 documents ต่อ request ที่ `limit=500` จึงควรเพิ่ม pagination/index ก่อนขยายการใช้งาน.

เพิ่มขอบเขต local alert history: จำกัด 500 รายการและ 1 MiB, ข้าม record ที่ไม่ถูกต้อง และย้ายข้อมูลเก่าเข้า secure storage หลังตรวจอ่านกลับ; เมื่อมี global และ scoped history จะรวม ID ที่ไม่ซ้ำก่อนลบข้อมูลต้นทาง เพิ่มการจัดเก็บโปรไฟล์/สุขภาพด้วย platform secure storage และปิด Android backup เพื่อหลีกเลี่ยงสำรองข้อมูลอ่อนไหวโดยไม่ตั้งใจ

### 3. เก็บข้อมูลและฝึก AI

| ไฟล์ | บทบาท | ใช้เมื่อ |
|---|---|---|
| `drowines/device/firmware/max30102_mpu6050_pipeline/max30102_mpu6050_stream_esp32.ino` | อ่าน/ส่งข้อมูลจาก sensor บนบอร์ด | capture จริงหลังตรวจ wiring และ sensor |
| `drowines/device/firmware/max30102_mpu6050_pipeline/sensor_ai_pipeline.py` | host parser, quality checks, features, model replay/logging | ทดสอบบน host; จำกัด JSONL/raw counts; สร้าง log แบบ exclusive permission 0600 และบังคับ safe IDs; `joblib` ต้อง opt-in พร้อมตรวจ SHA-256; ไม่เท่ากับ embedded inference |
| `drowines/device/firmware/max30102_mpu6050_pipeline/test_sensor_ai_pipeline.py` | tests ของ parser/quality/features/baseline | ใช้ `python3 -m unittest discover -s drowines/device/firmware/max30102_mpu6050_pipeline -p 'test_*.py' -v` |
| `workflows/sensor_ai/train_sensor_ai.py` | schema gate สำหรับ feature table 14 ค่า | ใช้เมื่อมี labeled wearable CSV จริงเท่านั้น |
| `workflows/ai_board/train_real_data.py` | Random Forest subject-disjoint trainer/exporter | trainer baseline ปัจจุบันตาม `workflows/sensor_ai/README_TH.md` |
| `workflows/sensor_ai/train_sensor_cnn1d.py` | CNN1D research alternative สำหรับลำดับ feature windows | ทดลองเปรียบเทียบ; ไม่ใช่ production default |
| `workflows/sensor_ai/train_sensor_cnn_lstm.py` | CNN-LSTM research alternative | ทดลองเท่านั้น |
| `workflows/sensor_ai/simulate_sensor_stream.py` | สร้าง stream จำลองเพื่อทดสอบ parser/fault guards | **ไม่ใช้ train/รายงาน performance** |
| `workflows/sensor_ai/sensor_pseudolabel.py`, `train_*pseudolabel*` | เลือก pseudo-label จากโมเดล/ข้อมูลไม่มี label | research-only; ไม่ใช้สร้าง ground truth หรือปล่อยรุ่นแรก |
| `workflows/sensor_ai/model_release.py` | host-side signing/verification gate | ไม่ได้ทำให้ firmware รับ OTA/rollback ได้เอง |

สคริปต์ `workflows/sensor_ai/train_drozy_*`, `train_dd_database_ecg_cnn1d.py` และ `train_mpd_ecg_cnn1d.py` เป็นการทดลองกับ dataset/target proxy (เช่นวิดีโอ/ECG) ไม่ใช่เส้นทางฝึก wearable MAX30102+MPU6050. `train_sensor_ai.py` เป็น gate ของ schema 14 features แล้วเรียก `workflows/ai_board/train_real_data.py`; `train_sensor_cnn1d.py` และ `train_sensor_cnn_lstm.py` เป็น trainer ทางเลือกคนละเส้นทาง ยังไม่ใช่ production default. ดูผล references/เงื่อนไขล่าสุดใน `workflows/sensor_ai/README_TH.md` ก่อนใช้แต่ละ trainer.

คำสั่งดู schema/ตัวเลือก:

```bash
cd /Users/norapol/Downloads/Doz
python3 workflows/sensor_ai/train_sensor_ai.py --help
python3 workflows/ai_board/train_real_data.py --help
```

อย่ารัน train โดยใช้ path ตัวอย่าง `/path/จริง/...` หรือไฟล์ template ว่าง ต้องมี label ที่ยืนยันจาก protocol และ split แยกผู้เข้าร่วม/วิดีโอ/session ก่อน

### 4. Firmware / hardware

| ไฟล์/โฟลเดอร์ | บทบาท | สถานะ |
|---|---|---|
| `workflows/sensor_ai/esp32/` | runtime C++ guard และตัวอย่าง inference adapter | มี unit/stub test; ยังต้อง parity กับ preprocessing จริง |
| `workflows/ai_board/esp32_benchmark_harness/` | firmware สำหรับ benchmark | ไม่ใช่ firmware ผลิต |
| `firmware/deployment_manifest.json` | release gate สถานะ upload/benchmark | ปัจจุบันระบุ `BLOCKED_MODEL_AND_REAL_HELD_OUT_DATA_REQUIRED` |
| `devices/`, `pcb/`, `hardware 2/` | KiCad/PCB/3D ที่มีหลาย revision/สำเนา | **ยังไม่มี source-of-truth ที่ยืนยันในเอกสารนี้**; ห้ามสั่งผลิตจากชื่อไฟล์อย่างเดียว |
| `Doz_3D_Print/` และ `devices/case_concept_new/` | STL/Blender/OpenSCAD case concepts | เลือก revision และเทียบกับ PCB/ชิ้นส่วนจริงก่อนพิมพ์ |

## ไฟล์ที่ไม่ควรใช้เป็น production input

- `workflows/sensor_ai/tests/`, `tests/esp32_runtime_stub/`, `app/test/`: tests/fixtures เท่านั้น
- `simulate_sensor_stream.py`, `analysis/synthetic/`, mock data ในแอป: ข้อมูลจำลอง ไม่ใช่หลักฐานการฝึก
- โฟลเดอร์ `*_proxy_*`, `*_synthetic_*`, `*_pseudolabel_*` และรายงานจาก DROZY/WESAD/ECG: งานวิจัย/คนละ sensor หรือคนละ target; ต้องติดป้าย proxy ชัดเจน
- `*.blend1`, `*.kicad_prl`, `.dart_tool/`, `build/`, `__pycache__/`, `.venv*/`, `.pytest_cache/`: backup/cache/environment/generated; ไม่ใช่ source-of-truth และไม่ควรจัดมือ/commit โดยไม่จำเป็น
- `index.html`, `app.js`, `style.css` ที่รากโปรเจกต์ และ `app/smart_health_risk_alert_watch/`, `app/files/`, `app/outputs/`: เว็บไซต์/งานเก่าหรือแพ็กผลลัพธ์; ยังไม่ใช่เส้นทาง build Flutter ตามหลักฐานปัจจุบัน

**ยังไม่ย้ายหรือลบไฟล์เก่า** เพราะ working tree มีการแก้ไขและไฟล์ใหม่ค้างอยู่จำนวนมาก การย้ายตอนนี้เสี่ยงทำลายสำเนางาน/ลิงก์ build เอกสารนี้ทำหน้าที่แยกประเภทก่อน ให้ตรวจ dependency references แล้วค่อย archive ในงานแยก

## สัญญาระหว่างระบบที่ยังต้องล็อก

1. App mapper ปัจจุบันรู้จัก class `Normal/Drowsiness/High-Stress` ขณะที่ wearable Round 1 trainer กำหนด `alert/drowsiness` สองคลาส — **class index และ version ยังไม่ตรงกัน** จึงต้องเลือก label map/model protocol เดียวและเพิ่ม integration test ก่อนเชื่อผลบนแอป
2. BLE ต้องล็อก service UUID, characteristic UUID, packet version/length, sequence/reassembly, units, class enum, alert enum และ stale timeout ไว้ในเอกสาร protocol กลาง; เปลี่ยนฝั่งเดียวไม่ได้. Timestamp ซ้ำ/ย้อนถูกกรองแล้วใน connection เดียว แต่ BLE ยังไม่มี cryptographic device authentication/replay protection; UI จึงเตือนว่า telemetry ยังไม่ผ่านการยืนยันตัวตน
3. Firmware stream sketch ส่ง sensor telemetry แต่ไม่ได้แปลว่า AI บนบอร์ดพร้อม ต้องทำ filter/window/feature extraction/quality gate ให้ตรงกับ trainer และทดสอบ host-vs-board parity
4. Dataset FatigueSet export ใช้ timestamp PPG เป็น master, จับคู่ IMU ภายใน 5 ms; ค่าที่จับคู่ไม่ได้เป็น missing ไม่ได้เติมเอง คะแนน fatigue เป็น event ไม่ใช่ dense drowsiness label ดูที่ `drowines/device/datasets/FatigueSet_raw_aligned_20261111/README.txt`
5. ห้ามอ้าง Macro-F1 ≥ 0.80/0.85, real-time, battery-life, medical/safety readiness หากไม่มี evaluation artifact และการทดสอบจริงที่ผูกกับ model hash, dataset split และ firmware hash

## ผลตรวจที่รันในเครื่อง

- `flutter analyze` จาก root: ผ่าน (ควรรันซ้ำจาก `app/` เพื่อผูกกับ Flutter package ที่ถูกต้อง)
- `cd app && flutter test --no-pub`: **135 tests ผ่าน** เมื่อ 12 พ.ย. 2026 หลังเพิ่ม fail-closed BLE fragment bounds และปรับ stress fixture ให้ตรงกับ firmware ที่ส่ง payload 14 byte/fragment
- `cd app && flutter build apk --debug --target-platform android-arm64 --no-pub`: build สำเร็จ; output `app/build/app/outputs/flutter-apk/app-debug.apk`, SHA-256 `cb3361817bb5a453c4b95147b9d6c40f20c3f604fc426fc166ae38a709245a31`. เป็น debug build เท่านั้น ไม่ใช่หลักฐานการทำงานบนโทรศัพท์/บอร์ดจริงหรือ release build; Gradle ยังแสดงคำเตือน plugin `package_info_plus` ใช้ Kotlin Gradle Plugin รุ่นที่ Flutter กำลังเลิกสนับสนุน
- `app/cloud_api`: **44 unittest ผ่าน** เมื่อ 12 พ.ย. 2026 ด้วย `app/cloud_api/.venv/bin/python -m unittest discover -s app/cloud_api -p 'test_*.py' -v`; มี Starlette/httpx TestClient deprecation warning จาก dependency (ทดสอบไม่ได้ล้ม)
- Render dashboard ที่เปิดอยู่: deploy ระบุ Live; `/health` ตรวจด้วย browser ได้ `{"status":"ok"}`. Logs แสดง root 404 และ `/chat` 503; `{"detail":"Bad Request"}` ยังไม่มี request metadata ที่จับคู่กับ log จึงยังฟันธงไม่ได้
- `workflows/sensor_ai/esp32/doz_runtime.cpp` + C++ stub: compile ด้วย `-Wall -Wextra -Werror` และรันผ่าน
- `drowines/device/firmware/max30102_mpu6050_pipeline`: **17 tests ผ่าน**; `py_compile` ของ pipeline/trainer และ `git diff --check` ผ่าน หลังเพิ่ม finite/range validation, timestamp monotonicity และ scaler validation
- `workflows/sensor_ai/tests/test_model_release.py`: **5 tests ผ่าน** รวมตรวจ signature, tampering, downgrade/version compatibility และการตรวจ hash ก่อนโหลด interpreter
- Python suite ทั้งก้อน: ยังไม่มีผลสรุป; การรันรวมค้างนานเกินปกติและถูกหยุดเพื่อแยกทดสอบ ไม่ถือว่าผ่าน

## คำอธิบายโค้ดไทย/อังกฤษ

ไฟล์ใหม่หรือบรรทัดที่แก้ในรอบนี้มี comment สองภาษาเมื่ออธิบาย logic ที่ไม่ตรงไปตรงมา โดยเฉพาะ `app/cloud_api/main.py` ที่เปลี่ยนไปใช้ Pydantic v2 `ConfigDict`. โค้ดเดิมมีหลายร้อยไฟล์และหลายรุ่น; ยังไม่ได้ใส่ comment ทุก statement ทุกบรรทัด เพราะการเพิ่ม comment กลไกทั่วไฟล์โดยไม่ตรวจความหมายเสี่ยงทำให้คำอธิบายผิดและบัง logic สำคัญ ให้ใช้สารบัญนี้เป็น routing และ walkthrough เฉพาะไฟล์หลักเป็นลำดับถัดไป แทนการประกาศว่าอธิบายครบทั้ง repository แล้ว
