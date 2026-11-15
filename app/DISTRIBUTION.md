# คู่มือทดสอบและแจกจ่ายแอป doz (สถานะต้นแบบ)

คู่มือฉบับละเอียดและสถานะตรวจล่าสุดอยู่ที่ [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md). ห้ามใช้ขั้นตอน release จนกว่า backend, signing และการทดสอบจริงจะผ่าน

## Android — APK สำหรับทดสอบ

สร้าง debug APK จากโฟลเดอร์ Flutter app:

```bash
cd /Users/norapol/Downloads/Doz/app
flutter build apk --debug --target-platform android-arm64
```

ไฟล์อยู่ที่ `build/app/outputs/flutter-apk/app-debug.apk`. ส่งไฟล์นี้ไปยังโทรศัพท์ Android ARM64 เพื่อทดสอบ UI/BLE scan; เป็น debug build และไม่มี Supabase configuration จึงยังใช้ login/chat ระยะไกลไม่ได้. เปิดไฟล์จาก Downloads/Files แล้วอนุญาตติดตั้งจากแหล่งนี้เมื่อ Android ถาม. ทดสอบได้ด้วย `adb install -r build/app/outputs/flutter-apk/app-debug.apk` เมื่อเชื่อมโทรศัพท์ผ่าน USB.

สำหรับ release ต้องตั้ง application ID ที่โครงการเป็นเจ้าของ, สร้างและเก็บ Android upload keystore, ตั้งค่า Supabase และ API endpoint จริง, ผ่าน chatbot preflight และทดสอบบนโทรศัพท์/บอร์ดจริงก่อน build signed APK/AAB. อย่าส่ง debug APK เป็นแอป production.

## iOS — TestFlight/App Store

การแจกผู้ใช้ต้องใช้ Apple Developer Team, Bundle Identifier ที่โครงการเป็นเจ้าของ, signing และ Xcode archive แล้วอัปโหลดผ่าน TestFlight/App Store. ปัจจุบันเครื่องพัฒนายังสร้าง iOS artifact ไม่ได้: Xcode ไม่พบ iOS 26.5 platform ที่ติดตั้ง/ลงทะเบียน และไม่มี Simulator runtime. เพิ่มพื้นที่ว่างและติดตั้ง Xcode component ก่อน; จากนั้นต้องทดสอบ install, login/deep link และ BLE บน iPhone จริงด้วย.

## Backend ที่ต้องพร้อมก่อนเปิด remote login/chat

Blueprint อยู่ที่ `app/cloud_api/render.yaml` จาก Git repository root (`Doz/`) และ service `rootDir` คือ `app/cloud_api`. ต้อง deploy web service และตั้งค่า `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `LLM_API_KEY` ใน provider dashboard; เก็บ `SUPABASE_SERVICE_ROLE_KEY` เป็น secret ฝั่ง server เท่านั้นและจำเป็นเฉพาะฟังก์ชันลบบัญชี. คง `HEALTH_DATA_SYNC_ENABLED=false` จนผ่าน privacy/security review. ห้ามใส่ service-role หรือ LLM key ใน mobile app.

สถานะตรวจ 15 พ.ย. 2569: Render service `Drive-alert` deploy API commit `3664ff1` จาก branch `render-api-deploy` ใน `app/cloud_api` แล้ว. `https://drive-alert.onrender.com/health` ตอบ HTTP 200 `{"status":"ok"}`; `/ready` ตอบ HTTP 503 เพราะยังไม่มีค่า Auth ที่จำเป็น และ `/chat` ตอบ HTTP 503 ว่ายังไม่ได้ตั้งค่า Auth. ดังนั้น health check ไม่ได้แปลว่า chatbot พร้อมใช้. URL นี้เป็น API ไม่ใช่หน้าแอป Flutter. อย่า build แอปแจกจนกว่าการตั้งค่า Auth, preflight และการทดสอบบนอุปกรณ์จริงจะผ่าน.

โค้ดแอปในเครื่องตรวจ `/ready` ก่อนแสดงว่า server พร้อมสำหรับแชต แทนการตีความ `/health` ว่า Auth พร้อม และปิดการตาม HTTP redirect ในคำขอที่มี bearer token หรือข้อมูลสุขภาพ. การแก้หน้าแอปนี้ยังอยู่ใน worktree; API บน Render ไม่ได้รวมไฟล์ Flutter ดังกล่าว.

API commit `6081eec` เพิ่ม CORS สำหรับเว็บ Flutter ที่ origin `https://doz-web.onrender.com` แบบระบุปลายทางตรงตัว หากชื่อหรือโดเมนของ static site เปลี่ยน ต้องตั้ง `DOZ_WEB_ORIGIN` บน API ให้ตรงกับ origin จริงก่อนทดสอบบน browser. คำสั่ง preflight จะตรวจ `/ready` ก่อนเรียก `/chat` และ `/advice`.

หน้า Flutter web มี Blueprint แยกใน `app/render-web.yaml` และ build script ใน `app/scripts/render_build_web.sh` ซึ่งผ่าน `render blueprints validate` และ `flutter build web --release --no-pub --no-wasm-dry-run` ในเครื่องแล้ว. ก่อน deploy ให้ตั้ง `DOZ_SUPABASE_URL` และ `DOZ_SUPABASE_PUBLISHABLE_KEY` ของ Supabase project ใน Render static site; build script จะหยุดหากขาดค่าหรือ `scripts/validate_web_config.dart` พบว่า URL/key ผิดรูปแบบ. ค่าเหล่านี้เป็น public client configuration เท่านั้น ห้ามใช้ service-role key. แก้ BLE permission flow ให้ไม่เรียก `dart:io Platform` ใน browser แล้ว แต่แอป web ยังต้องทดสอบการใช้งานจริงใน browser โดยเฉพาะ secure storage, Auth และ BLE ก่อนนับว่าพร้อมใช้งาน.

ตรวจ browser ในเครื่อง 15 พ.ย. 2569: สร้าง web release ด้วย URL/key **ทดสอบที่ไม่ใช่บัญชีจริง** แล้วเปิดผ่าน `http://127.0.0.1:8765`; หน้าเข้าสู่ระบบปรากฏและไฟล์หน้าเว็บโหลดได้. ผลนี้ยืนยันเฉพาะการเริ่ม UI ไม่ยืนยันการเข้าสู่ระบบ การเก็บข้อมูลปลอดภัยหรือ BLE ใน browser.

ไฟล์ APK ล่าสุดและผลตรวจติดตั้งอยู่ใน [รายงานทดสอบ](docs/STRESS_TEST_10000_SCENARIOS_TH.md). การผ่าน emulator ไม่แทนการทดสอบ BLE กับบอร์ดและโทรศัพท์จริง.
