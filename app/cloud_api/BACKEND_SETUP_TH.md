# ตั้งค่าหลังบ้าน Doz กับ Google Sheets

## ส่วนที่ทำแล้ว

- Flutter web เผยแพร่ที่ https://doz-web.onrender.com จาก branch `render-api-deploy` และเปิดหน้า sign in ได้
- Cloud API เผยแพร่ที่ https://drive-alert.onrender.com โดย `/health` และ `/ready` ตอบ 200 เมื่อปิด health sync
- Supabase Auth project `ihedtlpeszdpdcfdkcip` ถูกกำหนดด้วย URL และ publishable key ทั้งฝั่งเว็บและ API
- Google Cloud project `doz-backend` เปิด Sheets API แล้ว; service account `doz-sheets-writer@doz-backend.iam.gserviceaccount.com` ได้สิทธิ์ Editor เฉพาะชีตต้นแบบ
- API ตรวจ Supabase bearer token ก่อนอ่าน/เขียนข้อมูลของบัญชี
- ข้อมูล sensor และ alert ที่ผ่านการตรวจถูกส่งไปยัง Google Sheets ได้เมื่อกำหนดค่า service account
- มี `GET /sensor`, `GET /alert`, `GET /overview`, `GET /devices` และ `GET /ready`
- `GET /ready` ตรวจทั้งสองแท็บของ Sheets เมื่อเปิด health sync
- ชีตต้นแบบว่าง: https://docs.google.com/spreadsheets/d/1Bo8vV7uvmzTfupZQZd4vfUsmk7cnbOOdBa1mTyznPCM/edit

## สิ่งที่ต้องตั้งค่าในบัญชีของโครงการ

1. ใช้ Google Cloud project `doz-backend` ซึ่งเปิด Google Sheets API แล้ว
2. ตรวจว่า JSON key ของ service account ถูกสร้างและเก็บไว้อย่างปลอดภัย; ยังไม่ได้ยืนยันคีย์ที่ใช้งานได้จากฝั่งเซิร์ฟเวอร์
3. ชีตต้นแบบแชร์ให้ **อีเมลของ service account** เป็น Editor แล้ว โดยไม่เปิดเป็น public
4. ใส่ค่าต่อไปนี้ใน Environment ของ Render service `Drive-alert` โดยตรง:
   - `DOZ_SHEETS_SPREADSHEET_ID=1Bo8vV7uvmzTfupZQZd4vfUsmk7cnbOOdBa1mTyznPCM`
   - `DOZ_GOOGLE_SERVICE_ACCOUNT_JSON` = JSON key ทั้งก้อน (Secret; ห้ามส่งทางแชตหรือ commit)
   - `SUPABASE_URL` และ `SUPABASE_PUBLISHABLE_KEY` สำหรับตรวจผู้ใช้ (ตั้งแล้ว)
   - `SUPABASE_SERVICE_ROLE_KEY` เฉพาะเมื่อใช้ flow ลบบัญชีกับ backend อื่นที่รองรับการลบจริง
5. เก็บ `HEALTH_DATA_SYNC_ENABLED=false` ระหว่างทดสอบโครงสร้างและสิทธิ์ เมื่อกฎข้อมูลส่วนบุคคลพร้อมและทดสอบกับข้อมูลสาธิตแล้วจึงพิจารณาเปิด

เว็บ static site ตั้งค่า rewrite `/*` ไป `/index.html` แล้วเพื่อให้เส้นทางภายในแอปเปิดจาก URL ตรงได้ ค่า build ฝั่งเว็บเป็น public เท่านั้น ไม่ใส่ service-role key หรือ JSON key ลงเว็บ

## ตรวจสอบ

จากเครื่องพัฒนา รัน `python3 -m pytest app/cloud_api -q` ที่ราก repo เพื่อตรวจ logic โดยไม่ส่งข้อมูลจริง จากนั้นตรวจ `GET /health` (process), `GET /ready` (Auth และ storage เมื่อเปิด sync) โดยไม่ส่ง credential ใน URL หาก `/ready` ตอบ 503 ให้ตรวจ environment, การแชร์ชีต และชื่อแท็บผ่าน Render logs โดยไม่พิมพ์ JSON key ลง log

ตรวจ deploy แบบไม่ต้องใช้บัญชีทดสอบด้วย `DOZ_API_BASE_URL=https://drive-alert.onrender.com python3 app/cloud_api/preflight_chat.py --public-only` คำสั่งนี้ตรวจ `/ready` และตรวจว่า `/chat` กับ `/advice` ปฏิเสธ token ผิดด้วย HTTP 401 เท่านั้น หากต้องการตรวจคำตอบแชตจริง ให้ใช้บัญชีทดสอบที่มี token อายุสั้นและรันโดยไม่ใส่ `--public-only`

## ข้อจำกัดที่ต้องแก้ก่อนใช้งานจริง

Google Sheets มีโควตาคำขอและขีดจำกัด 2,000 แถวข้อมูลต่อแท็บใน adapter นี้ ไม่เหมาะกับ raw sensor ต่อเนื่องทุกวินาที การล้างเซลล์ไม่รับประกันการลบจาก version history ดังนั้น `DELETE /account` จะปฏิเสธเมื่อเลือก Sheets และแอปยังปิด health sync อยู่ ต้องเลือก storage ที่รองรับการลบและ retention จริงก่อนใช้กับข้อมูลสุขภาพของผู้ใช้ทั่วไป
