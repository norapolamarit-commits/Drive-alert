# คู่มือตั้งค่าและแจกจ่ายแอป doz (ฉบับต้นแบบ)

## ขอบเขตที่แอปทำได้ในตอนนี้

- Android และ iOS ใช้ Flutter; เชื่อมต่ออุปกรณ์ผ่าน BLE เมื่ออุปกรณ์เปิดโฆษณาและใช้ GATT protocol/UUID ที่แอปรองรับ
- สมัคร/เข้าสู่ระบบ/กู้รหัสผ่านใช้ Supabase Auth เมื่อ build กำหนด URL และ publishable key; local demo ใช้ได้เฉพาะ debug build เท่านั้น ส่วน release build จะไม่เริ่มแอปต่อหากไม่ได้ตั้ง Auth ครบ
- โปรไฟล์/ข้อมูลสุขภาพและประวัติ alert ใช้ platform secure storage แยก scope ตามบัญชี ส่วนค่าตั้งค่าทั่วไปที่ไม่อ่อนไหวยังอยู่ใน SharedPreferences; การทำงานจริงต้องตรวจซ้ำบน Android/iOS แต่ละรุ่นก่อนแจก และ Android ปิด backup ของแอปไว้
- BLE telemetry ยังไม่พิสูจน์ตัวตนของผู้ส่งด้วย cryptographic pairing; แอปเตือนผู้ใช้และไม่ควรนำค่าที่รับไปใช้ตัดสินใจด้านความปลอดภัยจนกว่าจะเพิ่มการยืนยันอุปกรณ์และ replay protection
- Chatbot และคำแนะนำ AI ระยะไกลต้อง login, ใช้ HTTPS, แนบ Supabase access token และขอ consent ที่ผูกกับ endpoint; หากไม่มี consent/auth จะไม่ส่ง sensor context และใช้คำแนะนำในเครื่อง
- `cloud_api /chat`, `/advice`, `/sensor`, `/alert` และ `/devices` ตรวจ Supabase bearer token; event ที่เขียนจะผูกกับบัญชีที่ยืนยันแล้ว `/chat` และ `/advice` ใช้ process-local rate limit/concurrency guard ร่วมกัน แต่ยังไม่มี shared gateway limiter ที่ตรวจยืนยันแล้ว ส่วน route อ่าน/เขียน health data ถูกปิดฝั่ง server ด้วย `HEALTH_DATA_SYNC_ENABLED=false` จึงยังห้ามเปิด cloud health sync หรือส่งข้อมูลสุขภาพจริงจนกว่าจะผ่านการทบทวน retention/deletion, deployment security และ ownership controls

## 1. ตั้งค่า Supabase Auth

1. สร้าง Supabase project และเปิด Email/Password ใน Authentication providers
2. ตั้งค่า Site URL และ redirect allowlist ให้มี `doz://login-callback/` สำหรับ Android/iOS และ `https://doz-web.onrender.com/` สำหรับเว็บบน Render; หากเปลี่ยนโดเมนเว็บต้องเพิ่ม origin ใหม่ใน allowlist
3. ตั้งอีเมล/SMTP และตรวจ email confirmation, reset-password template กับ deep link บนเครื่องจริง
4. ใช้ Project URL และ **publishable key** เท่านั้น ห้ามใช้ `service_role` key ในแอป
5. Supabase project ต้องตั้ง region, retention, email sender และผู้ประมวลผลให้ตรงกับประกาศความเป็นส่วนตัวฉบับที่จะเผยแพร่

ทดสอบโหมดพัฒนาโดยไม่ฝัง key ใน source:

