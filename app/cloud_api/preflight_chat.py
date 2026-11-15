#!/usr/bin/env python3
"""EN: Check deployed Doz routes without sensor or profile data. TH: ตรวจเส้นทาง Doz โดยไม่ส่งข้อมูลเซนเซอร์หรือโปรไฟล์"""

import argparse  # EN: Read the preflight mode from command-line arguments. TH: อ่านโหมดตรวจจากอาร์กิวเมนต์
import json  # EN: Encode test bodies and decode API responses. TH: เข้ารหัสคำขอทดสอบและถอดผล API
import os  # EN: Read the API URL and optional test token from the environment. TH: อ่าน URL API และ test token จาก environment
import sys  # EN: Print failures to stderr and return process status. TH: พิมพ์ข้อผิดพลาดไป stderr และคืนสถานะโปรเซส
from typing import Dict, Optional, Tuple, Any  # EN: Describe the small request/response contract. TH: ระบุชนิดข้อมูลคำขอและผลตอบกลับ
from urllib.error import HTTPError, URLError  # EN: Distinguish HTTP rejection from network failure. TH: แยกการปฏิเสธ HTTP จากเครือข่ายล้มเหลว
from urllib.parse import urlsplit, urlunsplit  # EN: Validate and normalize the API base URL. TH: ตรวจและปรับ URL ตั้งต้น
from urllib.request import HTTPRedirectHandler, Request, build_opener  # EN: Open HTTPS requests with redirect control. TH: เปิดคำขอ HTTPS โดยควบคุม redirect


class _RejectRedirects(HTTPRedirectHandler):  # EN: Keep the test token on the configured origin. TH: จำกัด test token ให้อยู่กับ origin ที่กำหนด
    def redirect_request(self, request, fp, code, msg, headers, newurl):  # EN: Intercept every redirect before a follow-up request. TH: ดัก redirect ทุกครั้งก่อนส่งคำขอถัดไป
        return None  # EN: Turn redirects into HTTP errors without forwarding Authorization. TH: ทำ redirect เป็น HTTP error โดยไม่ส่ง Authorization ต่อ


_OPENER = build_opener(_RejectRedirects())  # EN: Reuse a non-redirecting opener for all preflight calls. TH: ใช้ opener ที่ไม่ตาม redirect กับทุกคำขอ preflight


def parse_base_url(value: str) -> str:  # EN: Screen a configured HTTPS API origin. TH: ตรวจ URL HTTPS ที่ตั้งค่า
    """EN: Accept only a clean HTTPS API base. TH: รับเฉพาะ URL ตั้งต้น HTTPS ที่สะอาด"""
    parts = urlsplit(value.strip())  # EN: Remove outer whitespace and parse URL components. TH: ตัดช่องว่างรอบและแยกส่วน URL
    if (  # EN: Reject insecure or endpoint-specific bases. TH: ปฏิเสธ URL ที่ไม่ปลอดภัยหรือชี้ endpoint เฉพาะ
        parts.scheme != "https"  # EN: Require encrypted transport. TH: บังคับ HTTPS
        or not parts.hostname  # EN: Require a host. TH: บังคับมีชื่อโฮสต์
        or parts.username is not None  # EN: Forbid credentials embedded in URL. TH: ห้ามชื่อผู้ใช้ใน URL
        or parts.password is not None  # EN: Forbid password in URL. TH: ห้ามรหัสผ่านใน URL
        or parts.query  # EN: Forbid query parameters. TH: ห้าม query parameters
        or parts.fragment  # EN: Forbid URL fragments. TH: ห้าม fragment
        or parts.path.rstrip("/").endswith(("/chat", "/health", "/ready"))  # EN: Do not append a route twice. TH: ไม่ต่อท้ายเส้นทางซ้ำ
    ):  # EN: Finish URL checks. TH: จบเงื่อนไขตรวจ URL
        raise ValueError("DOZ_API_BASE_URL must be a clean HTTPS API base URL.")  # EN: Report a safe configuration error. TH: แจ้งการตั้งค่าผิดโดยไม่เปิดเผยคีย์
    return urlunsplit((parts.scheme, parts.netloc, parts.path.rstrip("/"), "", ""))  # EN: Return a route-free base. TH: คืน URL ตั้งต้นที่ไม่มี query


