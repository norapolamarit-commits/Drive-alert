# ตั้งค่าหลังบ้าน Doz กับ Google Sheets

## ส่วนที่ทำแล้ว

- API ตรวจ Supabase bearer token ก่อนอ่าน/เขียนข้อมูลของบัญชี
- ข้อมูล sensor และ alert ที่ผ่านการตรวจถูกส่งไปยัง Google Sheets ได้เมื่อกำหนดค่า service account
- มี `GET /sensor`, `GET /alert`, `GET /overview`, `GET /devices` และ `GET /ready`
- `GET /ready` ตรวจทั้งสองแท็บของ Sheets เมื่อเปิด health sync
- ชีตต้นแบบว่าง: https://docs.google.com/spreadsheets/d/1Bo8vV7uvmzTfupZQZd4vfUsmk7cnbOOdBa1mTyznPCM/edit

## สิ่งที่ต้องตั้งค่าในบัญชีของโครงการ

1. ใช้ Google Cloud project `doz-backend` (สร้างแล้ว) ซึ่งเปิด Google Sheets API แล้ว
2. สร้าง service account และ JSON key สำหรับเซิร์ฟเวอร์
3. แชร์ชีตต้นแบบให้ **อีเมลของ service account** เป็น Editor โดยไม่เปิดเป็น public
4. ใส่ค่าต่อไปนี้ใน Environment ของ Render service `Drive-alert` โดยตรง:
   - `DOZ_SHEETS_SPREADSHEET_ID=1Bo8vV7uvmzTfupZQZd4vfUsmk7cnbOOdBa1mTyznPCM`
   - `DOZ_GOOGLE_SERVICE_ACCOUNT_JSON` = JSON key ทั้งก้อน (Secret; ห้ามส่งทางแชตหรือ commit)
   - `SUPABASE_URL` และ `SUPABASE_PUBLISHABLE_KEY` สำหรับตรวจผู้ใช้
   - `SUPABASE_SERVICE_ROLE_KEY` เฉพาะเมื่อใช้ flow ลบบัญชีกับ backend อื่นที่รองรับการลบจริง
5. เก็บ `HEALTH_DATA_SYNC_ENABLED=false` ระหว่างทดสอบโครงสร้างและสิทธิ์ เมื่อกฎข้อมูลส่วนบุคคลพร้อมและทดสอบกับข้อมูลสาธิตแล้วจึงพิจารณาเปิด

## ตรวจสอบ

จากเครื่องพัฒนา รัน `python3 -m pytest app/cloud_api -q` ที่ราก repo เพื่อตรวจ logic โดยไม่ส่งข้อมูลจริง จากนั้นตรวจ `GET /health` (process), `GET /ready` (Auth และ storage เมื่อเปิด sync) โดยไม่ส่ง credential ใน URL หาก `/ready` ตอบ 503 ให้ตรวจ environment, การแชร์ชีต และชื่อแท็บผ่าน Render logs โดยไม่พิมพ์ JSON key ลง log

## ข้อจำกัดที่ต้องแก้ก่อนใช้งานจริง

Google Sheets มีโควตาคำขอและขีดจำกัด 2,000 แถวข้อมูลต่อแท็บใน adapter นี้ ไม่เหมาะกับ raw sensor ต่อเนื่องทุกวินาที การล้างเซลล์ไม่รับประกันการลบจาก version history ดังนั้น `DELETE /account` จะปฏิเสธเมื่อเลือก Sheets และแอปยังปิด health sync อยู่ ต้องเลือก storage ที่รองรับการลบและ retention จริงก่อนใช้กับข้อมูลสุขภาพของผู้ใช้ทั่วไป