```bash
cd /Users/norapol/Downloads/Doz/app
flutter pub get
flutter run \
  --dart-define=DOZ_SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=DOZ_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

ตรวจสมัครบัญชี, ยืนยันอีเมล, login, logout, reset password, แล้วทดสอบบัญชี A/B บนเครื่องเดียวกันว่าโปรไฟล์และประวัติไม่ปะปนกัน

ร่าง privacy notice ไทย/อังกฤษสำหรับส่งทบทวนอยู่ที่ `docs/PRIVACY_NOTICE_DRAFT.md`; source of truth คือ `lib/legal/privacy_policy_draft.dart`. หลังแก้ข้อความใน source ให้สร้างสำเนาอ่านง่ายใหม่ด้วย `python3 scripts/export_privacy_notice.py`. เอกสารยังเป็นฉบับร่างและต้องเติม/ยืนยันผู้ควบคุมข้อมูล ผู้ประมวลผล ระยะเวลาเก็บ และรายละเอียดผู้ให้บริการก่อนเผยแพร่

## 2. Build สำหรับติดตั้ง

### วิธีเชื่อมต่อ BLE สำหรับผู้ทดสอบ

1. **สถานะการดาวน์โหลดปัจจุบัน (ตรวจ 11 พ.ย. 2569):** สร้าง Android debug APK ARM64 สำเร็จจากโค้ดล่าสุดที่ `app/build/app/outputs/flutter-apk/app-debug.apk` (128,461,896 bytes; SHA-256 `cb3361817bb5a453c4b95147b9d6c40f20c3f604fc426fc166ae38a709245a31`; build 11 พ.ย. 2569 เวลา 23:53 น.). APK เป็น debug/test build ไม่มี Supabase config จึงไม่ใช่ release และไม่มี remote login/chat ที่พร้อมใช้; ยังไม่ได้ติดตั้งตรวจซ้ำกับโทรศัพท์จริงหรือบอร์ดจริง. ไม่มีลิงก์ดาวน์โหลดสาธารณะ. **iOS:** หลักฐานจากการตรวจ 10 พ.ย. ระบุว่า Xcode ไม่มี iOS 26.5 platform/runtime ที่ต้องใช้; ยังไม่มี artifact iOS หรือการยืนยันติดตั้งบน iPhone รอบนี้.
2. เปิดบอร์ดต้นแบบและวางไว้ใกล้โทรศัพท์ จากนั้นเปิดหน้า **อุปกรณ์** ในแอป
3. กด **ค้นหาอุปกรณ์ใกล้เคียง** แล้วอนุญาต Nearby devices/Bluetooth เมื่อระบบถาม; Android 11 ลงไปต้องอนุญาต Location permission และอาจต้องเปิดสวิตช์ Location ของระบบเพื่อให้ BLE scan พบอุปกรณ์ แอปไม่อ่านพิกัดระหว่างการค้นหา หากสวิตช์ปิด แอปจะแสดงปุ่มเปิด Location settings; ตั้งแต่ Android 12 ใช้ Nearby devices permission แทน
4. เลือกอุปกรณ์ที่ชื่อ Doz หรือประกาศ service UUID ของ Doz แล้วเชื่อมต่อจากในแอป ไม่ต้อง pair ผ่านหน้า Bluetooth Settings
5. หากไม่พบอุปกรณ์ ให้ตรวจว่า firmware กำลัง advertise service UUID `6b2f0001-4f2a-4c3e-9a1b-9d5e7c1a0001`, เปิด Bluetooth, เปิดบอร์ด และอนุญาตสิทธิ์ให้แอป
6. หลังเชื่อมต่อ แอปรับ raw Red/IR และ MPU6050 ตาม protocol ปัจจุบันเท่านั้น; ยังไม่ใช่ผล AI, HR, SpO₂ หรือเปอร์เซ็นต์แบตเตอรี่

การเชื่อมต่อข้างต้นตรงกับ GATT UUID ใน firmware ต้นแบบ แต่ยังต้องทดสอบ scan/connect/notification บน Android และ iPhone จริงก่อนกล่าวว่าใช้งานได้ครบทุกอุปกรณ์

#### แบบตรวจรับ BLE บนโทรศัพท์จริง (ทำแยก Android และ iOS)

ใช้บอร์ด/firmware รุ่นเดียวกับที่ระบุข้างต้น และทำ checklist นี้อย่างน้อยหนึ่งเครื่องต่อ OS พร้อมบันทึกรุ่นโทรศัพท์, OS version, app build, firmware commit, ผลแต่ละข้อ และภาพหน้าจอเมื่อผิดพลาด ห้ามบันทึกว่าผ่านจากการทดสอบ widget หรือ BLE contract checker อย่างเดียว

| ขั้น | ทำอะไร | ผลที่ต้องเห็น |
|---|---|---|
| 1. สิทธิ์ | เปิด Bluetooth; ล้างสิทธิ์แอปหรือใช้ install ใหม่ แล้วเปิดหน้าอุปกรณ์ | iOS ขอ Bluetooth เมื่อจำเป็น; Android 12+ ขอ Nearby devices; Android 11 ลงไปอาจต้องให้ Location permission และเปิด Location services ของระบบเพื่อ scan; ปฏิเสธแล้วแอปต้องบอกวิธีเปิดสิทธิ์ โดยไม่กล่าวว่าการสแกนอ่านพิกัด |
| 2. ค้นหา | เปิดบอร์ดให้ advertise แล้วกดค้นหา | พบชื่อ Doz หรืออุปกรณ์ที่ประกาศ service UUID `6b2f0001-4f2a-4c3e-9a1b-9d5e7c1a0001`; ไม่ควรเลือก BLE อื่นที่ไม่ใช่ Doz; ยกเลิก scan แล้ว spinner ต้องหยุด |
| 3. เชื่อมต่อ | เลือกอุปกรณ์จากในแอป (ไม่ pair ใน Settings) | สถานะเปลี่ยนเป็น connected/waiting; ถ้าบอร์ดปิดหรือ UUID ไม่ตรง ต้องแสดง connection failure และยังห้ามแสดงข้อมูลว่าเป็น live |
| 4. รับข้อมูล | รออย่างน้อย 3 วินาทีโดยให้เซนเซอร์ทำงาน | มี raw Red/IR และค่า IMU; freshness แสดง live เมื่อแพ็กเก็ตล่าสุดอายุไม่เกิน 8 วินาที; HR, SpO₂, battery และ AI ต้องยังแสดงว่าไม่มี/ไม่พร้อม เพราะ firmware ปัจจุบันไม่ได้ส่งค่าเหล่านั้น |
| 5. หยุดส่ง | ปิดบอร์ดหรือหยุด BLE notifications โดยยังไม่กด disconnect | ภายในประมาณ 9 วินาที ข้อมูลต้องไม่ถูกนำเสนอว่าเป็น live และเห็นข้อความว่าไม่มี packet ล่าสุด; เมื่อเกิน 30 วินาทีสถานะ freshness เป็น stale |
| 6. ตัดการเชื่อมต่อ | เปิดบอร์ดกลับหรือเชื่อมต่อใหม่จากหน้าอุปกรณ์ แล้วกด Disconnect | การเชื่อมต่อเดิมถูกล้าง; เมื่อเชื่อมใหม่แล้ว packet ใหม่ทำให้ freshness กลับมา live; ข้อมูลสาธิตที่แสดงหลัง disconnect ต้องไม่ถูกเข้าใจว่าเป็นข้อมูลจากบอร์ด |
| 7. ทดสอบซ้ำ | force-close แล้วเปิดแอปใหม่ จากนั้นเชื่อมต่อด้วยตนเองอีกครั้ง | แอปยังเปิดได้ ไม่ค้างสถานะ connected จาก session เก่า และเชื่อมต่อ/รับ packet ใหม่ได้ |

ทำซ้ำอย่างน้อยสามรอบต่อโทรศัพท์ (รวมปฏิเสธ/อนุญาตสิทธิ์และ reconnect) และบันทึกผลเป็น `PASS`, `FAIL` หรือ `NOT RUN`; หากไม่มีโทรศัพท์หรือบอร์ดจริง ให้ระบุ `NOT RUN` ไม่ใช่ `PASS`. BLE ที่ใช้งานกับ ESP32 บน Android ไม่ได้ยืนยันว่าจะผ่าน iOS เนื่องจาก OS permissions, CoreBluetooth และ BLE stack ต่างกัน

ก่อนแก้ UUID, JSON telemetry หรือ BLE fragment format ให้รันตัวตรวจสัญญาระหว่างแอปกับ firmware จาก repository root:

```bash
python3 scripts/check_ble_contract.py
```

ตัวตรวจนี้ช่วยจับ source-level mismatch เท่านั้น ไม่แทนการทดสอบวิทยุ BLE และอุปกรณ์จริง

### Android — APK สำหรับทดสอบและรุ่นลงนาม

อย่าใช้ `--release` ก่อนสร้าง upload keystore และตั้งค่า signing: ตอนนี้ Gradle จะปฏิเสธ release build หากยังไม่มี signing config และจะไม่ใช้ debug key เซ็น release ให้อัตโนมัติ ใช้ `android/key.properties.example` เป็นแม่แบบ คัดลอกเป็น `android/key.properties` แล้วใส่ path/รหัสจริง (ไฟล์นี้ถูก ignore โดย Git):

```properties
storeFile=/absolute/path/to/doz-upload-key.jks
storePassword=...
keyAlias=doz-upload
keyPassword=...
```

เก็บ keystore และรหัสผ่านสำรองไว้อย่างปลอดภัย หาก keystore สูญหายอาจอัปเดตแอปที่เผยแพร่ด้วย signing identity เดิมไม่ได้ ก่อนเผยแพร่จริงต้องเลือก application ID แบบ reverse-DNS ที่โครงการเป็นเจ้าของ (ห้ามใช้ `com.example.doz`) และตั้ง Supabase/redirect URLs ให้ตรงกัน Gradle จะปฏิเสธ Android release build หากยังเป็น placeholder หรือรูปแบบไม่ถูกต้อง

สำหรับทดสอบในเครื่อง ใช้ debug APK ซึ่งเซ็นด้วย debug key อัตโนมัติ:

```bash
flutter build apk --debug --target-platform android-arm64
```

คำสั่งนี้สร้าง `build/app/outputs/flutter-apk/app-debug.apk`. Build ล่าสุด 10 พ.ย. 2569 เวลา 06:38 น. ขนาด 116,660,801 bytes, SHA-256 `4e6235648d3b63ed59e256579756063538cbc1afdd4fb679936db1032781abe8`; ติดตั้งและเปิดบน Pixel 8 emulator ได้ก่อนหน้านี้ รวมถึงทดสอบหน้า Status/Data/Device และ BLE scan ที่รายงานไม่พบอุปกรณ์โดยไม่ crash. การรันทวนเวลา 21:34–21:38 ติดตั้งได้แต่ถูก system-UI ANR บังหน้าจอจากแรงกดดันทรัพยากร emulator จึงต้องตรวจ runtime ซ้ำบนเครื่องเสถียร. APK ไม่มี Supabase config จึงใช้ทดสอบ UI/โหมด local เท่านั้น; remote login/chat ยังใช้ไม่ได้ และ BLE ยังไม่ผ่านการทดสอบกับบอร์ดหรือโทรศัพท์จริง. เป็น debug/test build ไม่ใช่ release สำหรับร้านค้า

ผลตรวจ toolchain ล่าสุดด้วย `flutter doctor -v` พบ Android SDK/Emulator แต่ **Android SDK Command-line Tools ยังไม่มี** และ Flutter ยังตรวจสถานะ license ไม่ได้. ก่อน build/release ในเครื่องนี้ ให้เปิด Android Studio → SDK Manager → SDK Tools แล้วติดตั้ง Android SDK Command-line Tools (latest), จากนั้นรัน `flutter doctor --android-licenses` และยอมรับ license ตามที่ตรวจอ่านแล้ว; ปิดท้ายด้วย `flutter doctor -v` ซ้ำ. การติดตั้ง APK ที่ build ไว้ก่อนหน้านี้ผ่าน `adb` ยังทำได้ แต่ห้ามนับว่าเครื่องมือพัฒนา Android ตั้งค่าครบจน doctor ผ่าน

วิธีติดตั้งบนโทรศัพท์ Android เพื่อทดสอบ: ส่งไฟล์ `app-debug.apk` ไปยังโทรศัพท์ด้วยสาย USB หรือช่องทางแชร์ไฟล์ส่วนตัว → เปิดจาก Downloads/Files → อนุญาต “Install unknown apps” ให้แอปที่เปิดไฟล์ หาก Android ถาม → กดติดตั้ง → เปิดแอปและไปหน้า **อุปกรณ์** → เปิดบอร์ดต้นแบบใกล้โทรศัพท์ กด **ค้นหาอุปกรณ์ใกล้เคียง** และอนุญาต Nearby devices/Bluetooth → เลือก Doz จากรายการ (ไม่ต้อง pair ผ่าน Bluetooth Settings) หรือเชื่อมต่อผ่าน USB debugging ด้วย `adb install -r build/app/outputs/flutter-apk/app-debug.apk`. ติดตั้งทับได้เมื่อ package/signing key ตรงกัน; debug APK ใช้แทนรุ่น release ไม่ได้

หาก Android ปฏิเสธ APK ให้ตรวจว่าเลือก architecture ตรงกับโทรศัพท์ (ARM64 ใช้กับ Android phone ส่วนใหญ่), มีพื้นที่ว่าง และยอมรับการติดตั้งจากแอปต้นทางแล้ว อย่าปิดระบบป้องกันถาวรหรือเปิดติดตั้งจากทุกแหล่งเกินจำเป็น ไฟล์นี้ยังเป็น demo build: ไม่มี Supabase URL/key, ดังนั้นล็อกอินและ chatbot ระยะไกลไม่พร้อม แม้หน้าจอ BLE จะเปิดได้ การเชื่อมต่อกับบอร์ดจริงยังต้องยืนยันบนโทรศัพท์และ firmware จริง

สคริปต์ `build_apps.sh` เป็นเส้นทางแนะนำสำหรับ build สองแพลตฟอร์ม โดยตรวจ `/health`, authenticated `/chat`/`/advice` และ LLM จริงก่อน build พร้อมส่ง Supabase URL/publishable key เข้า build ให้ครบ ต้องใช้ **base URL ที่ deploy แล้วจริง** (ไม่เติม `/chat` หรือ `/health`) และ credentials ของโปรเจกต์ที่ผู้ดูแลเป็นเจ้าของ:

```bash
cd /Users/norapol/Downloads/Doz/app
DOZ_APPLICATION_ID=com.yourorganization.doz \
DOZ_SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
DOZ_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY \
./build_apps.sh https://YOUR_DEPLOYED_API_HOST
```

ก่อนเรียกสคริปต์ ให้ตั้ง `DOZ_CHAT_TEST_TOKEN` ผ่าน secret manager หรือวิธีส่ง environment variable ที่ปลอดภัย เป็น access token อายุสั้นของบัญชีทดสอบที่อยู่ใน Supabase project เดียวกับ API; อย่าใส่ token ใน command line, source control หรือใช้บัญชีผู้ใช้จริง สคริปต์จะเรียก `cloud_api/preflight_chat.py --require-llm` เพื่อตรวจ `/health`, `/chat`, `/advice` และการปฏิเสธ token ปลอมทั้งสอง route โดยส่งเฉพาะข้อความ/สถานะทดสอบคงที่ ไม่มีข้อมูลเซนเซอร์หรือโปรไฟล์ การตรวจนี้เรียก LLM provider จริงและอาจใช้โควต้าเล็กน้อย

แทน `com.yourorganization.doz` ด้วย application/bundle ID reverse-DNS ที่องค์กรควบคุมจริง; ตั้ง Bundle Identifier ของ iOS Runner ให้ตรงกันใน Xcode และตั้ง `android/key.properties` จากแม่แบบก่อนรัน สคริปต์จะหยุดหากยังเป็น ID ตัวอย่างหรือไม่มี Android upload keystore; อย่าใส่รหัส keystore หรือ Supabase admin/service-role key ในคำสั่งหรือ binary

สคริปต์ตรวจ Xcode destination ให้พบ `Any iOS Device` ก่อนทำ network preflight หรือเริ่ม build; ถ้า iOS platform ไม่พร้อมจะหยุดก่อนสร้าง artifact ใด ๆ จากนั้นจึงตรวจ health/chat/advice และ token rejection และหยุดถ้า `/chat` ไม่คืน `mode=llm` หรือ `/advice` ไม่คืน `mode=rag`. ขั้น build ทำ iOS ก่อน Android เพื่อไม่ให้เกิด APK ครึ่งงานเมื่อ iOS build ล้มเหลว. การผ่าน preflight และ build ไม่ยืนยัน BLE หรือการทำงานบนอุปกรณ์จริง; ต้องอ่าน exit status และทดสอบทั้งสองแพลตฟอร์ม ไม่ถือว่าจบเมื่อเห็นไฟล์ APK อย่างเดียว

เมื่อมี signing config แล้วจึงสร้าง APK/AAB release ด้วยตนเองเท่านั้นหลังผ่าน preflight เดียวกัน (คำสั่ง Flutter ด้านล่างไม่ตรวจ chatbot ให้อัตโนมัติ):

```bash
cd /Users/norapol/Downloads/Doz/app
DOZ_API_BASE_URL=https://YOUR_DEPLOYED_API_HOST \
python3 cloud_api/preflight_chat.py --require-llm
```

คำสั่งนี้ใช้ `DOZ_CHAT_TEST_TOKEN` ที่ตั้งไว้ใน environment; อย่าใส่ token ใน command history.

```bash
cd /Users/norapol/Downloads/Doz/app
flutter build apk --release \
  --android-project-arg=dozApplicationId=com.yourorganization.doz \
  --dart-define=VITAGAURD_CLOUD_BASE_URL=https://YOUR_DEPLOYED_API_HOST \
  --dart-define=DOZ_SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=DOZ_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