def request_json(  # EN: Send one bounded request and parse JSON. TH: ส่งคำขอที่จำกัดขนาดแล้วอ่าน JSON
    url: str,  # EN: Receive the target endpoint. TH: รับ URL ปลายทาง
    *,  # EN: Require named optional arguments. TH: บังคับระบุชื่ออาร์กิวเมนต์เสริม
    token: Optional[str] = None,  # EN: Accept an optional test token. TH: รับ test token ที่อาจไม่มี
    body: Optional[Dict[str, Any]] = None,  # EN: Accept an optional JSON body. TH: รับ JSON body ที่อาจไม่มี
) -> Tuple[int, Any]:  # EN: Return status and parsed body. TH: คืนรหัสสถานะและข้อมูลที่แปลงแล้ว
    """EN: Return only status and bounded JSON. TH: คืนเฉพาะสถานะและ JSON ที่จำกัดขนาด"""
    headers = {"Accept": "application/json"}  # EN: Request a JSON response. TH: ขอผลตอบกลับ JSON
    payload = None  # EN: Default to a GET request. TH: ใช้ GET เมื่อไม่มี body
    if body is not None:  # EN: Encode a supplied POST body. TH: แปลง body สำหรับ POST
        headers["Content-Type"] = "application/json"  # EN: Declare JSON input. TH: ระบุชนิดข้อมูลที่ส่งเป็น JSON
        payload = json.dumps(body).encode("utf-8")  # EN: Encode the test object in UTF-8. TH: แปลงข้อมูลทดสอบเป็น UTF-8
    if token is not None:  # EN: Attach a token only when supplied. TH: แนบ token เฉพาะเมื่อมี
        headers["Authorization"] = f"Bearer {token}"  # EN: Use the bearer scheme. TH: ใช้รูปแบบ bearer
    request = Request(url, data=payload, headers=headers, method="POST" if payload else "GET")  # EN: Construct one HTTP request. TH: สร้างคำขอ HTTP หนึ่งรายการ
    try:  # EN: Bound network work and normalize HTTP errors. TH: จำกัดงานเครือข่ายและจัดการ HTTP error
        with _OPENER.open(request, timeout=12) as response:  # EN: Never follow a redirect carrying the test token. TH: ห้ามตาม redirect ที่อาจพา test token ไปด้วย
            raw = response.read(64_001)  # EN: Read one byte beyond the 64 KB cap. TH: อ่านเกินเพดาน 64 KB หนึ่งไบต์เพื่อตรวจขนาด
            if len(raw) > 64_000:  # EN: Detect an oversized response. TH: ตรวจผลตอบกลับใหญ่เกิน
                raise ValueError("API response exceeded the 64 KB preflight limit.")  # EN: Stop before parsing. TH: หยุดก่อนแปลง JSON
            return response.status, json.loads(raw.decode("utf-8"))  # EN: Return status and decoded JSON. TH: คืนสถานะและ JSON ที่ถอดแล้ว
    except HTTPError as error:  # EN: Keep redirects and unauthorized statuses as data. TH: คืน redirect และสถานะไม่อนุญาตเป็นข้อมูล
        return error.code, None  # EN: Never forward the token after a redirect. TH: ไม่ส่ง token ต่อหลัง redirect


def check_invalid_tokens(base_url: str) -> bool:  # EN: Confirm protected routes reject an invalid credential. TH: ยืนยันว่า route ป้องกันปฏิเสธ token ที่ผิด
    invalid_status, _ = request_json(  # EN: Probe chat without a valid user. TH: ทดสอบแชตโดยไม่มีผู้ใช้ที่ถูกต้อง
        f"{base_url}/chat",  # EN: Target the chat route. TH: เรียกเส้นทางแชต
        token="doz-preflight-invalid-token",  # EN: Send a fixed obviously invalid token. TH: ส่ง token ทดสอบที่ผิดแน่นอน
        body={"question": "invalid-token check", "prompt": "invalid-token check"},  # EN: Send no private data. TH: ไม่ส่งข้อมูลส่วนตัว
    )  # EN: Finish the chat rejection probe. TH: จบการทดสอบแชต
    if invalid_status != 401:  # EN: Require unauthorized status. TH: ต้องตอบว่าไม่อนุญาต
        print(f"Invalid-token check failed: expected HTTP 401, got {invalid_status}.", file=sys.stderr)  # EN: Report status only. TH: รายงานเฉพาะรหัสสถานะ
        return False  # EN: Fail the preflight. TH: ให้การตรวจไม่ผ่าน
    invalid_advice_status, _ = request_json(  # EN: Probe advice with the same invalid credential. TH: ทดสอบคำแนะนำด้วย token ผิดเดียวกัน
        f"{base_url}/advice",  # EN: Target the advice route. TH: เรียกเส้นทางคำแนะนำ
        token="doz-preflight-invalid-token",  # EN: Avoid a real user session. TH: ไม่ใช้ session ผู้ใช้จริง
        body={"status": "Watch", "alertLevel": "Info", "sensor": ""},  # EN: Use harmless test inputs. TH: ใช้ข้อมูลทดสอบที่ไม่อ่อนไหว
    )  # EN: Finish the advice rejection probe. TH: จบการทดสอบคำแนะนำ
    if invalid_advice_status != 401:  # EN: Require unauthorized status again. TH: ต้องปฏิเสธอีกเส้นทาง
        print(f"Invalid-token advice check failed: expected HTTP 401, got {invalid_advice_status}.", file=sys.stderr)  # EN: Report only a status mismatch. TH: รายงานเฉพาะสถานะที่ไม่ตรง
        return False  # EN: Fail the preflight. TH: ให้การตรวจไม่ผ่าน
    print("Invalid-token checks: HTTP 401 for /chat and /advice as expected.")  # EN: Confirm both guards. TH: ยืนยันการป้องกันทั้งสองเส้นทาง
    return True  # EN: Allow the caller to finish. TH: ให้ผู้เรียกทำงานต่อ


