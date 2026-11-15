"""EN: Store bounded Doz events in server-only Google Sheets. TH: เก็บเหตุการณ์ Doz แบบจำกัดขนาดในชีตฝั่งเซิร์ฟเวอร์"""
from __future__ import annotations  # EN: Resolve type hints after definitions. TH: ประเมินชนิดข้อมูลหลังนิยามชื่อ

import json  # EN: Encode and decode credentials and event records. TH: เข้ารหัสและถอดรหัสข้อมูลรับรองกับเหตุการณ์
import os  # EN: Read protected deployment settings. TH: อ่านค่าตั้งค่าที่ป้องกันไว้บนเซิร์ฟเวอร์
import re  # EN: Validate spreadsheet identifiers. TH: ตรวจรูปแบบรหัสชีต
from typing import Any  # EN: Type provider responses without trusting their shape. TH: ระบุชนิดข้อมูลตอบกลับที่ยังไม่เชื่อถือ
from urllib.parse import quote  # EN: Escape fixed tab ranges in API URLs. TH: เข้ารหัสช่วงเซลล์ใน URL

from google.auth.transport.requests import AuthorizedSession  # EN: Send signed requests to Sheets. TH: ส่งคำขอที่ยืนยันตัวตนไปยัง Sheets
from google.oauth2.service_account import Credentials  # EN: Load service-account credentials on the server. TH: โหลดข้อมูลรับรองบัญชีบริการฝั่งเซิร์ฟเวอร์


HEADERS = ["auth_user_id", "received_at", "event_id", "event_json"]  # EN: Require this exact four-column schema. TH: บังคับส่วนหัวสี่คอลัมน์นี้
MAX_ROWS = 2_000  # EN: Cap data rows per tab. TH: จำกัดจำนวนแถวข้อมูลต่อแท็บ
MAX_EVENT_CHARS = 8_000  # EN: Bound one JSON cell. TH: จำกัดความยาว JSON หนึ่งเซลล์
MAX_RESPONSE_BYTES = 8 * 1024 * 1024  # EN: Bound provider response memory. TH: จำกัดหน่วยความจำสำหรับผลตอบกลับ
_ID_RE = re.compile(r"^[A-Za-z0-9_-]{20,100}$")  # EN: Accept only ordinary spreadsheet IDs. TH: รับเฉพาะรหัสชีตรูปแบบปกติ


class SheetsStorageError(Exception):  # EN: Normalize provider and configuration failures. TH: รวมข้อผิดพลาดจากผู้ให้บริการและการตั้งค่า
    """EN: Signal a storage failure. TH: แจ้งข้อผิดพลาดของระบบเก็บข้อมูล"""