แทน `com.yourorganization.doz` ด้วย ID ที่คุณควบคุมจริง (ตัวอย่างนี้เป็นเพียงรูปแบบ ห้ามนำไปใช้ตรง ๆ) และตั้ง Bundle Identifier ของ iOS ให้เป็น ID เดียวกันใน Xcode ก่อน Archive; ปัจจุบันทั้ง Android/iOS ยังใช้ `com.example.doz` จึงยังไม่ใช่ชื่อ package สำหรับปล่อยแอปจริง

ไฟล์ติดตั้งอยู่ที่ `build/app/outputs/flutter-apk/app-release.apk` แจกให้ผู้ทดสอบติดตั้ง sideload ได้ หรือ build App Bundle แล้วส่งผ่าน Google Play internal testing:

```bash
flutter build appbundle --release \
  --android-project-arg=dozApplicationId=com.yourorganization.doz \
  --dart-define=VITAGAURD_CLOUD_BASE_URL=https://YOUR_DEPLOYED_API_HOST \
  --dart-define=DOZ_SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=DOZ_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

สำหรับแจก Android ให้กลุ่มทดสอบ แนะนำอัปโหลด AAB ไปที่ Google Play Console > Testing > Internal testing แล้วเพิ่มรายชื่อผู้ทดสอบและส่ง opt-in link; internal track รองรับผู้ทดสอบได้สูงสุด 100 คนตามคู่มือ Google Play ([ตั้งค่า open/closed/internal testing](https://support.google.com/googleplay/android-developer/answer/9845334?hl=en)). การแจก APK ตรงเหมาะกับทดสอบวงจำกัดเท่านั้น ไม่ใช่ช่องทางอัปเดตที่จัดการได้เหมือน Play.

### iOS — TestFlight

โปรเจกต์ชุดนี้ใช้ Swift Package Manager สำหรับ Flutter plugins; ใช้ `flutter pub get` เพื่อสร้าง package integration และไม่ต้องรัน `pod install` สำหรับ dependencies ปัจจุบัน ต้อง build บน macOS ที่มี Xcode และ Apple Developer signing:

```bash
cd /Users/norapol/Downloads/Doz/app
flutter build ios --release \
  --dart-define=DOZ_SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=DOZ_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