def main() -> int:  # EN: Run the selected deployment checks. TH: เรียกชุดตรวจ deploy ตามโหมดที่เลือก
    """EN: Check readiness, authenticated routes, and invalid-token rejection. TH: ตรวจความพร้อม route ที่ยืนยันตัวตนและการปฏิเสธ token ผิด"""
    parser = argparse.ArgumentParser(description=__doc__)  # EN: Build command-line help from the module purpose. TH: สร้างคำอธิบาย CLI จากหน้าที่ไฟล์
    modes = parser.add_mutually_exclusive_group()  # EN: Prevent conflicting public-only and LLM requirements. TH: ห้ามเลือกโหมดสาธารณะพร้อมบังคับ LLM
    modes.add_argument(  # EN: Add a strict provider test. TH: เพิ่มโหมดตรวจผู้ให้บริการ AI แบบเข้มงวด
        "--require-llm",  # EN: Name the strict flag. TH: ตั้งชื่อ flag เข้มงวด
        action="store_true",  # EN: Use a boolean switch. TH: ใช้สวิตช์จริง/เท็จ
        help="Fail unless /chat confirms mode=llm and /advice confirms mode=rag.",  # EN: Describe expected live modes. TH: อธิบายโหมดที่ต้องได้
    )  # EN: Finish the flag definition. TH: จบนิยาม flag
    modes.add_argument("--public-only", action="store_true", help="Check readiness and invalid-token rejection without a user token.")  # EN: Permit non-sensitive deployment smoke checks. TH: ให้ตรวจ deploy โดยไม่ใช้ token ผู้ใช้
    args = parser.parse_args()  # EN: Read the selected mode. TH: อ่านโหมดที่เลือก
    try:  # EN: Validate the API destination before sending any token. TH: ตรวจปลายทาง API ก่อนส่ง token
        base_url = parse_base_url(os.environ.get("DOZ_API_BASE_URL", ""))  # EN: Read the configured API base. TH: อ่าน URL ตั้งต้นที่กำหนด
    except ValueError as error:  # EN: Catch malformed destinations. TH: จับ URL ปลายทางผิดรูป
        print(str(error), file=sys.stderr)  # EN: Print the safe configuration error. TH: พิมพ์ข้อผิดพลาดการตั้งค่าที่ปลอดภัย
        return 2  # EN: Stop before network requests. TH: หยุดก่อนส่งคำขอ
    token = os.environ.get("DOZ_CHAT_TEST_TOKEN", "").strip()  # EN: Read an optional short-lived test token. TH: อ่าน test token อายุสั้นที่อาจไม่มี
    if not token and not args.public_only:  # EN: Require a real test token only for authenticated checks. TH: บังคับ test token เฉพาะการตรวจแบบยืนยันตัวตน
        print("Set DOZ_CHAT_TEST_TOKEN to a short-lived test-account access token.", file=sys.stderr)  # EN: Request a test token without echoing it. TH: ขอ test token โดยไม่พิมพ์ค่า
        return 2  # EN: Refuse authenticated tests without credentials. TH: ปฏิเสธการตรวจแบบมีบัญชีเมื่อไม่มี token

    try:  # EN: Convert network and parsing failures to a bounded exit code. TH: แปลงข้อผิดพลาดเครือข่ายและการแปลงเป็นรหัสจบ
        # EN: Readiness requires Auth configuration, unlike process liveness at /health.
        # TH: /ready ต้องตั้งค่า Auth ครบ ต่างจาก /health ที่ตรวจแค่ว่า process ยังทำงาน
        ready_status, ready = request_json(f"{base_url}/ready")  # EN: Probe configured Auth and enabled dependencies. TH: ตรวจ Auth และ dependency ที่เปิดใช้
        if ready_status != 200 or not isinstance(ready, dict) or ready.get("status") != "ready":  # EN: Require the expected readiness contract. TH: บังคับผลความพร้อมตามข้อตกลง
            print(f"Readiness check failed: HTTP {ready_status}.", file=sys.stderr)  # EN: Report status without response content. TH: รายงานเฉพาะสถานะไม่พิมพ์เนื้อหา
            return 1  # EN: Fail the preflight. TH: ให้การตรวจไม่ผ่าน
        print("Readiness check: HTTP 200; status=ready.")  # EN: Confirm service readiness. TH: ยืนยันความพร้อมบริการ

        if args.public_only:  # EN: Stop before authenticated chat and advice calls. TH: หยุดก่อนเรียกแชตและคำแนะนำแบบผู้ใช้จริง
            return 0 if check_invalid_tokens(base_url) else 1  # EN: Verify guards without credentials. TH: ตรวจการป้องกันโดยไม่ใช้คีย์ผู้ใช้

        chat_status, chat = request_json(  # EN: Test authenticated chat with a harmless prompt. TH: ทดสอบแชตด้วยข้อความไม่อ่อนไหว
            f"{base_url}/chat",  # EN: Use the protected chat route. TH: ใช้เส้นทางแชตที่ป้องกัน
            token=token,  # EN: Use only the test account token. TH: ใช้เฉพาะ token บัญชีทดสอบ
            body={  # EN: Keep the request free of private data. TH: ไม่ใส่ข้อมูลส่วนตัวในคำขอ
                "question": "Reply with READY only. This is a deployment test; no sensor or personal data.",  # EN: Ask a fixed simple question. TH: ถามข้อความทดสอบคงที่
                "prompt": "Reply with READY only. This is a deployment test; no sensor or personal data.",  # EN: Support the legacy prompt field. TH: รองรับช่อง prompt เดิม
            },  # EN: Finish the safe body. TH: จบ body ทดสอบ
        )  # EN: Finish the chat request. TH: จบคำขอแชต
        if chat_status != 200 or not isinstance(chat, dict):  # EN: Require a JSON success response. TH: บังคับผลสำเร็จเป็น JSON
            print(f"Authenticated chat check failed: HTTP {chat_status}.", file=sys.stderr)  # EN: Print status only. TH: พิมพ์เฉพาะสถานะ
            return 1  # EN: Stop failed chat preflight. TH: หยุดเมื่อแชตไม่ผ่าน
        mode = chat.get("mode")  # EN: Read the reported response mode. TH: อ่านโหมดที่ตอบ
        answer = chat.get("answer")  # EN: Read the answer only to validate presence. TH: อ่านคำตอบเพื่อตรวจว่ามีเท่านั้น
        if mode not in {"llm", "fallback"} or not isinstance(answer, str) or not answer.strip():  # EN: Verify chat response structure. TH: ตรวจโครงสร้างคำตอบแชต
            print("Chat response contract failed (expected mode and non-empty answer).", file=sys.stderr)  # EN: Avoid printing model text. TH: ไม่พิมพ์เนื้อหาคำตอบโมเดล
            return 1  # EN: Fail invalid response. TH: ให้ผลตอบกลับผิดรูปไม่ผ่าน
        print(f"Authenticated chat: HTTP 200; mode={mode}; answer_present=yes.")  # EN: Print metadata only. TH: พิมพ์เฉพาะข้อมูลสถานะ
        if args.require_llm and mode != "llm":  # EN: Enforce live LLM mode when requested. TH: บังคับใช้ LLM จริงเมื่อร้องขอ
            print("LLM was required, but the server returned fallback mode.", file=sys.stderr)  # EN: Identify fallback without leaking content. TH: แจ้ง fallback โดยไม่เปิดเผยเนื้อหา
            return 1  # EN: Fail the strict mode. TH: ให้โหมดเข้มงวดไม่ผ่าน

        advice_status, advice = request_json(  # EN: Test authenticated advice with fixed sample input. TH: ทดสอบคำแนะนำด้วยข้อมูลตัวอย่างคงที่
            f"{base_url}/advice",  # EN: Use the protected advice route. TH: ใช้เส้นทางคำแนะนำที่ป้องกัน
            token=token,  # EN: Use the short-lived test session. TH: ใช้ session ทดสอบอายุสั้น
            body={  # EN: Avoid personal sensor information. TH: ไม่ส่งค่าจากเซนเซอร์ส่วนตัว
                "status": "Watch",  # EN: Provide a known sample state. TH: ใช้สถานะตัวอย่างที่รู้จัก
                "alertLevel": "Info",  # EN: Provide a harmless alert level. TH: ใช้ระดับแจ้งเตือนตัวอย่าง
                "sensor": "",  # EN: Send no sensor values. TH: ไม่ส่งค่าเซนเซอร์
            },  # EN: Finish the sample request. TH: จบคำขอตัวอย่าง
        )  # EN: Finish the advice request. TH: จบคำขอคำแนะนำ
        if advice_status != 200 or not isinstance(advice, dict):  # EN: Require a JSON success response. TH: บังคับผลสำเร็จเป็น JSON
            print(f"Authenticated advice check failed: HTTP {advice_status}.", file=sys.stderr)  # EN: Report only HTTP status. TH: รายงานเฉพาะสถานะ HTTP
            return 1  # EN: Fail an unavailable route. TH: ให้เส้นทางที่ใช้ไม่ได้ไม่ผ่าน
        advice_mode = advice.get("mode")  # EN: Read advice provider mode. TH: อ่านโหมดผู้ให้คำแนะนำ
        advice_text = advice.get("advice")  # EN: Check for nonempty advice without printing it. TH: ตรวจข้อความคำแนะนำโดยไม่พิมพ์
        if (  # EN: Validate the advice response contract. TH: ตรวจข้อตกลงผลตอบกลับคำแนะนำ
            advice_mode not in {"rag", "fallback"}  # EN: Permit only known modes. TH: รับเฉพาะโหมดที่รู้จัก
            or not isinstance(advice_text, str)  # EN: Require text output. TH: บังคับผลเป็นข้อความ
            or not advice_text.strip()  # EN: Reject whitespace-only advice. TH: ปฏิเสธข้อความว่าง
        ):  # EN: Finish advice checks. TH: จบเงื่อนไขตรวจคำแนะนำ
            print("Advice response contract failed (expected mode and non-empty advice).", file=sys.stderr)  # EN: Avoid exposing advice content. TH: ไม่เปิดเผยเนื้อหาคำแนะนำ
            return 1  # EN: Fail invalid provider output. TH: ให้ผลผิดรูปไม่ผ่าน
        print(f"Authenticated advice: HTTP 200; mode={advice_mode}; advice_present=yes.")  # EN: Report mode only. TH: รายงานเฉพาะโหมด
        if args.require_llm and advice_mode != "rag":  # EN: Require RAG when strict mode is chosen. TH: บังคับ RAG เมื่อเลือกโหมดเข้มงวด
            print("LLM was required, but /advice returned deterministic fallback mode.", file=sys.stderr)  # EN: Explain the fallback. TH: แจ้งว่าใช้ fallback
            return 1  # EN: Fail strict mode. TH: ให้โหมดเข้มงวดไม่ผ่าน

        if not check_invalid_tokens(base_url):  # EN: Reject a deployment that accepts a fake token. TH: ปฏิเสธ deploy ที่รับ token ปลอม
            return 1  # EN: Report failed authorization enforcement. TH: แจ้งว่าการป้องกันไม่ผ่าน
    except (TimeoutError, URLError, OSError, ValueError, json.JSONDecodeError) as error:  # EN: Catch expected network and decoding errors. TH: จับข้อผิดพลาดเครือข่ายและการถอดข้อมูลที่คาดได้
        print(f"Preflight failed ({type(error).__name__}); response details were not printed.", file=sys.stderr)  # EN: Avoid printing tokens or response bodies. TH: ไม่พิมพ์ token หรือเนื้อหาผลตอบกลับ
        return 1  # EN: Report a controlled failure. TH: แจ้งว่าการตรวจไม่ผ่านแบบควบคุม
    return 0  # EN: Report all required checks passed. TH: แจ้งว่าการตรวจทั้งหมดผ่าน


if __name__ == "__main__":  # EN: Run only when called as a script. TH: ทำงานเมื่อเรียกไฟล์โดยตรง
    raise SystemExit(main())  # EN: Return the preflight exit code to the shell. TH: ส่งรหัสผลลัพธ์กลับ shell