class SheetsStore:  # EN: Keep access scoped to one spreadsheet and two tabs. TH: จำกัดการเข้าถึงชีตเดียวสองแท็บ
    """EN: Read and write fixed event tabs. TH: อ่านและเขียนแท็บเหตุการณ์ที่กำหนดไว้"""

    def __init__(self, spreadsheet_id: str, credentials_json: str, session: Any = None):  # EN: Validate config before creating the client. TH: ตรวจการตั้งค่าก่อนสร้าง client
        if not _ID_RE.fullmatch(spreadsheet_id):  # EN: Reject malformed IDs before URL construction. TH: ปฏิเสธรหัสผิดรูปก่อนสร้าง URL
            raise SheetsStorageError("Invalid spreadsheet ID")  # EN: Report invalid configuration. TH: แจ้งการตั้งค่าที่ผิด
        if len(credentials_json) > 20_000:  # EN: Reject unexpectedly large secrets. TH: ปฏิเสธข้อมูลรับรองที่ใหญ่ผิดปกติ
            raise SheetsStorageError("Credentials are too large")  # EN: Stop before parsing. TH: หยุดก่อนแปลง JSON
        try:  # EN: Convert malformed credentials into one safe error. TH: แปลงข้อมูลรับรองที่ผิดเป็นข้อผิดพลาดที่ควบคุมได้
            info = json.loads(credentials_json)  # EN: Parse the service-account document. TH: แปลงเอกสารบัญชีบริการ
            if not isinstance(info, dict) or info.get("type") != "service_account":  # EN: Reject arrays and scalars before looking up credential fields. TH: ปฏิเสธ JSON ที่ไม่ใช่ออบเจ็กต์ก่อนอ่านข้อมูลรับรอง
                raise ValueError("Expected service account")  # EN: Require a service-account key, not an arbitrary JSON object. TH: บังคับเป็นคีย์บัญชีบริการ
            credentials = Credentials.from_service_account_info(  # EN: Load signed credentials outside tests. TH: โหลดข้อมูลสำหรับลงลายเซ็นนอกการทดสอบ
                info, scopes=["https://www.googleapis.com/auth/spreadsheets"]  # EN: Grant only the Sheets API scope. TH: ขอ scope เฉพาะ Sheets API
            ) if session is None else None  # EN: Permit a fake session in unit tests. TH: อนุญาต session จำลองใน unit test
        except (ValueError, TypeError, KeyError) as exc:  # EN: Catch expected parsing errors. TH: จับข้อผิดพลาดการแปลงที่คาดได้
            raise SheetsStorageError("Invalid Sheets credentials") from exc  # EN: Hide secret details from callers. TH: ไม่เปิดเผยรายละเอียดคีย์ต่อผู้เรียก
        self.spreadsheet_id = spreadsheet_id  # EN: Preserve the validated ID. TH: เก็บรหัสชีตที่ผ่านการตรวจ
        self.session = session or AuthorizedSession(credentials)  # EN: Use signed transport by default. TH: ใช้การเชื่อมต่อที่ยืนยันตัวตนเป็นค่าเริ่มต้น
        self.base = f"https://sheets.googleapis.com/v4/spreadsheets/{spreadsheet_id}"  # EN: Target only the selected spreadsheet. TH: จำกัด URL ไปยังชีตที่เลือก

    @staticmethod  # EN: Resolve a tab without instance state. TH: เลือกแท็บโดยไม่ใช้สถานะของออบเจ็กต์
    def _tab(collection: str) -> str:  # EN: Map an internal collection to a fixed tab. TH: แปลงชื่อชุดข้อมูลภายในเป็นแท็บที่กำหนด
        tabs = {"sensor_events": "SensorEvents", "alert_events": "AlertEvents"}  # EN: Allow only these two destinations. TH: อนุญาตปลายทางเพียงสองแท็บ
        if collection not in tabs:  # EN: Reject unknown or attacker-controlled tab names. TH: ปฏิเสธชื่อแท็บที่ไม่รู้จัก
            raise SheetsStorageError("Unsupported event collection")  # EN: Fail before contacting Sheets. TH: หยุดก่อนติดต่อ Sheets
        return tabs[collection]  # EN: Return the canonical tab name. TH: คืนชื่อแท็บมาตรฐาน

    def _request(self, method: str, url: str, **kwargs: Any) -> dict[str, Any]:  # EN: Send one bounded Sheets API request. TH: ส่งคำขอ Sheets ที่จำกัดเวลาและขนาด
        try:  # EN: Normalize transport and decode failures. TH: รวมข้อผิดพลาดการส่งและถอดรหัส
            response = self.session.request(method, url, timeout=10, stream=True, **kwargs)  # EN: Stream with a ten-second timeout. TH: รับแบบ stream โดยจำกัดสิบวินาที
            if response.status_code < 200 or response.status_code >= 300:  # EN: Require HTTP success. TH: ต้องได้รับ HTTP ที่สำเร็จ
                raise SheetsStorageError("Sheets request failed")  # EN: Do not leak provider response details. TH: ไม่เปิดเผยรายละเอียดตอบกลับของผู้ให้บริการ
            if hasattr(response, "iter_content"):  # EN: Bound real HTTP response bytes. TH: จำกัดจำนวนไบต์จาก HTTP จริง
                chunks = []  # EN: Collect chunks below the limit. TH: เก็บชิ้นข้อมูลที่ยังไม่เกินเพดาน
                size = 0  # EN: Track cumulative bytes. TH: นับไบต์สะสม
                for chunk in response.iter_content(chunk_size=65_536):  # EN: Read in bounded chunks. TH: อ่านทีละชิ้นขนาดจำกัด
                    size += len(chunk)  # EN: Account for the next chunk. TH: รวมขนาดชิ้นล่าสุด
                    if size > MAX_RESPONSE_BYTES:  # EN: Stop oversized responses. TH: หยุดผลตอบกลับที่ใหญ่เกิน
                        raise SheetsStorageError("Sheets response exceeds size limit")  # EN: Preserve the memory cap. TH: รักษาเพดานหน่วยความจำ
                    chunks.append(chunk)  # EN: Retain a safe chunk. TH: เก็บชิ้นข้อมูลที่ปลอดภัย
                body = json.loads(b"".join(chunks))  # EN: Decode the bounded JSON body. TH: ถอด JSON ที่ตรวจขนาดแล้ว
            else:  # EN: Support a small test session. TH: รองรับ session จำลองในการทดสอบ
                body = response.json()  # EN: Read the test response. TH: อ่านผลตอบกลับจำลอง
            if not isinstance(body, dict):  # EN: Require an object response. TH: บังคับผลตอบกลับเป็นออบเจ็กต์
                raise SheetsStorageError("Invalid Sheets response")  # EN: Reject malformed provider data. TH: ปฏิเสธข้อมูลผู้ให้บริการที่ผิดรูป
            return body  # EN: Return validated response shape. TH: คืนข้อมูลที่ตรวจรูปแบบแล้ว
        except SheetsStorageError:  # EN: Preserve deliberate storage errors. TH: คงข้อผิดพลาด storage ที่ตั้งใจแจ้ง
            raise  # EN: Let the caller fail closed. TH: ให้ผู้เรียกปิดการทำงานอย่างปลอดภัย
        except Exception as exc:  # EN: Catch network and JSON errors. TH: จับข้อผิดพลาดเครือข่ายและ JSON
            raise SheetsStorageError("Sheets request failed") from exc  # EN: Avoid leaking request details. TH: ไม่เปิดเผยรายละเอียดคำขอ
        finally:  # EN: Close the response even after an error. TH: ปิดผลตอบกลับแม้เกิดข้อผิดพลาด
            if "response" in locals() and hasattr(response, "close"):  # EN: Check whether a closable response exists. TH: ตรวจว่ามีผลตอบกลับให้ปิดหรือไม่
                response.close()  # EN: Release the connection. TH: คืนทรัพยากรการเชื่อมต่อ

    def _rows(self, collection: str) -> list[list[Any]]:  # EN: Read and validate one event tab. TH: อ่านและตรวจแท็บเหตุการณ์หนึ่งแท็บ
        tab = self._tab(collection)  # EN: Resolve a fixed tab name. TH: เลือกชื่อแท็บที่กำหนด
        # EN: Read one extra row to detect capacity overflow. TH: อ่านเพิ่มหนึ่งแถวเพื่อตรวจข้อมูลเกินเพดาน
        encoded = quote(f"{tab}!A1:D{MAX_ROWS + 2}", safe="")  # EN: Escape the bounded A:D range. TH: เข้ารหัสช่วง A:D ที่จำกัดแล้ว
        result = self._request("GET", f"{self.base}/values/{encoded}")  # EN: Fetch rows from Sheets. TH: ดึงแถวจาก Sheets
        rows = result.get("values", [])  # EN: Extract values or an empty fallback. TH: แยกค่าเซลล์หรือใช้รายการว่าง
        if not isinstance(rows, list) or not rows or rows[0] != HEADERS:  # EN: Verify the exact header row. TH: ตรวจหัวคอลัมน์ให้ตรงทุกช่อง
            raise SheetsStorageError("Sheets tab headers are missing")  # EN: Refuse unknown schemas. TH: ปฏิเสธโครงสร้างชีตที่ไม่รู้จัก
        if len(rows) > MAX_ROWS + 1:  # EN: Account for one header plus limited data rows. TH: นับหัวตารางหนึ่งแถวและแถวข้อมูลที่จำกัด
            raise SheetsStorageError("Sheets row limit exceeded")  # EN: Refuse over-capacity tabs. TH: ปฏิเสธแท็บที่เกินเพดาน
        return rows  # EN: Return checked rows. TH: คืนแถวที่ตรวจแล้ว

    def check_ready(self) -> None:  # EN: Probe both required tabs. TH: ตรวจแท็บที่จำเป็นทั้งคู่
        """EN: Confirm readable tab headers. TH: ยืนยันว่าอ่านหัวตารางได้"""
        for collection in ("sensor_events", "alert_events"):  # EN: Check sensor and alert data separately. TH: ตรวจข้อมูลเซนเซอร์และการแจ้งเตือนแยกกัน
            self._rows(collection)  # EN: Fail if a tab is missing or malformed. TH: แจ้งผิดพลาดหากแท็บหายหรือผิดรูป

    def append(self, collection: str, event: dict[str, Any]) -> None:  # EN: Append one validated event. TH: เพิ่มเหตุการณ์ที่ผ่านการตรวจหนึ่งรายการ
        rows = self._rows(collection)  # EN: Confirm schema and current capacity. TH: ตรวจโครงสร้างและพื้นที่คงเหลือ
        if len(rows) >= MAX_ROWS + 1:  # EN: Stop before exceeding the tab cap. TH: หยุดก่อนจำนวนแถวเกินเพดาน
            raise SheetsStorageError("Sheets row limit reached")  # EN: Reject unsafe growth. TH: ปฏิเสธการเพิ่มข้อมูลเกินขนาด
        owner = event.get("authUserId")  # EN: Read the verified owner field. TH: อ่านรหัสเจ้าของข้อมูลที่ยืนยันแล้ว
        if not isinstance(owner, str) or not owner or len(owner) > 256:  # EN: Require a bounded nonempty owner. TH: บังคับรหัสเจ้าของไม่ว่างและไม่ยาวเกิน
            raise SheetsStorageError("Invalid event owner")  # EN: Reject ownerless records. TH: ปฏิเสธระเบียนที่ไม่มีเจ้าของ
        payload = json.dumps(event, ensure_ascii=False, separators=(",", ":"), allow_nan=False)  # EN: Serialize compact UTF-8-safe JSON. TH: แปลงเหตุการณ์เป็น JSON กระชับ
        if len(payload) > MAX_EVENT_CHARS:  # EN: Guard the cell-length budget. TH: ตรวจเพดานความยาวเซลล์
            raise SheetsStorageError("Event exceeds Sheets cell limit")  # EN: Reject oversized events. TH: ปฏิเสธเหตุการณ์ที่ใหญ่เกิน
        from uuid import uuid4  # EN: Generate a unique event ID for this write. TH: สร้างรหัสเฉพาะของเหตุการณ์นี้
        tab = self._tab(collection)  # EN: Select a fixed event tab. TH: เลือกแท็บเหตุการณ์ที่กำหนด
        encoded = quote(f"{tab}!A:D", safe="")  # EN: Escape the append range. TH: เข้ารหัสช่วงที่เพิ่มข้อมูล
        result = self._request(  # EN: Submit one append request. TH: ส่งคำขอเพิ่มแถวหนึ่งครั้ง
            "POST",  # EN: Write through the Sheets append endpoint. TH: เขียนผ่าน endpoint เพิ่มแถว
            f"{self.base}/values/{encoded}:append",  # EN: Target the validated spreadsheet and tab. TH: ใช้ชีตและแท็บที่ตรวจแล้ว
            params={"valueInputOption": "RAW", "insertDataOption": "INSERT_ROWS"},  # EN: Prevent formula evaluation and insert one row. TH: ป้องกันการประเมินสูตรและเพิ่มหนึ่งแถว
            json={"majorDimension": "ROWS", "values": [[owner, event.get("receivedAt", ""), uuid4().hex, payload]]},  # EN: Supply the fixed four columns. TH: ส่งข้อมูลสี่คอลัมน์ที่กำหนด
        )  # EN: Complete the append request. TH: จบคำขอเพิ่มแถว
        if result.get("updates", {}).get("updatedRows") != 1:  # EN: Verify exactly one row was reported. TH: ตรวจว่าระบบยืนยันเพิ่มหนึ่งแถว
            raise SheetsStorageError("Sheets did not confirm the appended row")  # EN: Never claim an unconfirmed write. TH: ไม่อ้างว่าเขียนสำเร็จหากไม่ยืนยัน

    def read(self, collection: str, owner: str, limit: int) -> list[dict[str, Any]]:  # EN: Return only one verified owner's recent events. TH: คืนเฉพาะเหตุการณ์ล่าสุดของเจ้าของที่ยืนยันแล้ว
        if not isinstance(limit, int) or isinstance(limit, bool) or limit < 1 or limit > MAX_ROWS:  # EN: Reject zero, negative, and oversized limits. TH: ปฏิเสธจำนวนที่เป็นศูนย์ ติดลบ หรือเกินเพดาน
            raise SheetsStorageError("Invalid event limit")  # EN: Avoid a zero-slice returning every row. TH: ป้องกันการแบ่งช่วงศูนย์ที่คืนทุกแถว
        rows = self._rows(collection)  # EN: Read a validated tab. TH: อ่านแท็บที่ผ่านการตรวจ
        events = []  # EN: Collect records belonging to this owner. TH: เก็บระเบียนเฉพาะเจ้าของนี้
        for row in rows[1:]:  # EN: Skip the header row. TH: ข้ามแถวหัวตาราง
            if not isinstance(row, list) or len(row) != 4 or row[0] != owner:  # EN: Ignore malformed and other-owner rows. TH: ข้ามแถวผิดรูปและของผู้อื่น
                continue  # EN: Move to the next row. TH: ไปยังแถวถัดไป
            try:  # EN: Decode stored JSON without trusting cell content. TH: ถอด JSON โดยไม่เชื่อเนื้อหาเซลล์ทันที
                event = json.loads(row[3])  # EN: Parse one event cell. TH: แปลงเซลล์เหตุการณ์หนึ่งรายการ
            except (ValueError, TypeError):  # EN: Skip corrupted cells. TH: ข้ามเซลล์ที่เสียหาย
                continue  # EN: Continue reading usable rows. TH: อ่านแถวที่ใช้ได้ต่อ
            if isinstance(event, dict) and event.get("authUserId") == owner:  # EN: Double-check the owner inside JSON. TH: ตรวจเจ้าของใน JSON ซ้ำอีกชั้น
                events.append(event)  # EN: Include a valid owned event. TH: เพิ่มเหตุการณ์ที่เป็นของผู้ใช้นี้
        events.sort(key=lambda item: str(item.get("receivedAt", "")))  # EN: Order by recorded receipt time. TH: เรียงตามเวลารับข้อมูล
        return events[-limit:]  # EN: Return at most the requested recent count. TH: คืนรายการล่าสุดไม่เกินจำนวนที่ขอ

    def delete_owner(self, owner: str) -> None:  # EN: Clear visible cells owned by one account. TH: ล้างเซลล์ที่มองเห็นของบัญชีหนึ่ง
        # EN: Cell clearing cannot erase revision history; the account-deletion API refuses Sheets. TH: การล้างเซลล์ไม่ลบประวัติเวอร์ชัน API ลบบัญชีจึงไม่ใช้ Sheets
        # EN: Clearing preserves other owners and row indexes; empty rows still use capacity. TH: การล้างไม่กระทบเจ้าของอื่นหรือเลขแถว แต่แถวว่างยังใช้พื้นที่
        for collection in ("sensor_events", "alert_events"):  # EN: Inspect both event tabs. TH: ตรวจแท็บเหตุการณ์ทั้งสอง
            rows = self._rows(collection)  # EN: Read current rows. TH: อ่านแถวปัจจุบัน
            tab = self._tab(collection)  # EN: Resolve the fixed tab. TH: เลือกแท็บที่กำหนด
            ranges = [f"{tab}!A{index}:D{index}" for index, row in enumerate(rows[1:], 2)  # EN: Index data rows after the header. TH: นับเลขแถวข้อมูลหลังหัวตาราง
                      if isinstance(row, list) and row and row[0] == owner]  # EN: Build ranges only for matching owner rows. TH: สร้างช่วงเฉพาะแถวของเจ้าของนี้
            for offset in range(0, len(ranges), 100):  # EN: Batch at most 100 clear ranges. TH: แบ่งคำขอล้างไม่เกิน 100 ช่วง
                self._request("POST", f"{self.base}/values:batchClear",  # EN: Use the Sheets batch-clear endpoint. TH: ใช้ endpoint ล้างหลายช่วงของ Sheets
                              json={"ranges": ranges[offset:offset + 100]})  # EN: Clear only selected cells. TH: ล้างเฉพาะเซลล์ที่เลือก