open ios/Runner.xcworkspace
```

หาก Xcode แจ้งว่า iOS platform/runtime ไม่ได้ติดตั้ง ให้เปิด Xcode → Settings → Components และติดตั้ง iOS platform/runtime รุ่นที่ตรงกับ Xcode ก่อน build อีกครั้ง ([คู่มือเพิ่ม Xcode components](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)). การติดตั้ง runtime อาจใช้พื้นที่ดิสก์หลาย GB

สถานะตรวจสอบล่าสุดบนเครื่องพัฒนา (10 พ.ย. 2569): Xcode 26.6; `xcrun simctl list runtimes` ไม่พบ iOS Simulator runtime. ทดสอบ `flutter build ios --no-codesign` แล้วล้มเหลวเพราะ Xcode ระบุว่า iOS 26.5 platform ไม่ได้ติดตั้ง แม้ `xcodebuild -showsdks` แสดง SDK entries; generic destinations ยังใช้ไม่ได้. `flutter devices` พบเฉพาะ macOS และไม่มีโทรศัพท์จริงเชื่อมต่อ. Xcode เคยรายงาน package 8.52 GB สำหรับ platform/runtime; พื้นที่ว่างล่าสุด 9.9 GiB ยังเหลือ headroom น้อยเกินไปสำหรับการ staging และ build จึงยังไม่ติดตั้งเพื่อคงพื้นที่สำรองของระบบ. ก่อน release ต้องเพิ่มพื้นที่ว่างให้เพียงพอ ติดตั้ง platform/runtime ที่ Xcode ต้องการ และกำหนด application/bundle ID ที่โครงการเป็นเจ้าของกับ Apple Developer Team. ยังไม่มี artifact iOS หรือหลักฐานว่า iOS BLE ทำงานบน iPhone จริง:

```bash
xcrun simctl list runtimes
flutter build ios --simulator --debug
```

Simulator build ไม่แทนการทดสอบ BLE, login deep link หรือ notification บน iPhone จริง; การแจกผู้ใช้ยังต้องเลือก Bundle Identifier ของโครงการและ Apple Developer Team ก่อน Archive/Upload ผ่าน TestFlight

ยืนยันล่าสุด (10 พ.ย. 2569): Pixel 8 AVD เคยเปิดและติดตั้ง APK ทดลองได้; รอบก่อนตรวจหน้า Status/Device และ BLE scan โดยไม่มีบอร์ด (สแกนได้แต่ไม่พบ Doz device). รอบตรวจซ้ำเวลา 21:34–21:38 ติดตั้ง APK สำเร็จ แต่พบ system-UI ANR ขณะ emulator เตือนว่า host RAM ว่าง 3992 MB ต่ำกว่าที่แนะนำ 5120 MB; system dialog บังหน้าจอ จึงไม่นับรอบซ้ำนี้ว่า runtime/UI ผ่าน แม้ไม่พบ app FATAL/Flutter error ใน logcat. `xcrun simctl list runtimes` ยังไม่มี iOS Simulator runtime. `flutter build ios --no-codesign` ล้มเหลวเพราะ Xcode แจ้ง iOS 26.5 platform ไม่ได้ติดตั้ง แม้ SDK directory มีอยู่; พื้นที่ว่างล่าสุด 9.9 GiB เหลือ headroom น้อยเมื่อเทียบกับ platform/runtime ที่ Xcode เคยรายงานประมาณ 8.52 GB และพื้นที่ staging/build ที่ต้องใช้. ไม่มี iPhone จริงเชื่อมต่อ จึงยังทดสอบ login/deep link, permission และ BLE end-to-end บน iOS จริงไม่ได้

ตั้ง Team/Signing ใน Xcode แล้ว Archive → Upload → แจกผ่าน TestFlight ผู้ทดสอบติดตั้งผ่านแอป TestFlight; Apple ระบุว่ารองรับ internal testers สูงสุด 100 คน และ external testers สูงสุด 10,000 คน โดย build แรกสำหรับ external testing ต้องผ่าน Beta App Review ก่อน ([TestFlight ของ Apple](https://developer.apple.com/testflight/), [คู่มือ TestFlight ใน App Store Connect](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)). ผู้ใช้ iOS ทั่วไปไม่ควรรับ `.app` จากช่องทาง sideload; ใช้ TestFlight หรือ App Store

## 3. Chatbot และ Cloud API

แอปใช้ `VITAGAURD_CLOUD_BASE_URL` เพื่อประกอบ endpoint `/chat` และมี local fallback เมื่อ remote ใช้ไม่ได้ ตั้ง `SUPABASE_URL` กับ `SUPABASE_PUBLISHABLE_KEY` ฝั่ง API เพื่อให้ `/chat` ตรวจ access token ผ่าน Supabase Auth ก่อนเรียก LLM; เก็บ LLM key ไว้ฝั่ง server เท่านั้น:

**สถานะตรวจล่าสุด 15 พ.ย. 2569:** Render service `Drive-alert` deploy API จาก branch `render-api-deploy`, root `app/cloud_api`, commit `3664ff1` สถานะ `live`; `https://drive-alert.onrender.com/health` ตอบ HTTP 200. URL นี้แสดง JSON ของ API ไม่ใช่หน้าแอป Flutter. `/ready` ตอบ HTTP 503 ว่า config ที่จำเป็นยังไม่พร้อม และคำขอ `/chat` ที่มี body ถูกต้องแต่ไม่มี token ตอบ HTTP 503 ว่า Chat authentication ยังไม่ได้ตั้งค่าบน server; จึงยังไม่มีหลักฐานว่า Supabase/LLM หรือ preflight authenticated `/chat` และ `/advice` ทำงานจริง. `flutter analyze --no-pub` และ Flutter 135 tests ของ worktree ปัจจุบันผ่าน; backend 50 tests ผ่านโดยใช้ mock. โค้ดหน้าแอปในเครื่องมีการแก้ไขที่ยังไม่อยู่บน Render. ผลทดสอบ emulator ก่อนหน้าดูใน `docs/STRESS_TEST_10000_SCENARIOS_TH.md`; ยังไม่มีหลักฐาน end-to-end กับบอร์ดและบัญชีทดสอบจริง. อย่าระบุว่า chatbot หรือ cloud health sync พร้อมใช้งานจนกว่าการตั้งค่า, ทดสอบสิทธิ์ และ privacy/security review จะผ่าน.

