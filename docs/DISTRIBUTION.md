# คู่มือแจกจ่าย doz App (Android + iOS)

แอปนี้เรียก cloud server (RAG + Pathumma) ตอนแชต — ผู้ใช้ทางไกลจึงต้องชี้ไป
**public URL** ไม่ใช่ localhost. ฝัง URL ตอน build ด้วย `--dart-define`.

---

## ขั้นที่ 0 — Deploy server ขึ้น Render (ทำครั้งเดียว)

1. push โฟลเดอร์ `cloud_api/` ขึ้น GitHub
2. https://render.com → New → Web Service → เชื่อม repo (root = `cloud_api`)
3. Environment variables:
   - `LLM_API_KEY` = HuggingFace token (hf_...)
4. Deploy → ได้ URL เช่น `https://vita-gaurd-cloud-api.onrender.com`
5. ทดสอบ: `curl https://<url>/health`

> Render free จะหลับเมื่อไม่มีคนใช้ คำถามแรกอาจช้า ~30 วิ

---

## ขั้นที่ 1 — Build ทั้ง 2 platform ทีเดียว

```bash
cd /Users/norapol/Documents/Doz
./scripts/build_apps.sh https://vita-gaurd-cloud-api.onrender.com
```

---

## ขั้นที่ 2 — Android (ง่าย)

ได้ไฟล์: `build/app/outputs/flutter-apk/app-release.apk`

แจกได้ 3 ทาง:
- **ส่งไฟล์ .apk** (Drive/LINE) — ผู้ใช้เปิด "ติดตั้งจากแหล่งไม่รู้จัก"
- **Firebase App Distribution** — ส่งลิงก์ติดตั้ง จัดการเวอร์ชัน (ฟรี)
- **Google Play** — $25 ครั้งเดียว, ใช้ `flutter build appbundle`

---

## ขั้นที่ 3 — iOS (ต้องมี Apple Developer $99/ปี)

1. สมัคร https://developer.apple.com ($99/ปี)
2. เปิด Xcode: `open ios/Runner.xcworkspace`
3. ตั้ง Signing & Capabilities → เลือก Team
4. Product → Archive → Distribute App → TestFlight (หรือ App Store)
5. เชิญผู้ทดสอบทางอีเมลใน App Store Connect → ผู้ใช้โหลดผ่านแอป TestFlight

> ไม่มีวิธีส่งไฟล์ตรงเหมือน Android — iOS ต้องผ่าน TestFlight/App Store เท่านั้น

---

## เช็กลิสต์
- [ ] server ขึ้น Render + ใส่ LLM_API_KEY แล้ว
- [ ] build ด้วย `--dart-define` URL จริง (ไม่ใช่ localhost)
- [ ] Android: แจก APK / Firebase
- [ ] iOS: Apple Developer + TestFlight
- [ ] ทดสอบแชตบนเครื่องผู้ใช้จริง (ไม่ใช่ Wi-Fi เดียวกับเรา)