def store_from_env() -> SheetsStore | None:  # EN: Build optional Sheets storage from server settings. TH: สร้าง storage Sheets จากค่าฝั่งเซิร์ฟเวอร์
    spreadsheet_id = os.getenv("DOZ_SHEETS_SPREADSHEET_ID", "").strip()  # EN: Read the target spreadsheet ID. TH: อ่านรหัสชีตเป้าหมาย
    credentials_json = os.getenv("DOZ_GOOGLE_SERVICE_ACCOUNT_JSON", "").strip()  # EN: Read the protected service-account JSON. TH: อ่าน JSON บัญชีบริการที่ป้องกันไว้
    if not spreadsheet_id and not credentials_json:  # EN: Treat an entirely absent setup as disabled. TH: ถือว่าไม่เปิดใช้เมื่อไม่มีค่าทั้งคู่
        return None  # EN: Leave optional storage off. TH: ปิด storage ทางเลือก
    if not spreadsheet_id or not credentials_json:  # EN: Detect half-configured deployments. TH: ตรวจการตั้งค่าที่มีเพียงค่าเดียว
        raise SheetsStorageError("Incomplete Sheets configuration")  # EN: Report setup failure safely. TH: แจ้งการตั้งค่าไม่ครบอย่างปลอดภัย
    return SheetsStore(spreadsheet_id, credentials_json)  # EN: Create the validated storage adapter. TH: สร้างตัวเชื่อมข้อมูลที่ผ่านการตรวจ