Backend regression tests were rerun locally on 10 November 2026: **31 tests passed** with `cloud_api/.venv/bin/python -m unittest discover -s cloud_api -p 'test_*.py' -v`. These tests mock Supabase and the LLM provider; they validate code paths and security behavior, but do **not** prove the deployed API, Supabase project, provider credentials, or live chatbot are operational. The suite includes a check that LLM-provider exception text is not written to server logs.

หลัง deploy ใช้ `cloud_api/preflight_chat.py` ตรวจ health, `/chat`, `/advice` และการปฏิเสธ token ปลอมทั้งสอง route ในขั้นตอนเดียว ตั้ง `DOZ_CHAT_TEST_TOKEN` เป็น access token อายุสั้นของบัญชีทดสอบ และ `DOZ_API_BASE_URL` เป็น HTTPS base URL ก่อนเรียก `python3.11 cloud_api/preflight_chat.py --require-llm`; อย่าใช้ token บัญชีจริงหรือส่ง sensor/profile data ใน preflight. คำขอทดสอบจะถูกส่งถึง LLM provider เมื่อใช้ `--require-llm` และเซิร์ฟเวอร์ตอบจาก LLM จริง.

```bash
flutter run \
  --dart-define=VITAGAURD_CLOUD_BASE_URL=https://YOUR_API_HOST
```

