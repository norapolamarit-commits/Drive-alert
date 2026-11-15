"""EN: Prepare two private Doz tabs in an existing spreadsheet. TH: เตรียมแท็บ Doz สองแท็บในชีตส่วนตัวที่มีอยู่"""

import sys  # EN: Return a useful process exit status. TH: คืนรหัสจบโปรแกรมที่บอกผลได้
from urllib.parse import quote  # EN: Escape fixed Sheets ranges in URLs. TH: เข้ารหัสช่วงเซลล์ใน URL

from sheets_storage import HEADERS, SheetsStorageError, store_from_env  # EN: Reuse the validated storage contract. TH: ใช้ข้อตกลง storage ที่ตรวจแล้ว


def main() -> int:  # EN: Set up tabs without writing user health events. TH: เตรียมแท็บโดยไม่เขียนข้อมูลสุขภาพผู้ใช้
    try:  # EN: Handle missing or malformed credentials without a traceback. TH: จัดการคีย์ที่หายหรือผิดรูปโดยไม่แสดง traceback
        store = store_from_env()  # EN: Load protected server-side configuration. TH: โหลดค่าตั้งค่าที่ป้องกันไว้ฝั่งเซิร์ฟเวอร์
        if store is None:  # EN: Require both spreadsheet ID and service-account JSON. TH: บังคับมีรหัสชีตและ JSON บัญชีบริการ
            print("Set DOZ_SHEETS_SPREADSHEET_ID and DOZ_GOOGLE_SERVICE_ACCOUNT_JSON first.")  # EN: Explain missing settings without printing their values. TH: แจ้งค่าที่ขาดโดยไม่พิมพ์เนื้อหา
            return 2  # EN: Signal a configuration problem. TH: แจ้งรหัสผิดพลาดการตั้งค่า
        metadata = store._request("GET", store.base, params={"fields": "sheets.properties.title"})  # EN: Read only tab titles. TH: อ่านเฉพาะชื่อแท็บ
        sheets = metadata.get("sheets")  # EN: Extract the tab collection. TH: แยกรายการแท็บ
        if not isinstance(sheets, list):  # EN: Reject malformed provider metadata. TH: ปฏิเสธข้อมูลแท็บที่ผิดรูป
            raise SheetsStorageError("Invalid Sheets metadata")  # EN: Stop before changing an unknown spreadsheet. TH: หยุดก่อนแก้ชีตที่มีข้อมูลไม่แน่ชัด
        titles = {sheet["properties"].get("title") for sheet in sheets  # EN: Collect titles from valid metadata entries. TH: รวบรวมชื่อจากรายการข้อมูลแท็บที่ถูกต้อง
                  if isinstance(sheet, dict) and isinstance(sheet.get("properties"), dict)}  # EN: Ignore malformed entries. TH: ข้ามรายการแท็บที่ผิดรูป
        for tab in ("SensorEvents", "AlertEvents"):  # EN: Prepare both fixed event tabs. TH: เตรียมแท็บเหตุการณ์ทั้งสอง
            if tab not in titles:  # EN: Create a missing tab only. TH: สร้างเฉพาะแท็บที่ยังไม่มี
                store._request("POST", f"{store.base}:batchUpdate",  # EN: Use the Sheets metadata update endpoint. TH: ใช้ endpoint ปรับโครงสร้างชีต
                               json={"requests": [{"addSheet": {"properties": {"title": tab}}}]})  # EN: Add one named tab. TH: เพิ่มแท็บตามชื่อที่กำหนด
            encoded = quote(f"{tab}!A1:D1", safe="")  # EN: Target only the header row. TH: เล็งเฉพาะแถวหัวตาราง
            current = store._request("GET", f"{store.base}/values/{encoded}").get("values", [])  # EN: Read existing headers. TH: อ่านหัวตารางเดิม
            if not isinstance(current, list):  # EN: Refuse invalid values before indexing. TH: ปฏิเสธค่าผิดรูปก่อนอ่านตำแหน่ง
                raise SheetsStorageError("Invalid tab values")  # EN: Stop setup on malformed provider data. TH: หยุดตั้งค่าเมื่อข้อมูลผู้ให้บริการผิดรูป
            if current and current[0] != HEADERS:  # EN: Refuse to overwrite an incompatible schema. TH: ไม่เขียนทับโครงสร้างที่ไม่ตรง
                raise SheetsStorageError("Unexpected tab headers")  # EN: Stop before any header overwrite. TH: หยุดก่อนเขียนทับหัวตาราง
            if not current:  # EN: Write headers only on an empty tab. TH: เขียนหัวตารางเฉพาะแท็บว่าง
                store._request("PUT", f"{store.base}/values/{encoded}",  # EN: Update the header range. TH: เขียนช่วงหัวตาราง
                               params={"valueInputOption": "RAW"},  # EN: Prevent formula interpretation. TH: ป้องกันการตีความเป็นสูตร
                               json={"majorDimension": "ROWS", "values": [HEADERS]})  # EN: Supply the exact schema. TH: ส่งโครงสร้างคอลัมน์ที่กำหนด
        print("SensorEvents and AlertEvents are ready. No health data was written.")  # EN: Confirm only setup work. TH: ยืนยันว่าเตรียมแท็บอย่างเดียว
        return 0  # EN: Report successful initialization. TH: แจ้งเตรียมสำเร็จ
    except SheetsStorageError:  # EN: Catch setup and provider failures. TH: จับข้อผิดพลาดการตั้งค่าและผู้ให้บริการ
        print("Could not initialize tabs. Check sharing, API access, and empty tab headers.")  # EN: Avoid exposing the credential or sheet content. TH: ไม่เปิดเผยคีย์หรือเนื้อหาชีต
        return 1  # EN: Report a controlled failure. TH: แจ้งผิดพลาดแบบควบคุม


if __name__ == "__main__":  # EN: Run only when invoked as a script. TH: ทำงานเมื่อเรียกไฟล์นี้โดยตรง
    sys.exit(main())  # EN: Pass the result to the shell. TH: ส่งผลลัพธ์กลับไปยัง shell