ทุก endpoint `/chat`, `/advice`, `/sensor`, `/alert`, `/devices` ตรวจ bearer token กับ Supabase Auth และ endpoint ข้อมูลผูก event กับบัญชีที่ตรวจสอบแล้ว `/chat` กับ `/advice` ใช้ limiter ใน process เดียวกัน ส่วน route health-data จะตอบ HTTP 503 จนกว่าผู้ดูแลจะตั้ง `HEALTH_DATA_SYNC_ENABLED=true` เอง ยังไม่มี shared gateway limiter และยังต้องทบทวน retention/deletion controls กับการตั้งค่า deployment/สิทธิ์อ่านข้อมูลแบบ end-to-end จึง **ห้ามเปิด cloud health sync หรือส่งข้อมูลสุขภาพจริง** จนกว่าจะทำและตรวจมาตรการเหล่านี้ครบ การมี HTTPS อย่างเดียวไม่ยืนยันการตั้งค่า deployment หรือมาตรการจัดการข้อมูลทั้งหมด

## 4. ตรวจรับก่อนให้ผู้ทดสอบ

- [ ] Auth keys เป็น project URL + publishable key; ไม่มี service-role key ใน binary/config
- [ ] Email confirmation/reset deep link ใช้งานจริงบน iOS และ Android
- [ ] BLE scan/connect/disconnect, permissions, packet fragmentation และ freshness ทดสอบกับบอร์ด/firmware รุ่นจริงทั้งสอง OS
- [ ] UI แยก mock data จาก sensor จริงอย่างชัดเจน
- [ ] Chatbot/advice ต้องยืนยัน consent และ bearer token; ทดสอบการปฏิเสธ token ผิด/หมดอายุและ local fallback
- [ ] ตรวจ provider retention, rate limits, deletion, deployment configuration และทบทวนก่อนส่งข้อมูลสุขภาพจริง
- [ ] Cloud health sync ปิดไว้จนทดสอบ token, ownership isolation, retention/deletion, rate limits และ deployment จริงครบ
- [ ] ทบทวน privacy draft, controller/processor, data region/retention, account deletion และการตอบคำขอข้อมูล
- [ ] ทดสอบด้วยบัญชีสองคนและอุปกรณ์จริง; ตรวจ signed build และ store privacy disclosures

แอปยังเป็นต้นแบบ ไม่ใช่อุปกรณ์วินิจฉัย และยังไม่พร้อมเผยแพร่สู่สาธารณะหรือใช้เฝ้าระวังความปลอดภัยจริง
