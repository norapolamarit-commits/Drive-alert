from datetime import datetime  # EN: Parse and format event timestamps. TH: parse และจัดรูป timestamp ของ event
from html import escape  # EN: Escape dynamic dashboard values before HTML rendering. TH: escape ค่า dashboard ก่อนแสดงเป็น HTML
import json  # EN: Decode requests and encode stored/API JSON. TH: decode request และ encode JSON สำหรับ storage/API
import logging  # EN: Emit sanitized operational diagnostics. TH: บันทึกข้อมูลวินิจฉัยระบบที่ผ่านการ sanitize
import math  # EN: Validate finite sensor and configuration numbers. TH: ตรวจค่าตัวเลข sensor และ config ว่า finite
import os  # EN: Read environment configuration and filesystem-related flags. TH: อ่าน config environment และ flag ที่เกี่ยวกับระบบ
import re  # EN: Validate identifiers and apply text guard patterns. TH: ตรวจ identifier และใช้รูปแบบกรองข้อความ
from collections import Counter, OrderedDict, deque  # EN: Track bounded rate limits and event aggregates. TH: ติดตาม rate limit และสรุป event ภายใต้ขอบเขต
from math import ceil  # EN: Round display and pagination counts upward. TH: ปัดจำนวนแสดงผลและ pagination ขึ้น
from threading import BoundedSemaphore, Lock  # EN: Bound concurrent provider calls and protect shared in-memory state. TH: จำกัด provider calls พร้อมกันและป้องกัน shared state
import time  # EN: Track deadlines, freshness, and rate-limit windows. TH: ติดตาม deadline ความใหม่ของข้อมูล และช่วง rate limit
from typing import Any, Optional  # EN: Describe flexible JSON values and optional results. TH: ระบุชนิด JSON ที่ยืดหยุ่นและผลลัพธ์ที่อาจไม่มี
from urllib.parse import quote, urlsplit  # EN: Encode URL path components and validate endpoint structure. TH: encode ส่วน path URL และตรวจโครงสร้าง endpoint
from uuid import uuid4  # EN: Generate opaque request correlation IDs. TH: สร้างรหัส request สำหรับติดตามแบบไม่เปิดเผยข้อมูล

import httpx  # EN: Send bounded asynchronous requests to configured providers. TH: ส่งคำขอ async ที่จำกัดขนาดไปยัง provider ที่ตั้งไว้
from fastapi import FastAPI, Header, HTTPException, Query, Request  # EN: Define API routes, validated headers, errors, and request access. TH: กำหนด route, header, error และการเข้าถึง request
from fastapi.responses import HTMLResponse  # EN: Return escaped local dashboard markup. TH: ส่ง markup dashboard ภายในที่ escape แล้ว
from pydantic import BaseModel, ConfigDict, Field  # EN: Validate API request schemas and field constraints. TH: ตรวจ schema request API และข้อจำกัด field

try:  # EN: Make Firestore an optional deployment dependency. TH: ทำให้ Firestore เป็น dependency ที่เลือกเปิดได้
    from google.cloud import firestore  # EN: Load the Firestore client only when the package is installed. TH: โหลด client Firestore เมื่อมี package ติดตั้ง
except ImportError:  # EN: Keep local/test startup possible without Firestore packages. TH: ให้ local/test เริ่มได้แม้ไม่มี package Firestore
    firestore = None  # EN: Use the explicit unavailable marker for fail-closed configuration checks. TH: กำหนด marker ว่าไม่พร้อมให้ config checks ปิดการทำงาน


app = FastAPI(title="doz Cloud API")  # EN: Create the ASGI application served by Uvicorn/Render. TH: สร้าง ASGI app ที่ Uvicorn/Render ใช้
LOGGER = logging.getLogger("doz.request")  # EN: Keep request diagnostics separate from provider logs. TH: แยก log request ออกจาก log provider

# EN: Bound incoming event bodies and per-worker in-memory history against RAM exhaustion.
# TH: จำกัด body event และประวัติใน RAM ของแต่ละ worker เพื่อป้องกันใช้หน่วยความจำจนหมด
MAX_CLOUD_EVENT_BYTES = 32 * 1024  # EN: Cap one health-event request body at 32 KiB. TH: จำกัด body health event หนึ่งคำขอไว้ 32 KiB
MAX_AI_REQUEST_BYTES = 64 * 1024  # EN: Cap chat/advice request bodies at 64 KiB. TH: จำกัด body คำขอ chat/advice ไว้ 64 KiB
MAX_IN_MEMORY_EVENTS = 1_000  # EN: Keep only the latest bounded event copies per worker. TH: เก็บสำเนา event ใน worker ล่าสุดไม่เกินจำนวนนี้
MAX_FIRESTORE_DEVICES_PER_USER = 16  # EN: Bound device fan-out for per-user Firestore queries. TH: จำกัดจำนวนอุปกรณ์ที่ query Firestore ต่อผู้ใช้
MAX_BEARER_TOKEN_CHARS = 8_192  # EN: Bound credentials before forwarding them. TH: จำกัด credential ก่อนส่งต่อ
MAX_AUTH_USER_ID_CHARS = 256  # EN: Bound verified identity strings before using them as state keys. TH: จำกัดความยาว identity ที่ยืนยันแล้วก่อนใช้เป็น key ของ state
MAX_ABS_SENSOR_VALUE = 1_000_000.0  # EN: Reject implausibly huge sensor values while covering signed 16-bit raw motion counts. TH: ปฏิเสธค่า sensor ที่เกินจริงโดยยังครอบคลุม raw motion count แบบ signed 16 บิต
MAX_MAX30102_ADC = (1 << 18) - 1  # EN: Set the MAX30102's unsigned 18-bit ADC maximum. TH: กำหนดค่าสูงสุดของ ADC MAX30102 แบบ unsigned 18 บิต
MAX_DEVICE_TIMESTAMP_MS = (1 << 63) - 1  # EN: Match device milliseconds to Firestore's signed 64-bit integer limit. TH: จำกัดเวลาอุปกรณ์หน่วยมิลลิวินาทีให้อยู่ในช่วง signed 64-bit ของ Firestore
MAX_LLM_RESPONSE_BYTES = 128 * 1024  # EN: Bound provider JSON parsing and object expansion. TH: จำกัดการ parse JSON และการขยาย object จาก provider
MAX_LLM_TEXT_CHARS = 16_000  # EN: Bound model text returned to API clients. TH: จำกัดความยาวข้อความโมเดลที่ส่งกลับ client


def _reject_duplicate_json_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:  # EN: Decode object pairs while rejecting ambiguous repeated keys. TH: แปลงคู่ข้อมูล object พร้อมปฏิเสธ key ซ้ำที่กำกวม
    """Reject ambiguous duplicate JSON keys. / ปฏิเสธ key JSON ที่ซ้ำและกำกวม"""
    result: dict[str, Any] = {}  # EN: Build a mapping only after checking each key. TH: สร้าง mapping หลังตรวจ key ทีละรายการ
    for key, value in pairs:  # EN: Inspect every key/value pair produced by the JSON decoder. TH: ตรวจคู่ key/value ทั้งหมดจาก JSON decoder
        if key in result:  # EN: Detect keys whose later value could silently override an earlier one. TH: ตรวจ key ที่ค่าทีหลังอาจเขียนทับค่าก่อนหน้าโดยเงียบ ๆ
            raise ValueError("Duplicate JSON object key.")  # EN: Fail closed when the request has ambiguous meaning. TH: ปฏิเสธเมื่อ request มีความหมายกำกวม
        result[key] = value  # EN: Keep the unique value for this key. TH: เก็บค่าที่ไม่ซ้ำของ key นี้
    return result  # EN: Return the verified JSON object. TH: คืน JSON object ที่ตรวจแล้ว


def _reject_nonfinite_json_constant(value: str) -> None:  # EN: Reject non-standard JSON numeric constants. TH: ปฏิเสธค่าตัวเลขที่ไม่เป็นมาตรฐาน JSON
    """Reject NaN and Infinity tokens outside the JSON standard. / ปฏิเสธ NaN และ Infinity ที่ไม่ใช่ JSON มาตรฐาน"""
    raise ValueError("Non-finite JSON number.")  # EN: Prevent non-standard numeric values entering validation or storage. TH: กันค่าตัวเลขนอกมาตรฐานเข้าสู่ validation หรือ storage


def _validated_supabase_base_url(raw_url: Optional[str]) -> Optional[str]:  # EN: Return a safe HTTPS origin or None. TH: คืน HTTPS origin ที่ปลอดภัยหรือ None
    """Accept only an HTTPS Supabase origin. / รับเฉพาะ origin Supabase แบบ HTTPS"""
    if not isinstance(raw_url, str) or not raw_url or len(raw_url) > 2_048:  # EN: Bound and type-check operator configuration. TH: จำกัดความยาวและตรวจชนิด config ของผู้ดูแล
        return None  # EN: Treat absent or oversized URLs as invalid configuration. TH: ถือ URL ที่หายหรือยาวเกินว่า config ไม่ถูกต้อง
    if any(ord(char) <= 0x20 or ord(char) == 0x7F for char in raw_url):  # EN: Reject whitespace and control characters before parsing. TH: ปฏิเสธช่องว่างและอักขระควบคุมก่อน parse
        return None  # EN: Prevent ambiguous URL normalization. TH: ป้องกันการ normalize URL ที่กำกวม
    try:  # EN: Parse the URL with a standard library parser. TH: parse URL ด้วย parser มาตรฐาน
        parsed = urlsplit(raw_url)  # EN: Separate scheme, authority, path, query, and fragment. TH: แยก scheme, authority, path, query และ fragment
        _ = parsed.port  # EN: Force validation of malformed port syntax. TH: บังคับตรวจรูปแบบ port ที่ผิด
    except ValueError:  # EN: Reject malformed authority or port components. TH: ปฏิเสธ authority หรือ port ที่ผิดรูป
        return None  # EN: Do not use unparseable destinations for credentials. TH: ห้ามส่ง credential ไปยังปลายทางที่ parse ไม่ได้
    if parsed.scheme.lower() != "https" or not parsed.hostname:  # EN: Require encrypted transport and a host. TH: บังคับ HTTPS และต้องมี host
        return None  # EN: Refuse plaintext or hostless destinations. TH: ปฏิเสธปลายทางที่ไม่เข้ารหัสหรือไม่มี host
    if parsed.username is not None or parsed.password is not None:  # EN: Disallow embedded user information. TH: ไม่อนุญาต user information ฝังใน URL
        return None  # EN: Prevent credential-bearing URL ambiguity. TH: ป้องกันความกำกวมจาก URL ที่ฝัง credential
    if parsed.path not in {"", "/"} or parsed.query or parsed.fragment:  # EN: Accept only a bare project origin. TH: รับเฉพาะ origin ของ project โดยไม่มี path ต่อ
        return None  # EN: Prevent unexpected routing or query data in the Auth base URL. TH: ป้องกัน routing หรือ query ที่ไม่คาดใน Auth base URL
    return f"https://{parsed.netloc}"  # EN: Return the validated HTTPS origin for Auth calls. TH: คืน HTTPS origin ที่ตรวจแล้วเพื่อเรียก Auth


def _bounded_env_int(name: str, default: int, minimum: int, maximum: int) -> int:  # EN: Parse one bounded integer environment setting. TH: แปลงค่าตั้ง environment จำนวนเต็มหนึ่งค่าตามช่วง
    """Read a bounded integer setting. / อ่านจำนวนเต็มตามช่วงที่กำหนด"""
    # EN: Read the optional setting. TH: อ่านค่าที่ตั้งผ่าน environment
    raw_value = os.getenv(name)  # EN: Read the optional value without printing it. TH: อ่านค่าตัวเลือกโดยไม่พิมพ์ค่าจริง
    if raw_value is None:  # EN: Use the safe default only when the setting is absent. TH: ใช้ค่าเริ่มต้นเมื่อไม่ได้ตั้งค่าเท่านั้น
        return default  # EN: Use default. TH: ใช้ค่าเริ่มต้น
    try:  # EN: Convert the supplied text to an integer. TH: แปลงข้อความค่าตั้งเป็นจำนวนเต็ม
        value = int(raw_value)  # EN: Parse integer. TH: แปลงเป็นจำนวนเต็ม
    except (TypeError, ValueError) as exc:  # EN: Catch values that cannot be represented as integers. TH: จับค่าที่แปลงเป็นจำนวนเต็มไม่ได้
        # EN: Name the invalid setting without echoing its value. TH: แจ้งชื่อค่าโดยไม่แสดงค่าจริง
        raise ValueError(  # EN: Stop startup with a safe configuration error. TH: หยุดเริ่มระบบพร้อมข้อผิดพลาด config ที่ปลอดภัย
            f"{name} must be an integer in {minimum}..{maximum}."  # EN: State the permitted range without echoing the supplied value. TH: แจ้งช่วงที่อนุญาตโดยไม่สะท้อนค่าที่ป้อน
        ) from exc  # EN: Retain the parse failure for local diagnostics. TH: เก็บสาเหตุการแปลงไว้ตรวจในเครื่อง
    if not minimum <= value <= maximum:  # EN: Refuse values outside the configured safe interval. TH: ปฏิเสธค่าที่อยู่นอกช่วงปลอดภัยที่กำหนด
        # EN: Reject out-of-range values. TH: ปฏิเสธค่านอกช่วง
        raise ValueError(f"{name} must be an integer in {minimum}..{maximum}.")  # EN: Stop startup with a setting-specific but value-safe message. TH: หยุดเริ่มระบบพร้อมแจ้งชื่อตัวแปรโดยไม่แสดงค่าจริง
    return value  # EN: Return validated value. TH: คืนค่าที่ผ่านการตรวจ


def _bounded_env_float(
    name: str, default: float, minimum: float, maximum: float  # EN: Define the bounded setting and fallback. TH: ระบุค่าตั้ง ช่วง และค่าเริ่มต้น
) -> float:  # EN: Return only a finite value inside the inclusive bounds. TH: คืนเฉพาะค่าจำกัดที่อยู่ในช่วงรวมขอบ
    """Read a finite bounded float. / อ่านทศนิยม finite ที่อยู่ในช่วงกำหนด"""
    # EN: Read the optional setting. TH: อ่านค่าจาก environment
    raw_value = os.getenv(name)  # EN: Read the setting without exposing it in diagnostics. TH: อ่านค่าตั้งโดยไม่แสดงค่าจริงในข้อความวินิจฉัย
    if raw_value is None:  # EN: Distinguish an unset variable from an invalid value. TH: แยกกรณีไม่ได้ตั้งค่าออกจากค่าที่ผิด
        return default  # EN: Use default. TH: ใช้ค่าเริ่มต้น
    try:  # EN: Convert the configured text to a floating-point value. TH: แปลงข้อความค่าตั้งเป็นเลขทศนิยม
        value = float(raw_value)  # EN: Parse float. TH: แปลงเป็นทศนิยม
    except (TypeError, ValueError) as exc:  # EN: Normalize failed numeric parsing. TH: จัดการกรณีแปลงเป็นตัวเลขไม่สำเร็จ
        # EN: Do not echo configuration contents. TH: ไม่แสดงเนื้อหาของค่าตั้งต้นที่ผิด
        raise ValueError(  # EN: Fail at startup without revealing the supplied value. TH: หยุดเริ่มระบบโดยไม่เปิดเผยค่าที่ป้อน
            f"{name} must be a finite number in {minimum}..{maximum}."  # EN: Name the allowed setting range. TH: ระบุช่วงค่าที่อนุญาต
        ) from exc  # EN: Preserve the parsing cause for local diagnostics. TH: เก็บสาเหตุเดิมไว้สำหรับวินิจฉัยในเครื่อง
    if not math.isfinite(value) or not minimum <= value <= maximum:  # EN: Reject NaN, infinities, and values outside the allowed range. TH: ปฏิเสธ NaN, infinity และค่าที่อยู่นอกช่วงอนุญาต
        # EN: Reject NaN, infinity, and out-of-range values. TH: ปฏิเสธ NaN, infinity และค่านอกช่วง
        raise ValueError(f"{name} must be a finite number in {minimum}..{maximum}.")  # EN: Reject non-finite and out-of-range configuration. TH: ปฏิเสธค่าตั้งที่ไม่ finite หรืออยู่นอกช่วง
    return value  # EN: Return validated value. TH: คืนค่าที่ผ่านการตรวจ


class RequestBodyLimitMiddleware:  # EN: Enforce per-route request byte limits before JSON parsing. TH: บังคับเพดาน byte ต่อ route ก่อน parse JSON
    # EN: Buffer only small allowlisted POST bodies before JSON parsing. TH: buffer เฉพาะ POST ที่กำหนดและจำกัดขนาดก่อน parse JSON
    def __init__(self, inner_app):  # EN: Store the wrapped ASGI application. TH: เก็บ ASGI application ที่ middleware ครอบไว้
        self.inner_app = inner_app  # EN: Retain the application for accepted requests. TH: เก็บแอปไว้เรียกเมื่อ request ผ่าน

    async def __call__(self, scope, receive, send):  # EN: Intercept one ASGI request. TH: ดักตรวจ ASGI request หนึ่งรายการ
        if scope.get("type") != "http":  # EN: Leave websocket and lifespan scopes untouched. TH: ไม่ยุ่งกับ websocket และ lifespan
            await self.inner_app(scope, receive, send)  # EN: Forward non-HTTP scopes unchanged. TH: ส่ง scope ที่ไม่ใช่ HTTP ต่อโดยไม่แก้
            return  # EN: Finish this non-HTTP request path. TH: จบเส้นทางที่ไม่ใช่ HTTP

        request_id = uuid4().hex  # EN: Create an opaque ID without using client input. TH: สร้าง ID แบบสุ่มโดยไม่เชื่อข้อมูลจาก client
        original_send = send  # EN: Preserve the server-provided ASGI sender before wrapping it. TH: เก็บ sender จาก ASGI server ไว้ก่อนครอบการส่ง
        async def send_with_request_id(message):  # EN: Add correlation metadata to each HTTP response. TH: เพิ่ม metadata สำหรับเชื่อมโยง request ใน response HTTP
            if message.get("type") == "http.response.start":  # EN: Inspect only the response header event. TH: ตรวจเฉพาะ event เริ่ม response และ header
                status = int(message.get("status", 500))  # EN: Capture the status code for safe diagnostics. TH: อ่าน status code เพื่อใช้วินิจฉัยแบบปลอดภัย
                headers = [  # EN: Preserve normal response headers except any supplied request ID. TH: คง header ปกติและตัด request ID ที่อาจถูกกำหนดมาก่อน
                    (name, value)  # EN: Keep each unrelated response header unchanged. TH: คง header อื่นโดยไม่แก้
                    for name, value in message.get("headers", [])  # EN: Read the ASGI response headers. TH: อ่าน response header จาก ASGI
                    if name.lower() != b"x-request-id"  # EN: Prevent an inner layer from spoofing the correlation ID. TH: ป้องกันชั้นในปลอม correlation ID
                ]  # EN: Finish filtering existing request-ID headers. TH: จบการกรอง header request ID เดิม
                headers.append((b"x-request-id", request_id.encode("ascii")))  # EN: Return the server-generated ID to the caller. TH: ส่ง ID ที่ server สร้างกลับไปให้ caller
                message = {**message, "headers": headers}  # EN: Build the response-start message with the safe ID. TH: สร้าง response-start message พร้อม ID ที่ปลอดภัย
                path_bytes = scope.get("raw_path")  # EN: Prefer ASGI's original path bytes to avoid invalid-Unicode edge cases. TH: ใช้ path bytes ดั้งเดิมจาก ASGI เพื่อเลี่ยง Unicode ที่ผิดรูป
                if not isinstance(path_bytes, bytes):  # EN: Normalize non-byte fallback paths safely. TH: แปลง path สำรองที่ไม่ใช่ bytes อย่างปลอดภัย
                    path_bytes = str(scope.get("path", "")).encode("utf-8", "backslashreplace")  # EN: Escape malformed Unicode while converting the fallback path. TH: escape Unicode ที่ผิดรูปขณะแปลง path สำรอง
                safe_path = quote(path_bytes, safe=b"/")[:512]  # EN: Percent-encode controls and cap the path to prevent log injection. TH: เข้ารหัสอักขระควบคุมและจำกัด path เพื่อป้องกันการปลอมบรรทัด log
                method = re.sub(r"[^A-Z0-9_-]", "?", str(scope.get("method", "")).upper())[:16]  # EN: Restrict request-method log values to a short printable allowlist. TH: จำกัดค่า method ใน log ให้สั้นและอยู่ในชุดอักขระที่ปลอดภัย
                LOGGER.info("request_id=%s method=%s path=%s status=%s", request_id, method, safe_path, status)  # EN: Log sanitized metadata only; never log tokens, bodies, or health values. TH: log เฉพาะ metadata ที่ sanitize แล้ว ไม่บันทึก token, body หรือค่าสุขภาพ
            await original_send(message)  # EN: Forward the original or annotated ASGI message. TH: ส่ง ASGI message เดิมหรือที่เพิ่ม ID แล้วต่อไป

        send = send_with_request_id  # EN: Ensure early middleware errors and route responses share one ID. TH: ให้ error จาก middleware และ response จาก route ใช้ ID เดียวกัน

        body_limits = {  # EN: Set per-route byte caps before any body is read. TH: กำหนดเพดาน byte ต่อ route ก่อนอ่าน body
            "/sensor": MAX_CLOUD_EVENT_BYTES,  # EN: Cap sensor event uploads. TH: จำกัด upload sensor event
            "/alert": MAX_CLOUD_EVENT_BYTES,  # EN: Cap alert uploads. TH: จำกัด upload alert
            "/chat": MAX_AI_REQUEST_BYTES,  # EN: Cap chat prompts. TH: จำกัด prompt ของ chat
            "/advice": MAX_AI_REQUEST_BYTES,  # EN: Cap advice requests. TH: จำกัด request ขอคำแนะนำ
        }  # EN: Finish the route-to-limit map. TH: จบตาราง route กับเพดาน
        path = scope.get("path", "")  # EN: Read the normalized request path. TH: อ่าน path ของ request
        method = scope.get("method", "").upper()  # EN: Normalize the HTTP method. TH: ปรับ method เป็นตัวพิมพ์ใหญ่
        body_limit = body_limits.get(path) if method == "POST" else None  # EN: Apply limits only to listed POST routes. TH: ใช้เพดานเฉพาะ POST ใน route ที่ระบุ
        if body_limit is None:  # EN: Skip unrelated routes without consuming their bodies. TH: ข้าม route อื่นโดยไม่อ่าน body
            await self.inner_app(scope, receive, send)  # EN: Forward the request unchanged. TH: ส่ง request ต่อโดยไม่แก้
            return  # EN: Finish the unbounded route path. TH: จบเส้นทาง route อื่น

        length_headers = [value for name, value in scope.get("headers", []) if name.lower() == b"content-length"]  # EN: Preserve duplicate headers so conflicting lengths cannot be hidden. TH: เก็บ header ซ้ำไว้เพื่อตรวจไม่ให้ซ่อนขนาดที่ขัดแย้ง
        declared_length: Optional[int] = None  # EN: Treat Content-Length as an optional early size hint. TH: ใช้ Content-Length เป็นตัวช่วยตรวจขนาดล่วงหน้าแบบไม่บังคับ
        if length_headers:  # EN: Validate the length only when the client supplied it. TH: ตรวจ header ขนาดเมื่อ client ส่งมาเท่านั้น
            if len(length_headers) != 1:  # EN: Reject duplicate Content-Length headers as ambiguous. TH: ปฏิเสธ Content-Length ซ้ำเพราะขนาดกำกวม
                await self._respond(send, 400, "Multiple Content-Length headers are not allowed.")  # EN: Return a safe malformed-request response. TH: ส่ง response ปลอดภัยสำหรับ request ที่ผิดรูป
                return  # EN: Stop before choosing one of the conflicting values. TH: หยุดก่อนเลือกค่าหนึ่งจากค่าที่ขัดแย้ง
            raw_length = length_headers[0]  # EN: Read the single declared body length. TH: อ่านค่าขนาด body ที่ประกาศเพียงค่าเดียว
            if not raw_length.isdigit():  # EN: Accept only ASCII decimal digits in Content-Length. TH: รับ Content-Length เฉพาะเลขฐานสิบ ASCII
                await self._respond(send, 400, "Invalid Content-Length.")  # EN: Reject malformed length headers. TH: ปฏิเสธ header ขนาดที่ผิดรูป
                return  # EN: Stop before attempting integer conversion. TH: หยุดก่อนแปลงเป็นจำนวนเต็ม
            try:  # EN: Guard integer parsing against excessively long digit strings. TH: ครอบการแปลงเลขเพื่อป้องกันข้อความตัวเลขยาวเกิน
                declared_length = int(raw_length)  # EN: Convert the declared decimal byte count. TH: แปลงจำนวน byte ที่ประกาศเป็นจำนวนเต็ม
            except ValueError:  # EN: Python may reject values beyond its safe integer-string conversion limit. TH: Python อาจปฏิเสธข้อความตัวเลขที่ยาวเกินขีดจำกัดการแปลง
                await self._respond(send, 400, "Invalid Content-Length.")  # EN: Reject the malformed header with a client error. TH: ปฏิเสธ header ผิดรูปด้วย client error
                return  # EN: Stop before reading or buffering the request body. TH: หยุดก่อนอ่านหรือ buffer request body
            if declared_length > body_limit:  # EN: Reject oversized requests before buffering. TH: ปฏิเสธ request ใหญ่เกินก่อน buffer
                await self._respond(send, 413, "Request body exceeds the endpoint size limit.")  # EN: Return the request-size error. TH: ส่งข้อผิดพลาดเรื่องขนาด request
                return  # EN: Do not pass this request to application routes. TH: ไม่ส่ง request นี้เข้า route ของแอป

        chunks: list[bytes] = []  # EN: Store only chunks within the configured byte cap. TH: เก็บเฉพาะ chunk ที่ยังอยู่ในเพดาน byte
        actual_length = 0  # EN: Track bytes received independently of the client header. TH: นับ byte ที่รับจริงแยกจาก header ของ client
        while True:  # EN: Read the complete bounded body before parsing. TH: อ่าน body ที่จำกัดให้ครบก่อน parse
            message = await receive()  # EN: Receive the next ASGI body or disconnect event. TH: รับ body ASGI ถัดไปหรือเหตุการณ์ตัดการเชื่อมต่อ
            if message.get("type") == "http.disconnect":  # EN: Stop if the sender disconnected mid-request. TH: หยุดถ้าผู้ส่งตัดการเชื่อมต่อกลางทาง
                return  # EN: Do not process an incomplete body. TH: ไม่ประมวลผล body ที่มาไม่ครบ
            chunk = message.get("body", b"")  # EN: Read the current body fragment. TH: อ่าน fragment ของ body ปัจจุบัน
            actual_length += len(chunk)  # EN: Count actual bytes even when Content-Length is inaccurate. TH: นับ byte จริงแม้ Content-Length จะระบุคลาดเคลื่อน
            if actual_length > body_limit:  # EN: Enforce the cap against bytes actually received. TH: บังคับเพดานกับจำนวน byte ที่รับจริง
                await self._respond(send, 413, "Request body exceeds the endpoint size limit.")  # EN: Reject a body that exceeds the cap. TH: ปฏิเสธ body ที่เกินเพดาน
                return  # EN: Never forward an oversized payload for parsing. TH: ห้ามส่ง payload ใหญ่เกินไปให้ parser
            chunks.append(chunk)  # EN: Keep the fragment after its size has been checked. TH: เก็บ fragment หลังตรวจขนาดแล้ว
            if not message.get("more_body", False):  # EN: Detect the final body fragment. TH: ตรวจว่าเป็น fragment สุดท้ายหรือไม่
                break  # EN: Finish reading once the body is complete. TH: จบการอ่านเมื่อ body ครบ

        if declared_length is not None and actual_length != declared_length:  # EN: Check declared and received bytes when a length header exists. TH: เทียบ byte ที่ประกาศกับที่รับจริงเมื่อมี header ขนาด
            await self._respond(send, 400, "Content-Length does not match the received body.")  # EN: Return a clear malformed-request error. TH: แจ้งข้อผิดพลาด request ที่ขนาดไม่ตรง
            return  # EN: Prevent parsing a body with an inconsistent length. TH: ป้องกันการ parse body ที่ขนาดไม่สอดคล้อง

        body = b"".join(chunks)  # EN: Reassemble the already-bounded body for the application. TH: รวม body ที่ผ่านการจำกัดขนาดแล้วให้แอปใช้
        if body:  # EN: Preserve framework handling for an intentionally empty body. TH: คงการจัดการ body ว่างของ framework
            try:  # EN: Validate JSON syntax and unambiguous values before FastAPI parses the body. TH: ตรวจ syntax JSON และความกำกวมก่อน FastAPI parse body
                json.loads(  # EN: Parse once with strict duplicate-key and numeric-token rules. TH: parse หนึ่งครั้งด้วยกฎเข้มสำหรับ key ซ้ำและ token ตัวเลข
                    body,  # EN: Use the bounded bytes already read from the request. TH: ใช้ byte ที่อ่านและจำกัดขนาดไว้แล้ว
                    object_pairs_hook=_reject_duplicate_json_keys,  # EN: Reject duplicate keys at every object depth. TH: ปฏิเสธ key ซ้ำในทุกระดับของ object
                    parse_constant=_reject_nonfinite_json_constant,  # EN: Reject NaN and positive/negative Infinity. TH: ปฏิเสธ NaN และ Infinity ทั้งบวก/ลบ
                )  # EN: Finish strict JSON parsing. TH: จบการ parse JSON แบบเข้ม
            except (ValueError, UnicodeDecodeError, RecursionError):  # EN: Normalize malformed, ambiguous, invalid-encoding, or excessively nested JSON as a client error. TH: แปลง JSON ผิดรูป กำกวม encoding ผิด หรือซ้อนลึกเกินเป็น client error
                await self._respond(send, 400, "Malformed or ambiguous JSON body.")  # EN: Return a safe error without exposing the submitted body. TH: ตอบ error ปลอดภัยโดยไม่เปิดเผย body ที่ส่งมา
                return  # EN: Stop before route validation or any persistence side effect. TH: หยุดก่อน route validation หรือ side effect การบันทึก
        delivered = False  # EN: Track whether the body has been replayed to the app. TH: ติดตามว่า replay body ให้แอปแล้วหรือยัง

        async def replay_body():  # EN: Provide the buffered body through the ASGI receive interface. TH: ส่ง body ที่ buffer แล้วผ่าน ASGI receive interface
            nonlocal delivered  # EN: Share the one-time delivery flag with this closure. TH: ใช้ตัวแปรสถานะส่งข้อมูลครั้งเดียวร่วมกับ closure
            if not delivered:  # EN: Deliver the request body exactly once. TH: ส่ง body ของ request เพียงครั้งเดียว
                delivered = True  # EN: Mark the body as consumed before returning it. TH: ทำเครื่องหมายว่าอ่าน body แล้วก่อนคืนค่า
                return {"type": "http.request", "body": body, "more_body": False}  # EN: Replay one complete ASGI body message. TH: replay body ครบใน ASGI message เดียว
            return {"type": "http.disconnect"}  # EN: Report no further body data after the one-shot replay. TH: แจ้งว่าไม่มี body เพิ่มหลัง replay ครั้งเดียว

        await self.inner_app(scope, replay_body, send)  # EN: Parse and handle only the verified bounded body. TH: parse และจัดการเฉพาะ body ที่ตรวจเพดานแล้ว

    @staticmethod  # EN: Keep response construction independent of middleware state. TH: ทำตัวสร้าง response ให้ไม่ขึ้นกับ state ของ middleware
    async def _respond(send, status: int, detail: str) -> None:  # EN: Send a small JSON error without invoking route parsing. TH: ส่ง JSON error ขนาดเล็กโดยไม่เรียก route parser
        body = json.dumps({"detail": detail}).encode("utf-8")  # EN: Encode the fixed error payload as UTF-8 JSON. TH: เข้ารหัส error payload ที่กำหนดเป็น JSON UTF-8
        headers = [  # EN: Define response headers for a complete JSON response. TH: กำหนด header สำหรับ JSON response ที่ครบถ้วน
            (b"content-type", b"application/json"),  # EN: Declare the response media type. TH: ระบุชนิดข้อมูล response
            (b"content-length", str(len(body)).encode("ascii")),  # EN: Declare the exact response byte count. TH: ระบุจำนวน byte ของ response ให้ตรง
            (b"connection", b"close"),  # EN: Close early-rejected connections with unread request bytes. TH: ปิด connection ที่ปฏิเสธก่อนอ่าน body ที่เหลือ
        ]  # EN: Finish the response headers. TH: จบรายการ header
        await send({"type": "http.response.start", "status": status, "headers": headers})  # EN: Start the error response with its HTTP status. TH: เริ่ม error response พร้อม HTTP status
        await send({"type": "http.response.body", "body": body})  # EN: Send the complete JSON error body. TH: ส่ง JSON error body ให้ครบ


app.add_middleware(RequestBodyLimitMiddleware)  # EN: Install byte-level limits before route body parsing. TH: ติดตั้งการจำกัด byte ก่อน route parse body


def _append_bounded_event(events: list[dict[str, Any]], event: dict[str, Any]) -> None:  # EN: Append one event while keeping the list under its memory cap. TH: เพิ่ม event หนึ่งรายการโดยคงจำนวนใน RAM ไม่เกินเพดาน
    """Keep only the newest bounded in-process event history. / เก็บ event ล่าสุดใน RAM ตามเพดาน"""
    if len(events) >= MAX_IN_MEMORY_EVENTS:  # EN: Make room before the append would exceed the cap. TH: เตรียมพื้นที่ก่อนเพิ่มแล้วเกินเพดาน
        del events[: len(events) - MAX_IN_MEMORY_EVENTS + 1]  # EN: Drop only the oldest excess records. TH: ลบเฉพาะ record เก่าสุดที่เกินจำนวน
    events.append(event)  # EN: Add the newest record after enforcing the bound. TH: เพิ่ม record ล่าสุดหลังบังคับขอบเขต

# Per-process abuse guard; configure a shared gateway limiter before adding replicas.
# EN/TH: Cap per-user AI requests; invalid configuration stops startup / จำกัดคำขอ AI ต่อผู้ใช้; config ผิดให้หยุดตอนเริ่มระบบ
AI_RATE_LIMIT_MAX = _bounded_env_int("AI_RATE_LIMIT_MAX", 20, 1, 1_000)
AI_RATE_LIMIT_WINDOW_SECONDS = _bounded_env_int(
    "AI_RATE_LIMIT_WINDOW_SECONDS", 60, 1, 86_400
)
# EN/TH: Bound simultaneous provider calls per worker / จำกัดงานเรียก provider พร้อมกันต่อ worker
AI_MAX_CONCURRENT_REQUESTS = _bounded_env_int(
    "AI_MAX_CONCURRENT_REQUESTS", 2, 1, 64
)
_AI_REQUEST_TIMES: OrderedDict[str, deque[float]] = OrderedDict()
_AI_RATE_LIMIT_LOCK = Lock()
_AI_IN_FLIGHT = BoundedSemaphore(AI_MAX_CONCURRENT_REQUESTS)

SENSOR_EVENTS: list[dict[str, Any]] = []
ALERT_EVENTS: list[dict[str, Any]] = []
FIRESTORE_COLLECTION_PREFIX = os.getenv("FIRESTORE_COLLECTION_PREFIX", "vita_guard")
USE_FIRESTORE = os.getenv("USE_FIRESTORE", "").lower() in {"1", "true", "yes"}
_FIRESTORE_CLIENT = firestore.Client() if USE_FIRESTORE and firestore else None


class CloudPayload(BaseModel):  # EN: Model a bounded cloud event while preserving supported extra fields. TH: แทน cloud event ที่จำกัดขนาดและคง field เพิ่มเติมที่รองรับ
    # EN: Keep forward-compatible event fields while using Pydantic v2 config.
    # TH: ยอมรับฟิลด์ event เพิ่มเติมเพื่อรองรับรุ่นใหม่ และใช้ config ของ Pydantic v2
    model_config = ConfigDict(extra="allow")  # EN: Accept forward-compatible event fields. TH: ยอมรับฟิลด์ event เพิ่มเติมเพื่อรองรับรุ่นใหม่


class ChatRequest(BaseModel):  # EN: Define validated chat text fields before provider use. TH: กำหนด field แชตที่ผ่าน validation ก่อนส่ง provider
    # EN: Ignore client-only fields; the server controls provider/model selection. TH: ไม่รับ field เฉพาะ client; server เป็นผู้เลือก provider/model
    # EN: Bound user-controlled content before it can trigger provider billing. TH: จำกัดข้อความผู้ใช้ก่อนเรียก provider ซึ่งมีค่าใช้จ่าย
    model_config = ConfigDict(extra="ignore")  # EN: Ignore unrecognized fields such as a client-selected model. TH: ไม่รับ field ที่ไม่รู้จัก เช่น model ที่ client เลือก

    question: str = Field(min_length=1, max_length=2000)  # EN: Require a nonempty question no longer than 2,000 characters. TH: บังคับคำถามไม่ว่างและยาวไม่เกิน 2,000 ตัวอักษร
    prompt: str = Field(min_length=1, max_length=10000)  # EN: Bound the composed prompt to 10,000 characters. TH: จำกัด prompt ที่ประกอบแล้วไม่เกิน 10,000 ตัวอักษร


class AdviceRequest(BaseModel):  # EN: Define the bounded request schema for safety advice. TH: กำหนด schema request คำแนะนำที่จำกัดขนาด
    # EN: Bound advice input and prevent client-side provider/model selection. TH: จำกัด input คำแนะนำและไม่ให้ client เลือก provider/model
    model_config = ConfigDict(extra="ignore", populate_by_name=True)  # EN: Ignore unknown fields and accept the declared aliases. TH: ไม่รับ field แปลกปลอมและรองรับชื่อ alias ที่กำหนด

    status: str = Field(min_length=1, max_length=80)  # EN: Require a bounded nonempty status string. TH: บังคับ status ไม่ว่างและจำกัดความยาว
    alert_level: str = Field(default="", alias="alertLevel", max_length=40)  # EN: Accept the API's alertLevel alias within a short limit. TH: รองรับชื่อ alertLevel และจำกัดความยาว
    sensor: str = Field(default="", max_length=2000)  # EN: Bound the optional sensor description. TH: จำกัดความยาวคำอธิบาย sensor ที่ไม่บังคับ


def _verify_chat_user(authorization: Optional[str]) -> str:  # EN: Verify a Bearer token and return its authenticated user ID. TH: ตรวจ Bearer token และคืน user ID ที่ยืนยันแล้ว
    """Validate Supabase identity before protected requests. / ยืนยันตัวตน Supabase ก่อนคำขอที่มีการป้องกัน"""
    supabase_url = _validated_supabase_base_url(os.getenv("SUPABASE_URL"))  # EN: Validate the Auth origin before sending any credential. TH: ตรวจ Auth origin ก่อนส่ง credential ใด ๆ
    supabase_key = os.getenv("SUPABASE_PUBLISHABLE_KEY") or os.getenv(  # EN: Prefer the public publishable key and keep legacy anon-key support. TH: ใช้ publishable key ก่อนและรองรับ anon key เดิม
        "SUPABASE_ANON_KEY", ""  # EN: Default to missing configuration without exposing a secret. TH: ใช้ค่าว่างเมื่อไม่มี config โดยไม่เปิดเผย secret
    )  # EN: Finish reading the supported public key setting. TH: จบการอ่านค่าคีย์สาธารณะที่รองรับ
    if not supabase_url or not supabase_key:  # EN: Require both endpoint and public project key before Auth lookup. TH: ต้องมีทั้ง endpoint และ public project key ก่อนตรวจ Auth
        # EN: Fail closed when the server cannot verify identity. TH: ปิดการเข้าถึงเมื่อ server ยืนยันตัวตนไม่ได้
        raise HTTPException(  # EN: Fail closed instead of accepting an unverifiable identity. TH: ปิดการเข้าถึงเมื่อยืนยันตัวตนไม่ได้
            status_code=503,  # EN: Report missing server configuration as unavailable. TH: แจ้งว่า service ใช้งานไม่ได้เพราะ config ไม่ครบ
            detail="Chat authentication is not configured on this server.",  # EN: Give a safe operator-facing reason. TH: แจ้งสาเหตุที่ปลอดภัยสำหรับผู้ดูแล
        )  # EN: Stop before making any protected request. TH: หยุดก่อนเรียก protected route
    scheme, _, raw_token = (authorization or "").partition(" ")  # EN: Split the authorization scheme from the credential. TH: แยกชนิด authorization ออกจาก credential
    token = raw_token.strip()  # EN: Remove only outer whitespace before validation. TH: ตัดช่องว่างรอบนอกก่อนตรวจ
    if scheme.lower() != "bearer" or not token:  # EN: Require a nonempty Bearer credential. TH: บังคับใช้ Bearer credential ที่ไม่ว่าง
        raise HTTPException(status_code=401, detail="Bearer access token required.")  # EN: Reject missing or wrong-scheme credentials. TH: ปฏิเสธ credential ที่หายไปหรือใช้ scheme ผิด
    if len(token) > MAX_BEARER_TOKEN_CHARS or any(  # EN: Bound the outgoing header value and require safe ASCII. TH: จำกัด header ที่จะส่งและบังคับ ASCII ที่ปลอดภัย
        ord(char) <= 0x20 or ord(char) >= 0x7F for char in token  # EN: Reject controls, whitespace, and non-ASCII characters. TH: ปฏิเสธ control, ช่องว่าง และอักขระนอก ASCII
    ):  # EN: Finish the credential-format predicate. TH: จบเงื่อนไขตรวจรูปแบบ credential
        raise HTTPException(status_code=401, detail="Invalid bearer access token.")  # EN: Reject before constructing an outbound request. TH: ปฏิเสธก่อนสร้างคำขอออกไปภายนอก
    try:  # EN: Bound external identity lookup failures to controlled API responses. TH: ครอบความผิดพลาดจากการตรวจ identity ภายนอกให้เป็น API response ที่ควบคุมได้
        response = httpx.get(  # EN: Request the authenticated user's identity from Supabase. TH: ขอ identity ของผู้ใช้ที่ยืนยันกับ Supabase
            f"{supabase_url}/auth/v1/user",  # EN: Ask Supabase Auth to validate this bearer token. TH: ให้ Supabase Auth ตรวจ bearer token นี้
            headers={  # EN: Send only the required public key and user credential. TH: ส่งเฉพาะ public key และ credential ของผู้ใช้ที่จำเป็น
                "apikey": supabase_key,  # EN: Identify the public Supabase project. TH: ระบุ Supabase project ด้วย public key
                "Authorization": f"Bearer {token}",  # EN: Forward the validated token only to the configured Auth host. TH: ส่ง token ที่ตรวจแล้วไปยัง Auth host ที่ตั้งไว้เท่านั้น
            },  # EN: Finish the outbound authentication headers. TH: จบชุด header สำหรับตรวจยืนยัน
            timeout=5.0,  # EN: Bound the external identity check. TH: จำกัดเวลารอการตรวจ identity ภายนอก
        )  # EN: Complete the bounded request to the configured Auth endpoint. TH: จบคำขอที่มี timeout ไปยัง Auth endpoint ที่ตั้งไว้
    except httpx.HTTPError as exc:  # EN: Catch transport and timeout failures from the Auth provider. TH: จับ transport และ timeout จาก Auth provider
        # EN: Do not turn provider/network failures into unauthenticated access. TH: ห้ามเปลี่ยน provider/network failure ให้เป็นการเข้าถึงแบบไม่ยืนยัน
        raise HTTPException(  # EN: Keep provider outages distinct from invalid user credentials. TH: แยก provider ล่มออกจาก credential ผู้ใช้ผิด
            status_code=503, detail="Authentication provider is unavailable."  # EN: Return no internal network details. TH: ไม่เปิดเผยรายละเอียด network ภายใน
        ) from exc  # EN: Retain the cause for server-side logs. TH: เก็บสาเหตุไว้ใน log ฝั่ง server
    if response.status_code in (401, 403):  # EN: Treat explicit Auth rejection as invalid credentials. TH: ถือการปฏิเสธจาก Auth ว่า credential ไม่ถูกต้อง
        # EN: Map invalid/expired credentials to an authentication error. TH: แปลง credential ผิดหรือหมดอายุเป็น authentication error
        raise HTTPException(status_code=401, detail="Invalid or expired token.")  # EN: Reject credentials explicitly denied by Supabase. TH: ปฏิเสธ credential ที่ Supabase ระบุว่าผิดหรือหมดอายุ
    if response.status_code < 200 or response.status_code >= 300:  # EN: Reject provider failures other than invalid-token responses. TH: ปฏิเสธ provider failure ที่ไม่ใช่กรณี token ผิด
        # EN: Treat all other non-success provider responses as unavailable verification. TH: ถือ response ที่ไม่สำเร็จอื่นว่า verification ใช้งานไม่ได้
        raise HTTPException(status_code=503, detail="Could not verify access token.")  # EN: Fail closed when Auth returned an unexpected error. TH: ปิดการเข้าถึงเมื่อ Auth ตอบข้อผิดพลาดที่ไม่คาดไว้
    try:  # EN: Parse only the Auth provider's verified identity response. TH: parse เฉพาะ response identity ที่ Auth ยืนยัน
        user_id = response.json().get("id")  # EN: Read identity only from the Auth provider response. TH: อ่าน identity จาก response ของ Auth provider เท่านั้น
    except (ValueError, AttributeError):  # EN: Handle malformed JSON or a non-object response shape. TH: จัดการ JSON ผิดรูปหรือ response ที่ไม่ใช่ object
        user_id = None  # EN: Treat malformed JSON or an unexpected shape as invalid identity. TH: ถือ JSON ผิดรูปหรือโครงสร้างไม่ตรงว่า identity ไม่ถูกต้อง
    if not isinstance(user_id, str) or not user_id or len(user_id) > MAX_AUTH_USER_ID_CHARS:  # EN: Require a nonempty account ID within the bounded state-key length. TH: ต้องมีรหัสบัญชีที่ไม่ว่างและไม่เกินความยาว key ที่กำหนด
        # EN: Refuse missing or oversized identities before storing or using them. TH: ปฏิเสธ identity ที่หายหรือยาวเกินก่อนเก็บหรือนำไปใช้
        raise HTTPException(status_code=401, detail="Invalid user identity.")  # EN: Reject malformed identity responses as unauthorized. TH: ปฏิเสธ response identity ที่ผิดรูปเป็น unauthorized
    return user_id  # EN: Return only the server-verified account identifier. TH: คืนเฉพาะรหัสบัญชีที่ server ยืนยันแล้ว


def _memory_health_storage_enabled() -> bool:
    """EN: Enable ephemeral storage only by explicit operator choice. TH: เปิด storage ชั่วคราวเมื่อผู้ดูแลระบุอนุญาตเท่านั้น"""
    value = os.getenv("HEALTH_DATA_MEMORY_STORAGE_ENABLED", "false")  # EN: Read an opt-in that defaults to disabled. TH: อ่านค่าที่ปิดเป็นค่าเริ่มต้น
    return value.strip().lower() in {"1", "true", "yes"}  # EN: Accept only explicit truthy strings. TH: ยอมรับเฉพาะข้อความที่ระบุว่าเปิด


def _require_health_data_sync_enabled() -> None:  # EN: Keep health-data routes closed until storage is explicitly enabled. TH: ปิด route ข้อมูลสุขภาพจนกว่าจะเปิด storage อย่างชัดเจน
    """EN: Fail closed until deployment review enables sync. TH: ปิดระบบจนกว่าผู้ดูแล deployment จะเปิด sync"""
    enabled = os.getenv("HEALTH_DATA_SYNC_ENABLED", "false").strip().lower()  # EN: Read an explicit deployment opt-in; default to disabled. TH: อ่านการเปิดใช้จาก deployment โดยปริยายปิด
    if enabled not in {"1", "true", "yes"}:  # EN: Accept only explicit truthy configuration values. TH: ยอมรับเฉพาะค่าที่ระบุว่าเปิดชัดเจน
        raise HTTPException(  # EN: Keep health sync disabled until operator review. TH: ปิด health sync จนกว่าผู้ดูแลตรวจและเปิด
            status_code=503,  # EN: Report the unavailable feature without pretending to store data. TH: แจ้งว่า feature ยังใช้ไม่ได้โดยไม่แสร้งว่าบันทึกข้อมูลแล้ว
            detail="Health-data sync is disabled on this deployment.",  # EN: Explain the required deployment setting. TH: แจ้งค่าตั้ง deployment ที่ต้องเปิด
        )  # EN: Stop before storage operations. TH: หยุดก่อนเข้าถึง storage
    # EN: Do not claim sync succeeded when only process memory is available.
    # TH: ห้ามแจ้งว่าสำเร็จเมื่อมีเพียงหน่วยความจำชั่วคราว เว้นแต่เปิด opt-in สำหรับพัฒนา
    if not _FIRESTORE_CLIENT and not _memory_health_storage_enabled():  # EN: Require durable storage unless a developer explicitly opted into memory mode. TH: ต้องมี storage ถาวร เว้นแต่นักพัฒนาเปิดโหมด memory อย่างชัดเจน
        raise HTTPException(  # EN: Fail closed when only non-durable storage exists. TH: ปิดการเขียนเมื่อมีแต่ storage ที่ไม่ถาวร
            status_code=503,  # EN: Report storage readiness failure. TH: แจ้งว่า storage ยังไม่พร้อม
            detail="Persistent health-data storage is unavailable.",  # EN: Avoid claiming durable sync. TH: ไม่กล่าวอ้างว่า sync แบบถาวรสำเร็จ
        )  # EN: Do not continue into event persistence. TH: ไม่ทำงานต่อไปยังการบันทึก event


def _enforce_ai_rate_limit(user_id: str, *, now: Optional[float] = None) -> None:
    """Limit verified accounts per worker. / จำกัดคำขอต่อบัญชีใน worker นี้"""
    current = time.monotonic() if now is None else now  # EN: Use monotonic time for elapsed intervals. TH: ใช้เวลา monotonic วัดช่วงเวลาที่ผ่านไป
    cutoff = current - AI_RATE_LIMIT_WINDOW_SECONDS  # EN: Compute the oldest timestamp still inside the rolling window. TH: คำนวณเส้นแบ่ง timestamp ที่ยังอยู่ในช่วงจำกัด
    with _AI_RATE_LIMIT_LOCK:  # EN: Keep updates to shared worker state atomic. TH: ทำให้การแก้ shared state ใน worker เป็น atomic
        # Expire this account's timestamps before checking the current window.
        requests = _AI_REQUEST_TIMES.get(user_id)  # EN: Find this verified account's recent request times. TH: หาเวลาคำขอล่าสุดของบัญชีที่ยืนยันแล้ว
        if requests is None:  # EN: Initialize tracking for a new account. TH: เริ่มติดตามบัญชีใหม่
            # Reclaim expired identities and cap memory used by authenticated IDs.
            if len(_AI_REQUEST_TIMES) >= 10_000:  # EN: Reclaim expired IDs before consuming more memory. TH: คืนพื้นที่ ID ที่หมดอายุก่อนใช้หน่วยความจำเพิ่ม
                for old_user_id, old_requests in list(_AI_REQUEST_TIMES.items()):  # EN: Scan a bounded snapshot for inactive identities. TH: ตรวจ snapshot ที่มีขนาดจำกัดเพื่อหา identity ที่หมดอายุ
                    if not old_requests or old_requests[-1] <= cutoff:  # EN: Select entries with no active requests in the window. TH: เลือกรายการที่ไม่มีคำขอในช่วงเวลาปัจจุบัน
                        _AI_REQUEST_TIMES.pop(old_user_id, None)  # EN: Reclaim the inactive identity's memory. TH: คืนหน่วยความจำของ identity ที่ไม่ได้ใช้งาน
                        if len(_AI_REQUEST_TIMES) < 10_000:  # EN: Stop cleanup once capacity is available. TH: หยุด cleanup เมื่อมีพื้นที่เหลือ
                            break  # EN: Avoid scanning more entries than necessary. TH: ไม่สแกนต่อเมื่อไม่จำเป็น
            if len(_AI_REQUEST_TIMES) >= 10_000:  # EN: Refuse new identity state rather than grow memory without bound. TH: ปฏิเสธ state ใหม่แทนการเพิ่มหน่วยความจำไม่จำกัด
                raise HTTPException(  # EN: Signal temporary limiter capacity exhaustion. TH: แจ้งว่า capacity ของตัวจำกัดชั่วคราวเต็ม
                    status_code=503,  # EN: Mark the limiter as unavailable. TH: ระบุว่าตัวจำกัดยังไม่พร้อม
                    detail="AI rate-limit capacity is temporarily full.",  # EN: Return a non-sensitive operational message. TH: ส่งข้อความระบบที่ไม่เปิดเผยข้อมูล
                    headers={"Retry-After": str(AI_RATE_LIMIT_WINDOW_SECONDS)},  # EN: Tell clients when to retry. TH: แจ้งเวลาที่ควรรอก่อนลองใหม่
                )  # EN: Stop before allocating another per-user queue. TH: หยุดก่อนสร้างคิวต่อผู้ใช้เพิ่ม
            requests = deque()  # EN: Create an empty rolling window for this account. TH: สร้างช่วงเวลาแบบ rolling ว่างสำหรับบัญชีนี้
            _AI_REQUEST_TIMES[user_id] = requests  # EN: Register the window in bounded worker state. TH: ลงทะเบียนช่วงเวลาใน state ที่จำกัดขนาด
        while requests and requests[0] <= cutoff:  # EN: Remove entries at or before the rolling-window boundary. TH: ลบเวลาที่เก่ากว่าหรือเท่าขอบเขต rolling window
            requests.popleft()  # EN: Remove timestamps that have left the active window. TH: ลบ timestamp ที่พ้นช่วงจำกัดแล้ว
        if len(requests) >= AI_RATE_LIMIT_MAX:  # EN: Reject when the user has reached the configured rolling limit. TH: ปฏิเสธเมื่อผู้ใช้ถึงเพดาน rolling limit
            retry_after = max(  # EN: Compute a positive whole-second wait hint. TH: คำนวณเวลารอเป็นวินาทีจำนวนเต็มที่ไม่น้อยกว่าหนึ่ง
                1, ceil(AI_RATE_LIMIT_WINDOW_SECONDS - (current - requests[0]))  # EN: Measure until the oldest request leaves the window. TH: คำนวณจนกว่าคำขอเก่าสุดจะพ้นช่วงเวลา
            )  # EN: Finish the retry delay calculation. TH: จบการคำนวณช่วงเวลาลองใหม่
            raise HTTPException(  # EN: Return a standard rate-limit response. TH: ส่ง response มาตรฐานเมื่อเกินอัตรา
                status_code=429,  # EN: Identify the request as rate limited. TH: ระบุว่า request ถูกจำกัดอัตรา
                detail="AI request limit reached. Please wait before retrying.",  # EN: Tell the client to wait without disclosing limiter state. TH: แจ้งให้รอโดยไม่เปิดเผย state ภายใน
                headers={"Retry-After": str(retry_after)},  # EN: Publish the calculated retry delay. TH: ส่งเวลาที่คำนวณไว้ใน header
            )  # EN: Stop before counting the rejected request. TH: หยุดก่อนนับ request ที่ถูกปฏิเสธ
        requests.append(current)  # EN: Count the current request after it passes the limit check. TH: บันทึกคำขอปัจจุบันหลังผ่านการตรวจเพดาน
        _AI_REQUEST_TIMES.move_to_end(user_id)  # EN: Keep recently used account state at the end for bounded cleanup. TH: ย้ายบัญชีที่ใช้งานล่าสุดไว้ท้ายเพื่อช่วย cleanup แบบจำกัด


@app.get("/health")
def health():  # EN: Report process liveness independently of optional service configuration. TH: รายงานว่า process ยังตอบสนองโดยไม่ผูกกับ config ของ service เสริม
    # EN: Keep the public liveness endpoint free of personal and storage details. TH: ไม่เปิดเผยข้อมูลส่วนบุคคลหรือรายละเอียด storage ใน health check สาธารณะ
    return {"status": "ok"}  # EN: Return only a minimal alive status. TH: คืนเฉพาะสถานะว่า service ตอบสนอง


@app.get("/ready")
def readiness():  # EN: Check required Auth configuration without exposing secret values. TH: ตรวจ config Auth ที่จำเป็นโดยไม่เปิดเผยค่า secret
    supabase_url = _validated_supabase_base_url(os.getenv("SUPABASE_URL"))  # EN: Require a validated HTTPS Auth origin. TH: บังคับใช้ Auth origin HTTPS ที่ผ่านการตรวจ
    supabase_key = os.getenv("SUPABASE_PUBLISHABLE_KEY") or os.getenv("SUPABASE_ANON_KEY", "")  # EN: Accept the configured public project key names. TH: รองรับชื่อ public project key ที่ระบบกำหนด
    if not supabase_url or not supabase_key:  # EN: Mark the service unready when protected routes cannot verify users. TH: ระบุว่ายังไม่พร้อมเมื่อ route ที่ป้องกันตรวจผู้ใช้ไม่ได้
        raise HTTPException(  # EN: Return a generic readiness failure without naming missing values. TH: ตอบว่าไม่พร้อมแบบทั่วไปโดยไม่ระบุค่าตั้งที่หาย
            status_code=503,  # EN: Signal that required configuration is unavailable. TH: แจ้งว่า config ที่จำเป็นยังใช้งานไม่ได้
            detail="Required service configuration is unavailable.",  # EN: Avoid disclosing environment-variable or secret details. TH: ไม่เปิดเผยชื่อตัวแปรหรือรายละเอียด secret
        )  # EN: Finish the controlled readiness failure. TH: จบการตอบกลับ readiness failure ที่ควบคุมแล้ว
    return {"status": "ready"}  # EN: Confirm required Auth configuration is present. TH: ยืนยันว่ามี config Auth ที่จำเป็น


@app.get("/")
def service_root():
    """Return minimal service metadata. / คืน metadata ของ service เท่าที่จำเป็น"""
    # EN: Give browser visits a valid response without returning health events. TH: ให้การเปิด URL ใน browser ได้ response โดยไม่ส่ง event สุขภาพ
    return {"service": "doz Cloud API", "status": "ok", "health": "/health"}  # EN: Publish the service name and liveness path only. TH: แสดงเพียงชื่อ service และ path สำหรับตรวจสถานะ


@app.delete("/account", status_code=204)
def delete_account(authorization: Optional[str] = Header(default=None)):  # EN: Delete only records owned by the authenticated account. TH: ลบเฉพาะข้อมูลของบัญชีที่ยืนยันตัวตนแล้ว
    """EN: Delete the caller's records and Auth account. TH: ลบข้อมูลและบัญชี Auth ของผู้เรียก"""
    user_id = _verify_chat_user(authorization)  # EN: Resolve ownership only from a verified bearer token. TH: ระบุเจ้าของจาก bearer token ที่ยืนยันแล้วเท่านั้น
    supabase_url = _validated_supabase_base_url(os.getenv("SUPABASE_URL"))  # EN: Validate the identity-provider origin before using the admin key. TH: ตรวจ origin ของ identity provider ก่อนใช้ admin key
    service_role_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip()  # EN: Read the privileged key without logging or returning it. TH: อ่าน service key โดยไม่ log หรือส่งกลับให้ client
    if not supabase_url or not service_role_key:  # EN: Require a validated HTTPS origin and admin credential. TH: ต้องมี HTTPS origin ที่ผ่านตรวจและ admin credential
        # EN: Refuse deletion if the identity-provider admin API is not configured. TH: ปฏิเสธการลบบัญชีเมื่อยังไม่ได้ตั้งค่า admin API
        raise HTTPException(  # EN: Fail closed before deleting health data or identity. TH: ปิดการทำงานก่อนลบข้อมูลสุขภาพหรือ identity
            status_code=503,  # EN: Report missing administrative configuration. TH: แจ้งว่า config สำหรับผู้ดูแลยังไม่ครบ
            detail="Account deletion is not configured on this server.",  # EN: Give a safe configuration message. TH: แจ้งข้อความ config ที่ปลอดภัย
        )  # EN: Stop the deletion flow without side effects. TH: หยุดขั้นตอนลบโดยไม่ทำ side effect

    # EN: Do not delete the identity when health records cannot be checked/deleted.
    # TH: ห้ามลบบัญชีเมื่อยังตรวจ/ลบข้อมูลสุขภาพใน persistent storage ไม่ได้
    if not _FIRESTORE_CLIENT and not _memory_health_storage_enabled():  # EN: Require a place where account data can be enumerated and removed. TH: ต้องมี storage ที่ใช้ไล่และลบข้อมูลบัญชีได้
        # EN: Preserve the account when its health records cannot be safely checked. TH: คงบัญชีไว้เมื่อยังตรวจข้อมูลสุขภาพที่ต้องลบไม่ได้
        raise HTTPException(  # EN: Preserve the identity when its data cannot be audited for deletion. TH: คง identity ไว้เมื่อยังตรวจข้อมูลเพื่อลบไม่ได้
            status_code=503,  # EN: Report the storage dependency as unavailable. TH: แจ้งว่า storage dependency ยังใช้ไม่ได้
            detail="Persistent health-data storage is unavailable for account deletion.",  # EN: Explain why deletion must stop. TH: อธิบายเหตุผลที่ต้องหยุดการลบ
        )  # EN: Stop before removing any account state. TH: หยุดก่อนลบ state ของบัญชี

    # EN: Health events are scoped to the verified user document and its device subcollections. TH: event สุขภาพอยู่ใต้ user document ที่ยืนยันแล้วและ subcollection ของอุปกรณ์
    if _FIRESTORE_CLIENT:  # EN: Remove durable events when Firestore is configured. TH: ลบ event ถาวรเมื่อมี Firestore
        try:  # EN: Avoid reporting success if any durable deletion fails. TH: ห้ามรายงานสำเร็จเมื่อการลบถาวรจุดใดล้มเหลว
            for collection in ("sensor_events", "alert_events"):  # EN: Visit both health-event namespaces. TH: ไล่ทั้ง namespace ของ sensor และ alert
                # EN: Select only this service's two health-event collections. TH: เลือกเฉพาะ collection sensor และ alert ของ service นี้
                root = _FIRESTORE_CLIENT.collection(  # EN: Select the namespaced event collection. TH: เลือก event collection ตาม namespace
                    f"{FIRESTORE_COLLECTION_PREFIX}_{collection}"  # EN: Keep the configured product prefix. TH: คง prefix ของผลิตภัณฑ์ตาม config
                ).document(user_id)  # EN: Restrict deletion to this verified account document. TH: จำกัดการลบไว้ที่ document ของบัญชีที่ยืนยันแล้ว
                # EN: Enumerate the verified user's device collections. TH: ไล่ subcollection อุปกรณ์ของผู้ใช้ที่ยืนยันแล้ว
                for device_collection in root.collections():  # EN: Enumerate this owner's device subcollections. TH: ไล่ subcollection อุปกรณ์ของเจ้าของนี้
                    # EN: Stream event documents from the current device collection. TH: อ่านเอกสาร event ใน subcollection อุปกรณ์ปัจจุบัน
                    for event_document in device_collection.stream():  # EN: Stream events to avoid loading the whole collection into memory. TH: stream event เพื่อไม่โหลดทั้ง collection เข้า memory
                        # EN: Delete the event using its server-side document reference. TH: ลบ event ผ่าน document reference ฝั่ง server
                        event_document.reference.delete()  # EN: Delete each event through its Firestore reference. TH: ลบ event ทีละรายการผ่าน Firestore reference
                # EN: Remove the user registry after its device events are deleted. TH: ลบ registry ของผู้ใช้หลังลบ event ของอุปกรณ์
                root.delete()  # EN: Remove the registry after all known device events. TH: ลบ registry หลังลบ event ของอุปกรณ์ที่พบแล้ว
        except Exception as exc:  # EN: Convert any Firestore failure into a non-success response. TH: แปลง Firestore failure เป็น response ที่ไม่รายงานสำเร็จ
            # EN: Hide provider details and avoid claiming that deletion succeeded. TH: ซ่อนรายละเอียด provider และไม่กล่าวอ้างว่าลบสำเร็จ
            raise HTTPException(  # EN: Report incomplete health-data deletion without exposing details. TH: แจ้งว่าลบข้อมูลสุขภาพไม่ครบโดยไม่เปิดเผยรายละเอียด
                status_code=503,  # EN: Keep the account operation retryable after storage recovery. TH: ให้ลองการทำงานซ้ำได้เมื่อ storage กลับมาปกติ
                detail="Could not remove account data from persistent storage.",  # EN: Return a safe generic deletion failure. TH: ส่งข้อความลบไม่สำเร็จแบบทั่วไปที่ปลอดภัย
            ) from exc  # EN: Preserve the server-side cause for controlled diagnostics. TH: เก็บสาเหตุไว้สำหรับวินิจฉัยฝั่ง server

    # EN: Remove this user's process-local events before deleting the identity. TH: ลบ event ในหน่วยความจำของผู้ใช้นี้ก่อนลบ identity
    SENSOR_EVENTS[:] = [e for e in SENSOR_EVENTS if e.get("authUserId") != user_id]  # EN: Remove this owner's sensor events from worker memory. TH: ลบ sensor event ของเจ้าของนี้จาก memory ของ worker
    ALERT_EVENTS[:] = [e for e in ALERT_EVENTS if e.get("authUserId") != user_id]  # EN: Remove this owner's alert events from worker memory. TH: ลบ alert event ของเจ้าของนี้จาก memory ของ worker
    try:  # EN: Call the external identity admin API after health-data removal. TH: เรียก admin API ของ identity หลังลบข้อมูลสุขภาพ
        # EN: Call the admin endpoint only for the already-verified user ID. TH: เรียก admin endpoint ด้วย user ID ที่ยืนยันแล้วเท่านั้น
        response = httpx.delete(  # EN: Delete only the identity resolved from the validated bearer token. TH: ลบเฉพาะ identity ที่ได้จาก bearer token ที่ยืนยัน
            f"{supabase_url}/auth/v1/admin/users/{quote(user_id, safe='')}",  # EN: Escape the user ID as a single URL path component. TH: escape user ID ให้เป็น path component เดียว
            headers={  # EN: Send the server-only admin credential to the validated HTTPS host. TH: ส่ง admin credential ฝั่ง server ไปยัง HTTPS host ที่ตรวจแล้ว
                # EN: Send the privileged key only to the configured identity provider. TH: ส่ง service key ไปยัง identity provider ที่ตั้งค่าไว้เท่านั้น
                "apikey": service_role_key,  # EN: Authenticate with the configured project admin key. TH: ยืนยันกับ project ด้วย admin key ที่ตั้งไว้
                "Authorization": f"Bearer {service_role_key}",  # EN: Supply the same admin credential as a bearer token. TH: ส่ง admin credential เป็น bearer token
            },  # EN: Finish the restricted outbound headers. TH: จบ header ขาออกที่จำกัด
            # EN: Bound network time so a stalled provider cannot hold this worker indefinitely. TH: จำกัดเวลารอ network ไม่ให้ provider ที่ค้างยึด worker ไม่สิ้นสุด
            timeout=10.0,  # EN: Bound how long the remote deletion may block this request. TH: จำกัดเวลาที่ remote delete จะค้าง request นี้
        )  # EN: Finish the bounded account-deletion request. TH: จบ request ลบบัญชีที่มี timeout
    except httpx.HTTPError as exc:  # EN: Catch transport-level failures from Supabase. TH: จับ transport failure จาก Supabase
        # EN: Return a generic provider failure without leaking network details. TH: แจ้ง provider ล้มเหลวแบบทั่วไปโดยไม่เปิดเผยรายละเอียด network
        raise HTTPException(  # EN: Do not claim success when Supabase cannot be reached. TH: ห้ามแจ้งสำเร็จเมื่อเชื่อมต่อ Supabase ไม่ได้
            status_code=503, detail="Account provider is unavailable."  # EN: Hide network internals from the user. TH: ซ่อนรายละเอียด network ภายในจากผู้ใช้
        ) from exc  # EN: Retain the cause for server-side troubleshooting. TH: เก็บสาเหตุไว้แก้ปัญหาฝั่ง server
    if response.status_code < 200 or response.status_code >= 300:  # EN: Require an explicit successful provider response. TH: ต้องได้ response สำเร็จจาก provider อย่างชัดเจน
        # EN: Require an explicit 2xx confirmation before reporting success. TH: ต้องได้คำยืนยันสถานะ 2xx ก่อนรายงานว่าสำเร็จ
        raise HTTPException(  # EN: Treat unconfirmed external deletion as a failure. TH: ถือว่าการลบภายนอกที่ไม่ได้ยืนยันคือความล้มเหลว
            status_code=503, detail="Account provider did not confirm deletion."  # EN: Avoid falsely reporting that the identity is gone. TH: ป้องกันการแจ้งผิดว่า identity ถูกลบแล้ว
        )  # EN: Stop without returning HTTP 204. TH: หยุดโดยไม่ส่ง HTTP 204
    return None  # EN: Emit the configured HTTP 204 empty response. TH: ส่ง response ว่างตาม HTTP 204 ที่กำหนด


@app.get("/sensor")
def sensor_events(  # EN: Read recent sensor events for one verified account. TH: อ่าน sensor event ล่าสุดของบัญชีที่ยืนยันแล้ว
    limit: int = Query(default=100, ge=1, le=500),  # EN: Bound each caller's page size. TH: จำกัดขนาดหน้าข้อมูลของผู้เรียก
    authorization: Optional[str] = Header(default=None),  # EN: Accept the caller's bearer token. TH: รับ bearer token ของผู้เรียก
):  # EN: Return the authenticated account's recent sensor events. TH: คืน sensor event ล่าสุดของบัญชีที่ยืนยันแล้ว
    user_id = _verify_chat_user(authorization)  # EN: Derive the query owner from verified identity. TH: ระบุเจ้าของข้อมูลจาก identity ที่ยืนยันแล้ว
    _require_health_data_sync_enabled()  # EN: Apply the deployment's health-sync gate. TH: ตรวจ gate การ sync ข้อมูลสุขภาพของ deployment
    if _FIRESTORE_CLIENT:  # EN: Prefer durable storage when it is configured. TH: ใช้ storage ถาวรก่อนเมื่อมีการตั้งค่า
        return _read_firestore_events("sensor_events", user_id, limit)  # EN: Read a bounded page for this account from persistent storage. TH: อ่านข้อมูลของบัญชีนี้จาก persistent storage ตามจำนวนจำกัด
    events = [event for event in SENSOR_EVENTS if event.get("authUserId") == user_id]  # EN: Filter process-local records by authenticated owner. TH: กรอง record ในหน่วยความจำตามเจ้าของที่ยืนยันแล้ว
    return events[-limit:]  # EN: Return only the newest requested records. TH: คืนเฉพาะ record ล่าสุดตามจำนวนที่ร้องขอ


@app.get("/alert")
def alert_events(  # EN: Read recent alerts for one verified account. TH: อ่าน alert ล่าสุดของบัญชีที่ยืนยันแล้ว
    limit: int = Query(default=100, ge=1, le=500),  # EN: Bound the requested alert page size. TH: จำกัดขนาดหน้าของ alert ที่ร้องขอ
    authorization: Optional[str] = Header(default=None),  # EN: Accept the caller's bearer token. TH: รับ bearer token ของผู้เรียก
):  # EN: Return only the authenticated account's recent alerts. TH: คืนเฉพาะ alert ล่าสุดของบัญชีที่ยืนยันแล้ว
    user_id = _verify_chat_user(authorization)  # EN: Resolve the alert owner from verified identity. TH: ระบุเจ้าของ alert จาก identity ที่ยืนยันแล้ว
    _require_health_data_sync_enabled()  # EN: Enforce the configured health-data sync policy. TH: บังคับใช้นโยบาย sync ข้อมูลสุขภาพที่ตั้งไว้
    if _FIRESTORE_CLIENT:  # EN: Prefer durable storage when it is configured. TH: ใช้ storage ถาวรก่อนเมื่อมีการตั้งค่า
        return _read_firestore_events("alert_events", user_id, limit)  # EN: Read a bounded page from persistent storage. TH: อ่านข้อมูล persistent แบบจำกัดจำนวน
    events = [event for event in ALERT_EVENTS if event.get("authUserId") == user_id]  # EN: Exclude records owned by other users. TH: ตัด record ที่เป็นของผู้ใช้อื่นออก
    return events[-limit:]  # EN: Return only the newest requested alerts. TH: คืน alert ล่าสุดตามจำนวนที่ร้องขอ


@app.get("/devices")
def devices(authorization: Optional[str] = Header(default=None)):  # EN: List devices associated with the authenticated account. TH: แสดงอุปกรณ์ของบัญชีที่ยืนยันแล้ว
    user_id = _verify_chat_user(authorization)  # EN: Bind the device list to the verified account. TH: ผูกรายการอุปกรณ์กับบัญชีที่ยืนยันแล้ว
    _require_health_data_sync_enabled()  # EN: Apply the health-data sync gate. TH: ตรวจ gate การ sync ข้อมูลสุขภาพ
    if _FIRESTORE_CLIENT:  # EN: Discover devices from durable events when available. TH: ค้นหาอุปกรณ์จาก event ถาวรเมื่อมี
        # EN: Read at most one newest record per allowed device to discover device IDs. TH: อ่าน record ล่าสุดไม่เกินหนึ่งรายการต่ออุปกรณ์เพื่อหา device ID
        events = _read_firestore_events(  # EN: Load bounded recent events to summarize registered devices. TH: โหลด event ล่าสุดแบบจำกัดจำนวนเพื่อสรุปอุปกรณ์ที่ลงทะเบียน
            "sensor_events",  # EN: Use sensor events as the current source of device sightings. TH: ใช้ sensor event เป็นแหล่งพบอุปกรณ์ล่าสุด
            user_id,  # EN: Restrict the query to the verified account. TH: จำกัด query ให้เป็นบัญชีที่ยืนยันแล้ว
            MAX_FIRESTORE_DEVICES_PER_USER,  # EN: Bound the merged results by the device cap. TH: จำกัดผลรวมด้วยเพดานอุปกรณ์
            per_device_limit=1,  # EN: Read at most one event from each device. TH: อ่านไม่เกินหนึ่ง event ต่ออุปกรณ์
        )  # EN: Finish the bounded persistent device lookup. TH: จบการค้นหาอุปกรณ์ใน storage ถาวรแบบจำกัด
    else:  # EN: Use the bounded in-memory fallback when Firestore is unavailable. TH: ใช้ข้อมูลสำรองในหน่วยความจำที่มีขอบเขตเมื่อ Firestore ใช้ไม่ได้
        # EN: Restrict in-memory fallback records to this account. TH: จำกัด record สำรองในหน่วยความจำเฉพาะบัญชีนี้
        events = [event for event in SENSOR_EVENTS if event.get("authUserId") == user_id]  # EN: Filter fallback records to the authenticated account. TH: กรอง record สำรองให้เหลือบัญชีที่ยืนยันแล้ว
    latest: dict[str, dict[str, str]] = {}  # EN: Keep a device summary instead of retaining full health events. TH: เก็บสรุปอุปกรณ์แทนการส่ง event สุขภาพทั้งก้อนกลับ
    for event in events:  # EN: Reduce each authenticated event to device metadata. TH: ย่อ event ของผู้ใช้ที่ยืนยันแล้วให้เหลือ metadata อุปกรณ์
        profile = event.get("userProfile") or {}  # EN: Read only the profile container needed for its device ID. TH: อ่านเฉพาะ profile ที่จำเป็นต่อ device ID
        device_id = str(profile.get("deviceId") or "unknown-device")  # EN: Extract the device identifier for grouping. TH: ดึง device ID มาใช้จัดกลุ่ม
        received_at = str(event.get("receivedAt") or "")  # EN: Normalize the server receipt time for comparison. TH: แปลงเวลาที่ server รับข้อมูลให้อยู่ในรูปข้อความเพื่อเปรียบเทียบ
        current = latest.get(device_id)  # EN: Find the current summary for this device. TH: ค้นหาสรุปปัจจุบันของอุปกรณ์นี้
        if current is None or received_at > current["lastSeen"]:  # EN: Keep the most recently received event per device. TH: เก็บ event ที่ server รับล่าสุดของแต่ละอุปกรณ์
            latest[device_id] = {"deviceId": device_id, "lastSeen": received_at}  # EN: Store only non-sensitive device ID and last-seen time. TH: เก็บเฉพาะรหัสอุปกรณ์และเวลาล่าสุดที่ไม่ใช่ค่าชีวสัญญาณ
    return sorted(latest.values(), key=lambda item: item["deviceId"])  # EN: Return a stable, minimal device list. TH: คืนรายการอุปกรณ์แบบย่อและเรียงลำดับคงที่


def _is_local_request(request: Request) -> bool:  # EN: Gate debug dashboard access behind opt-in and a loopback peer. TH: จำกัด dashboard debug ด้วย opt-in และ loopback peer
    enabled = os.getenv("ENABLE_LOCAL_DEBUG_DASHBOARD", "false").strip().lower()  # EN: Require an explicit operator opt-in before exposing debug health data. TH: บังคับให้ผู้ดูแลเปิดใช้ชัดเจนก่อนแสดงข้อมูลสุขภาพบนหน้า debug
    if enabled not in {"1", "true", "yes"}:  # EN: Keep debug dashboards disabled by default in local and hosted environments. TH: ปิด dashboard debug เป็นค่าเริ่มต้นทั้งในเครื่องและบนโฮสต์
        return False  # EN: Deny access before evaluating network locality. TH: ปฏิเสธก่อนตรวจว่า request มาจากเครื่องเดียวกันหรือไม่
    client_host = request.client.host if request.client else ""  # EN: Read the ASGI peer address, not a client-provided forwarding header. TH: อ่าน peer address จาก ASGI ไม่ใช้ header forward ที่ client ปลอมได้
    # Never trust client-controlled X-Forwarded-For to authorize local dashboards.
    return client_host in {"127.0.0.1", "::1", "localhost", "testclient"}  # EN: Permit only loopback peers after the explicit opt-in. TH: อนุญาตเฉพาะ loopback หลังเปิดใช้อย่างชัดเจน


def _local_only_response() -> HTMLResponse:  # EN: Build a static denial response for remote dashboard requests. TH: สร้าง response ปฏิเสธแบบคงที่สำหรับ request dashboard จากระยะไกล
    return HTMLResponse(  # EN: Return a static denial page without reading or exposing stored events. TH: คืนหน้าแจ้งปฏิเสธแบบคงที่โดยไม่อ่านหรือเปิดเผย event ที่เก็บไว้
        """
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>doz Local Dashboard</title>
  <style>
    body { background:#050608; color:white; font-family:Arial, sans-serif; margin:24px; }
    .card { background:#11141b; border:1px solid #232833; border-radius:8px; padding:16px; max-width:720px; }
    .muted { color:#a7b0c0; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Local dashboard only</h1>
    <p class="muted">This dashboard can be opened only from this computer.</p>
    <p>Open it here: <strong>http://localhost:8000/local-dashboard</strong></p>
  </div>
</body>
</html>
""",
        status_code=403,
    )


def _dashboard_html() -> str:  # EN: Render bounded in-memory events as escaped dashboard HTML. TH: แสดง event ในหน่วยความจำที่มีเพดานเป็น HTML พร้อม escape
    latest_by_device: dict[str, dict[str, Any]] = {}  # EN: Keep one most-recent sensor event per device for display. TH: เก็บ sensor event ล่าสุดหนึ่งรายการต่ออุปกรณ์เพื่อแสดงผล
    for event in SENSOR_EVENTS:  # EN: Inspect the bounded in-memory sensor history. TH: ตรวจประวัติ sensor ในหน่วยความจำที่มีเพดาน
        profile = event.get("userProfile") or {}  # EN: Read the event's optional device profile. TH: อ่าน profile อุปกรณ์ที่อาจไม่มีใน event
        device_id = str(profile.get("deviceId") or "unknown-device")  # EN: Normalize the display key and provide a safe fallback. TH: ปรับ key สำหรับแสดงผลและกำหนดค่าแทนที่ปลอดภัย
        latest_by_device[device_id] = event  # EN: Retain the latest encountered event for this device. TH: เก็บ event ล่าสุดที่พบของอุปกรณ์นี้

    rows = []  # EN: Collect escaped table rows for the device summary. TH: รวบรวมแถวตารางที่ escape แล้วสำหรับสรุปอุปกรณ์
    for device_id, event in latest_by_device.items():  # EN: Format each device's latest event independently. TH: จัดรูป event ล่าสุดของแต่ละอุปกรณ์แยกกัน
        profile = event.get("userProfile") or {}  # EN: Read display-only profile fields. TH: อ่าน field profile สำหรับแสดงผลเท่านั้น
        sensor = event.get("sensorData") or {}  # EN: Read the optional sensor summary. TH: อ่านสรุป sensor ที่อาจไม่มี
        risk = event.get("riskResult") or {}  # EN: Read the optional calculated risk summary. TH: อ่านสรุปความเสี่ยงที่อาจไม่มี
        rows.append(  # EN: Add one escaped row to the local table. TH: เพิ่มแถวที่ escape แล้วลงตารางในเครื่อง
            "<tr>"
            f"<td>{escape(device_id)}</td>"
            f"<td>{escape(str(event.get('receivedAt', '-')))}</td>"
            f"<td>{escape(str(profile.get('age', '-')))}</td>"
            f"<td>{escape(str(profile.get('gender', '-')))}</td>"
            f"<td>{escape(str(_sensor_value(sensor, 'heart_rate', 'heartRate')))}</td>"
            f"<td>{escape(str(_sensor_value(sensor, 'spo2')))}</td>"
            f"<td>{escape(str(_sensor_value(sensor, 'ecg_rate', 'ecgRate')))}</td>"
            f"<td>{escape(str(_sensor_value(sensor, 'ecg_rr_interval', 'ecgRrInterval')))}</td>"
            f"<td>{escape(str(_sensor_value(sensor, 'ecg_hrv', 'ecgHrv')))}</td>"
            f"<td>{escape(str(_sensor_value(sensor, 'gsr')))}</td>"
            f"<td>{escape(str(_sensor_value(sensor, 'temperature')))}</td>"
            f"<td>{escape(str(_sensor_value(sensor, 'motion_magnitude')))}</td>"
            f"<td>{escape(str(_sensor_value(sensor, 'gyro_magnitude')))}</td>"
            f"<td>{escape(str(risk.get('riskClass', '-')))}</td>"
            f"<td>{escape(str(risk.get('alertLevel', '-')))}</td>"
            "</tr>"
        )

    alert_rows = []  # EN: Collect only the recent alert rows shown on this page. TH: รวบรวมเฉพาะแถว alert ล่าสุดที่หน้าเว็บจะแสดง
    for event in ALERT_EVENTS[-30:]:  # EN: Limit dashboard rendering to the latest 30 alerts. TH: จำกัดการแสดง dashboard ไว้ที่ 30 alert ล่าสุด
        profile = event.get("userProfile") or {}  # EN: Read the optional device profile for this alert. TH: อ่าน profile อุปกรณ์ที่อาจไม่มีใน alert
        alert_data = event.get("alert") or {}  # EN: Read the alert payload or use an empty mapping. TH: อ่าน payload alert หรือใช้ mapping ว่าง
        risk = alert_data.get("riskResult") or {}  # EN: Read the optional risk result from the alert. TH: อ่านผลความเสี่ยงที่อาจไม่มีจาก alert
        alert_rows.append(  # EN: Add one escaped row to the recent-alert table. TH: เพิ่มแถวที่ escape แล้วลงตาราง alert ล่าสุด
            "<tr>"
            f"<td>{escape(str(profile.get('deviceId', 'unknown-device')))}</td>"
            f"<td>{escape(str(event.get('receivedAt', '-')))}</td>"
            f"<td>{escape(str(risk.get('riskClass', '-')))}</td>"
            f"<td>{escape(str(risk.get('alertLevel', '-')))}</td>"
            f"<td>{escape(str(alert_data.get('userResponse', 'Pending') or 'Pending'))}</td>"
            "</tr>"
        )

    # EN: Render escaped event values into the local debug dashboard template.
    # TH: render ค่า event ที่ escape แล้วลง template dashboard debug ในเครื่อง
    return f"""
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="5">
  <title>doz Device Dashboard</title>
  <style>
    body {{ background:#050608; color:white; font-family:Arial, sans-serif; margin:24px; }}
    h1, h2 {{ margin-bottom:12px; }}
    .card {{ background:#11141b; border:1px solid #232833; border-radius:8px; padding:16px; margin-bottom:18px; }}
    table {{ width:100%; border-collapse:collapse; }}
    th, td {{ border-bottom:1px solid #232833; padding:10px; text-align:left; }}
    th {{ color:#a7b0c0; }}
    .muted {{ color:#a7b0c0; }}
  </style>
</head>
<body>
  <h1>doz Device Dashboard</h1>
  <p class="muted">Auto-refresh every 5 seconds. Devices: {len(latest_by_device)} | Sensor events: {len(SENSOR_EVENTS)} | Alerts: {len(ALERT_EVENTS)}</p>
  <div class="card">
    <h2>Latest Device Data</h2>
    <table>
      <thead>
        <tr><th>Device ID</th><th>Received</th><th>Age</th><th>Gender</th><th>HR</th><th>SpO2</th><th>ECG Rate</th><th>RR</th><th>HRV</th><th>GSR</th><th>Temp</th><th>Motion</th><th>Gyro</th><th>Risk</th><th>Level</th></tr>
      </thead>
      <tbody>{''.join(rows) if rows else '<tr><td colspan="15">No device data yet.</td></tr>'}</tbody>
    </table>
  </div>
  <div class="card">
    <h2>Recent Alerts</h2>
    <table>
      <thead>
        <tr><th>Device ID</th><th>Received</th><th>Risk</th><th>Level</th><th>User Response</th></tr>
      </thead>
      <tbody>{''.join(alert_rows) if alert_rows else '<tr><td colspan="5">No alerts yet.</td></tr>'}</tbody>
    </table>
  </div>
</body>
</html>
"""


def _sensor_value(sensor: dict[str, Any], key: str, fallback_key: Optional[str] = None):  # EN: Read a preferred sensor field with one legacy alias. TH: อ่าน field sensor หลักพร้อมรองรับชื่อเดิมหนึ่งชื่อ
    value = sensor.get(key)  # EN: Read the preferred field name from the sensor object. TH: อ่าน field หลักจาก sensor object
    if value is None and fallback_key:  # EN: Try the legacy alias only when the preferred key is absent. TH: ใช้ชื่อสำรองเมื่อไม่มีค่าจาก key หลักเท่านั้น
        value = sensor.get(fallback_key)  # EN: Read the compatible legacy field. TH: อ่าน field เก่าที่รองรับ
    return "-" if value is None else value  # EN: Render missing values as a dash without changing valid values. TH: แสดงค่าที่หายเป็นขีดและคงค่าที่มีอยู่


@app.get("/dashboard", response_class=HTMLResponse)
def dashboard(request: Request):  # EN: Serve the debug dashboard only to an authorized local caller. TH: แสดง dashboard debug เฉพาะผู้เรียกในเครื่องที่ผ่านเงื่อนไข
    if not _is_local_request(request):  # EN: Require opt-in and a loopback caller for this debug page. TH: บังคับเปิดใช้และเรียกจาก loopback สำหรับหน้า debug
        return _local_only_response()  # EN: Deny remote access without exposing stored health events. TH: ปฏิเสธ remote โดยไม่เปิดเผย health event ที่เก็บไว้
    return _dashboard_html()  # EN: Render the local-only in-memory event dashboard. TH: แสดง dashboard event ในหน่วยความจำสำหรับเครื่องนี้


@app.get("/local-dashboard", response_class=HTMLResponse)
def local_dashboard(request: Request):  # EN: Expose the same guarded dashboard through its explicit local route. TH: เปิด dashboard ที่มี guard เดียวกันผ่าน path local โดยตรง
    if not _is_local_request(request):  # EN: Apply the same local-only guard to the alias route. TH: ใช้ guard เฉพาะเครื่องเดียวกันกับ route alias
        return _local_only_response()  # EN: Deny remote access consistently. TH: ปฏิเสธ remote อย่างสม่ำเสมอ
    return _dashboard_html()  # EN: Render the local-only in-memory event dashboard. TH: แสดง dashboard event ในหน่วยความจำสำหรับเครื่องนี้


@app.post("/sensor")
def sensor(  # EN: Accept one validated sensor event for the authenticated account. TH: รับ sensor event ที่ตรวจแล้วของบัญชีที่ยืนยัน
    payload: CloudPayload,  # EN: Receive the bounded JSON event after middleware parsing. TH: รับ JSON event ที่ middleware จำกัดขนาดและ parse แล้ว
    authorization: Optional[str] = Header(default=None),  # EN: Read the caller's bearer credential. TH: อ่าน bearer credential ของผู้เรียก
):  # EN: Validate and persist one authenticated sensor event. TH: ตรวจและบันทึก sensor event ของผู้ใช้ที่ยืนยันแล้ว
    """Validate and persist one authenticated sensor event. / ตรวจและบันทึก sensor event ของผู้ใช้ที่ยืนยันตัวตนแล้ว"""
    user_id = _verify_chat_user(authorization)  # EN: Verify the bearer token before accessing user data. TH: ยืนยัน bearer token ก่อนแตะข้อมูลผู้ใช้
    _require_health_data_sync_enabled()  # EN: Stop when this deployment has health sync disabled. TH: หยุดเมื่อ deployment นี้ปิดการ sync ข้อมูลสุขภาพ
    event = payload.model_dump()  # EN: Convert the parsed request model to a mutable event dictionary. TH: แปลง request model ที่ parse แล้วเป็น dictionary สำหรับเติม metadata
    # EN: Bind ownership from verified auth before validation; never trust a client user ID.
    # TH: ใส่เจ้าของจาก token ที่ตรวจแล้วก่อน validate และไม่เชื่อ user ID ที่ client ส่ง
    profile = event.get("userProfile")  # EN: Read optional client profile metadata. TH: อ่าน metadata โปรไฟล์ที่ client อาจส่งมา
    if not isinstance(profile, dict):  # EN: Replace malformed profile containers instead of trusting them. TH: แทนที่ profile ที่ผิดชนิดแทนการเชื่อถือ
        profile = {}  # EN: Start with an empty profile for malformed input. TH: เริ่ม profile ว่างเมื่อ input ผิดรูป
    profile["userId"] = user_id  # EN: Overwrite any client-supplied owner with verified identity. TH: เขียน owner ทับค่าจาก client ด้วย identity ที่ยืนยันแล้ว
    event["userProfile"] = profile  # EN: Store the server-authoritative profile in the event. TH: ใส่ profile ที่ server กำหนดกลับเข้า event
    errors = _validate_sensor_event(event)  # EN: Validate sensor fields, ranges, timestamp, and device metadata. TH: ตรวจ field sensor ช่วงค่า timestamp และ metadata อุปกรณ์
    if errors:  # EN: Reject invalid data before attempting storage. TH: ปฏิเสธข้อมูลผิดก่อนเรียก storage
        # EN: Use 422 to distinguish invalid payload data from malformed HTTP transport. TH: ใช้ 422 เพื่อแยก payload ผิดจาก HTTP transport ที่ผิดรูป
        raise HTTPException(status_code=422, detail={"errors": errors})  # EN: Return field validation failures as unprocessable input. TH: ส่งข้อผิดพลาดของ field เป็น input ที่ประมวลผลไม่ได้
    event = _sanitize_sensor_event(event)  # EN: Persist only validated fields required by the app. TH: บันทึกเฉพาะ field ที่ตรวจแล้วและแอปจำเป็นต้องใช้
    event["authUserId"] = user_id  # EN: Store the server-controlled owner for later access filtering. TH: บันทึกเจ้าของที่ server ควบคุมเพื่อใช้กรองสิทธิ์ภายหลัง
    event["receivedAt"] = datetime.utcnow().isoformat()  # EN: Record server receipt time separately from client time. TH: บันทึกเวลารับจาก server แยกจากเวลาที่ client ส่ง
    persisted = _write_firestore("sensor_events", event)  # EN: Persist the event and propagate storage errors. TH: บันทึก event และส่งต่อข้อผิดพลาดจาก storage
    _append_bounded_event(SENSOR_EVENTS, event)  # EN: Keep a bounded in-process copy for fallback reads. TH: เก็บสำเนาใน process ตามเพดานสำหรับอ่านแบบ fallback
    # EN: Report whether persistence is durable without exposing a process-wide event count. TH: แจ้งว่าข้อมูลถาวรหรือไม่โดยไม่เปิดเผยจำนวน event รวมทั้ง process
    return {  # EN: Return the acceptance status without echoing health values. TH: คืนสถานะรับข้อมูลโดยไม่ส่งค่าชีวสัญญาณกลับ
        "ok": True,  # EN: Confirm the validated event was accepted. TH: ยืนยันว่า event ผ่าน validation และรับไว้แล้ว
        "storage": "firestore" if persisted else "memory-ephemeral",  # EN: Distinguish durable storage from temporary memory. TH: แยก storage ถาวรออกจากหน่วยความจำชั่วคราว
    }  # EN: Finish the minimal sensor-ingest acknowledgement. TH: จบการตอบรับการรับ sensor แบบย่อ


@app.post("/alert")
def alert(  # EN: Accept one validated alert for the authenticated account. TH: รับ alert ที่ตรวจแล้วของบัญชีที่ยืนยัน
    payload: CloudPayload,  # EN: Receive the bounded JSON alert event. TH: รับ alert event แบบ JSON ที่จำกัดขนาดแล้ว
    authorization: Optional[str] = Header(default=None),  # EN: Read the caller's bearer credential. TH: อ่าน bearer credential ของผู้เรียก
):  # EN: Validate and persist an alert for the authenticated account. TH: ตรวจและบันทึก alert ของบัญชีที่ยืนยันแล้ว
    """Validate and persist an authenticated alert. / ตรวจและบันทึก alert ของผู้ใช้ที่ยืนยันตัวตนแล้ว"""
    user_id = _verify_chat_user(authorization)  # EN: Verify ownership before processing the alert. TH: ยืนยันเจ้าของก่อนประมวลผล alert
    _require_health_data_sync_enabled()  # EN: Respect the deployment's health-sync policy. TH: เคารพนโยบาย sync ข้อมูลสุขภาพของ deployment
    event = payload.model_dump()  # EN: Convert parsed request data to a mutable dictionary. TH: แปลง request ที่ parse แล้วเป็น dictionary สำหรับเติม metadata
    profile = event.get("userProfile")  # EN: Read optional account and device metadata. TH: อ่าน metadata บัญชีและอุปกรณ์ที่อาจส่งมา
    if not isinstance(profile, dict):  # EN: Replace malformed profile containers with a safe empty object. TH: แทน profile ที่ผิดชนิดด้วย object ว่างที่ปลอดภัย
        profile = {}  # EN: Use an empty profile as the validation base. TH: ใช้ profile ว่างเป็นฐานสำหรับตรวจ
    profile["userId"] = user_id  # EN: Bind the event to the authenticated account. TH: ผูก event กับบัญชีที่ยืนยันแล้ว
    event["userProfile"] = profile  # EN: Store the server-authoritative profile in the event. TH: ใส่ profile ที่ server ควบคุมกลับเข้า event
    errors: list[str] = []  # EN: Collect all validation failures for one response. TH: รวมปัญหาการตรวจทั้งหมดเพื่อตอบครั้งเดียว
    alert_value = event.get("alert")  # EN: Read the alert object from the payload. TH: อ่าน object alert จาก payload
    if not isinstance(alert_value, dict):  # EN: Require the alert field to be a JSON object. TH: บังคับ field alert ให้เป็น JSON object
        errors.append("alert must be an object")  # EN: Add a safe schema message instead of indexing an invalid value. TH: เพิ่มข้อความ schema ที่ปลอดภัยแทนการ index ค่าผิดชนิด
    else:  # EN: Validate the fields of the structured alert object. TH: ตรวจ field ของ alert object ที่มีโครงสร้างถูกต้อง
        alert_id = alert_value.get("id")  # EN: Read the alert identifier. TH: อ่านรหัส alert
        # EN: Restrict identifiers to a short safe ASCII set. TH: จำกัดรหัสให้อยู่ในชุด ASCII ที่ปลอดภัยและสั้น
        if (  # EN: Require a bounded path-safe alert identifier. TH: บังคับ alert ID ที่จำกัดขนาดและปลอดภัยต่อ path
            not isinstance(alert_id, str)  # EN: Reject non-text identifiers. TH: ปฏิเสธ ID ที่ไม่ใช่ข้อความ
            or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", alert_id)  # EN: Allow only short ASCII letters, digits, underscore, and hyphen. TH: อนุญาตเฉพาะ ASCII สั้นที่เป็นตัวอักษร ตัวเลข underscore และ hyphen
        ):  # EN: Finish alert ID validation. TH: จบการตรวจ alert ID
            errors.append("alert.id must be a nonempty string of at most 128 characters")  # EN: Report the accepted identifier shape. TH: แจ้งรูปแบบ ID ที่ระบบรับ
        # EN: Validate client event time separately from the server receipt time. TH: ตรวจเวลา event จาก client แยกจากเวลารับของ server
        _validate_optional_timestamp(  # EN: Validate the client time while keeping server receipt time separate. TH: ตรวจเวลา client โดยแยกจากเวลารับของ server
            alert_value, "timestamp", errors, prefix="alert."  # EN: Prefix any error with the nested alert field path. TH: เติม prefix path ของ field alert ที่ซ้อนอยู่
        )  # EN: Finish timestamp validation. TH: จบการตรวจ timestamp
        if "sensorData" in alert_value:  # EN: Validate an optional sensor snapshot only when present. TH: ตรวจ snapshot sensor เมื่อแนบมาเท่านั้น
            alert_sensor = alert_value["sensorData"]  # EN: Read the optional sensor snapshot. TH: อ่าน snapshot sensor ที่แนบมา
            if not isinstance(alert_sensor, dict):  # EN: Require sensor snapshots to be JSON objects. TH: บังคับ snapshot sensor เป็น JSON object
                errors.append("alert.sensorData must be an object")  # EN: Reject malformed optional sensor details. TH: ปฏิเสธรายละเอียด sensor ที่เป็นตัวเลือกแต่ผิดรูป
            else:  # EN: Validate the optional snapshot after confirming its object shape. TH: ตรวจ snapshot เมื่อยืนยันแล้วว่าเป็น object
                # EN: Reuse shared validation for numbers, ranges, and ADC channels. TH: ใช้กฎตรวจตัวเลข ช่วงค่า และ ADC ร่วมกัน
                _validate_partial_sensor_data(alert_sensor, errors)  # EN: Validate included measurements without requiring omitted legacy fields. TH: ตรวจค่าที่แนบมาโดยไม่บังคับ field รุ่นเก่าที่ไม่ได้ส่ง
        if "riskResult" in alert_value:  # EN: Validate a supplied result; do not infer a new label here. TH: ตรวจผลที่แนบมาโดยไม่อนุมาน label ใหม่ในขั้นตอนนี้
            _validate_risk_result(  # EN: Validate the provided risk result without trusting its class. TH: ตรวจ risk result ที่ส่งมาโดยไม่เชื่อ class ที่ client ระบุ
                alert_value["riskResult"], errors, "alert.riskResult"  # EN: Include the nested JSON path in any validation message. TH: ระบุ JSON path ที่ซ้อนในข้อความ validation
            )  # EN: Finish risk-result validation. TH: จบการตรวจ risk result
        response = alert_value.get("userResponse")  # EN: Read the optional response text. TH: อ่านข้อความตอบกลับที่อาจมี
        # EN: Bound user-provided text before it is stored. TH: จำกัดข้อความจากผู้ใช้ก่อนจัดเก็บ
        if response is not None and (  # EN: Validate optional user response text only when supplied. TH: ตรวจข้อความตอบกลับเฉพาะเมื่อมีการส่งมา
            not isinstance(response, str) or len(response) > 2_000  # EN: Restrict the value to bounded text. TH: จำกัดค่าให้เป็นข้อความที่มีความยาวกำหนด
        ):  # EN: Finish response-text validation. TH: จบการตรวจข้อความตอบกลับ
            errors.append("alert.userResponse is invalid")  # EN: Report invalid response type or length. TH: แจ้งชนิดหรือความยาวข้อความตอบกลับที่ไม่ถูกต้อง
    device_id_error = _device_id_error(profile.get("deviceId"))  # EN: Validate the optional device identifier. TH: ตรวจรหัสอุปกรณ์ที่อาจส่งมา
    if device_id_error:  # EN: Include device errors in the combined validation response. TH: รวม error ของอุปกรณ์ไว้ใน response ตรวจข้อมูล
        errors.append(device_id_error)  # EN: Keep the validator's safe device-ID message. TH: เก็บข้อความ device ID ที่ปลอดภัยจาก validator
    if errors:  # EN: Reject invalid input before any persistence operation. TH: ปฏิเสธ input ก่อนเรียก persistence
        raise HTTPException(status_code=422, detail={"errors": errors})  # EN: Return all bounded validation failures as unprocessable input. TH: ส่งข้อผิดพลาด validation ที่จำกัดแล้วเป็น input ที่ประมวลผลไม่ได้
    event = _sanitize_alert_event(event)  # EN: Drop unneeded profile and alert fields before persistence. TH: ตัดข้อมูลโปรไฟล์และ alert ที่ไม่จำเป็นก่อนบันทึก
    event["authUserId"] = user_id  # EN: Add the verified owner for future access checks. TH: เพิ่มเจ้าของที่ยืนยันแล้วสำหรับตรวจสิทธิ์ภายหลัง
    event["receivedAt"] = datetime.utcnow().isoformat()  # EN: Record server receipt time for ordering and audit. TH: บันทึกเวลารับของ server เพื่อเรียงลำดับและตรวจย้อนหลัง
    persisted = _write_firestore("alert_events", event)  # EN: Persist and propagate storage failures. TH: บันทึก persistent และส่งต่อเมื่อเกิดปัญหา storage
    _append_bounded_event(ALERT_EVENTS, event)  # EN: Keep a bounded in-process copy for fallback reads. TH: เก็บสำเนาใน process แบบจำกัดเพื่ออ่าน fallback
    # EN: Report durability without disclosing the process-wide alert count. TH: แจ้งชนิด storage โดยไม่เปิดเผยจำนวน alert รวมทั้ง process
    return {  # EN: Return the acceptance status without echoing alert contents. TH: คืนสถานะรับข้อมูลโดยไม่ส่งเนื้อหา alert กลับ
        "ok": True,  # EN: Confirm the validated alert was accepted. TH: ยืนยันว่า alert ผ่าน validation และรับไว้แล้ว
        "storage": "firestore" if persisted else "memory-ephemeral",  # EN: Distinguish durable storage from temporary memory. TH: แยก storage ถาวรออกจากหน่วยความจำชั่วคราว
    }  # EN: Finish the minimal alert-ingest acknowledgement. TH: จบการตอบรับการรับ alert แบบย่อ


# ─────────────────────────────────────────────────────────────────────────────
# RAG: คลังความรู้ + retriever (char n-gram TF-IDF — รองรับไทย ไม่ต้องใช้ torch/faiss)
# ─────────────────────────────────────────────────────────────────────────────
LLM_BASE_URL = os.getenv("LLM_BASE_URL", "https://router.huggingface.co/v1")
LLM_API_KEY = os.getenv("LLM_API_KEY") or os.getenv("HF_TOKEN") or ""
LLM_MODEL_DEFAULT = os.getenv("LLM_MODEL", "nectec/Pathumma-llm-text-1.0.0:featherless-ai")
# EN/TH: Bound retrieved knowledge count / จำกัดจำนวนเอกสารความรู้ที่ดึงมาใช้
RAG_TOP_K = _bounded_env_int("RAG_TOP_K", 3, 1, 50)
# คะแนนความเกี่ยวข้องขั้นต่ำ — ต่ำกว่านี้ถือว่าไม่เกี่ยว (กันดึงความรู้สุขภาพใส่คำถามทั่วไป)
# EN/TH: Keep retrieval threshold finite and within cosine-score bounds / จำกัด threshold ให้อยู่ในช่วง cosine score
RAG_MIN_SCORE = _bounded_env_float("RAG_MIN_SCORE", 0.12, 0.0, 1.0)

SYSTEM_TH = (
    "คุณคือ doz / VitaGuard AI ผู้ช่วยดูแลสุขภาพที่เป็นมิตร "
    "(You are doz / VitaGuard AI, a friendly health companion.)\n"
    "\n"
    "หน้าที่หลัก 3 อย่าง / Your 3 main duties:\n"
    "1. แนะนำการปฏิบัติตัว — บอกชัดๆ ว่าควรทำอะไร (เช่น ควรพักผ่อน ควรดื่มน้ำ ควรหยุดพัก)\n"
    "2. วิเคราะห์สุขภาพสั้นๆ — สรุปสภาพจากค่าเซนเซอร์/แนวโน้มแบบเข้าใจง่าย "
    "(เช่น 'ช่วงนี้พักผ่อนน้อยไป' 'หัวใจเต้นเร็วกว่าปกติ')\n"
    "3. ถามตอบและทักทาย — คุยกับผู้ใช้อย่างเป็นมิตร อบอุ่น ให้กำลังใจ\n"
    "\n"
    "แนวทางการตอบ / Guidelines:\n"
    "- ตอบเป็น 'ภาษาเดียวกับผู้ใช้' เสมอ (ไทยถามไทยตอบ / English in, English out)\n"
    "- ทักทายหรือคุยเล่น (สวัสดี, ขอบคุณ, hello, how are you) ตอบเป็นมิตรสั้นๆ ไม่ปฏิเสธ\n"
    "- คำถามสุขภาพ: วิเคราะห์สั้นๆ 1 ประโยค แล้วตามด้วยคำแนะนำว่าควรทำอะไรเป็นข้อๆ\n"
    "- ตอบกระชับ ตรงประเด็น เป็นกันเอง ไม่อธิบายยืดยาว ไม่ตอบข้อความสำเร็จรูปเดิมซ้ำๆ\n"
    "- ห้ามวินิจฉัยโรคหรือสั่งยา/ระบุขนาดยา ถ้าเป็นเหตุฉุกเฉินรุนแรงให้แนะนำโทร 1669 ก่อนเป็นอันดับแรก\n"
    "- Do not diagnose illness or prescribe medication/doses; direct serious emergencies to local emergency services first."
)


def _ngrams(text: str, n: int = 3) -> list[str]:  # EN: Create character n-grams for Thai-friendly retrieval. TH: สร้าง character n-gram สำหรับค้นข้อความภาษาไทย
    text = re.sub(r"\s+", "", text.lower())  # EN: Normalize case and remove whitespace before tokenizing. TH: ปรับเป็นตัวเล็กและตัดช่องว่างก่อนแบ่ง token
    if len(text) < n:  # EN: Avoid producing invalid short slices. TH: ป้องกันการสร้างส่วนข้อความที่สั้นกว่าขนาด n
        return [text] if text else []  # EN: Keep one short nonempty token or return no tokens. TH: เก็บ token สั้นที่ไม่ว่างหนึ่งรายการหรือคืนรายการว่าง
    return [text[i : i + n] for i in range(len(text) - n + 1)]  # EN: Slide a fixed-width window over the normalized text. TH: เลื่อนหน้าต่างความกว้างคงที่ไปตามข้อความที่ normalize แล้ว


class TfidfRetriever:  # EN: Hold the precomputed local character TF-IDF index. TH: เก็บดัชนี character TF-IDF ในเครื่องที่คำนวณล่วงหน้า
    """retriever แบบ char n-gram TF-IDF (pure python) — เหมาะภาษาไทยที่ไม่มีเว้นวรรค"""

    def __init__(self, docs: list[str]):  # EN: Precompute TF-IDF vectors for the bounded local knowledge set. TH: คำนวณเวกเตอร์ TF-IDF ล่วงหน้าสำหรับคลังความรู้ในเครื่องที่จำกัด
        self.docs = docs  # EN: Retain the source documents for indexed lookup. TH: เก็บเอกสารต้นทางไว้ค้นด้วย index
        tokens = [Counter(_ngrams(d)) for d in docs]  # EN: Count character n-grams in each knowledge document. TH: นับ character n-gram ในเอกสารความรู้แต่ละรายการ
        df: Counter = Counter()  # EN: Initialize document-frequency counts. TH: เริ่มตัวนับ document frequency
        for c in tokens:  # EN: Visit each document's token-frequency map. TH: ตรวจ map ความถี่ token ของแต่ละเอกสาร
            df.update(c.keys())  # EN: Count each token once per document. TH: นับแต่ละ token หนึ่งครั้งต่อเอกสาร
        n = max(len(docs), 1)  # EN: Keep the IDF formula defined for an empty collection. TH: ให้สูตร IDF มีค่าได้แม้คลังเอกสารว่าง
        self.idf = {t: math.log((1 + n) / (1 + dft)) + 1 for t, dft in df.items()}  # EN: Compute smoothed inverse document frequency. TH: คำนวณ inverse document frequency แบบ smoothing
        self.vecs = [self._vec(c) for c in tokens]  # EN: Convert each document's token counts to weighted vectors. TH: แปลงจำนวน token ของแต่ละเอกสารเป็นเวกเตอร์ถ่วงน้ำหนัก
        self.norms = [math.sqrt(sum(v * v for v in vec.values())) or 1.0 for vec in self.vecs]  # EN: Precompute norms and avoid division by zero. TH: คำนวณ norm ล่วงหน้าและป้องกันหารด้วยศูนย์

    def _vec(self, counter: Counter) -> dict:  # EN: Apply IDF weights to one token-frequency counter. TH: ใช้น้ำหนัก IDF กับตัวนับความถี่ token หนึ่งรายการ
        return {t: tf * self.idf.get(t, 0.0) for t, tf in counter.items()}  # EN: Build the sparse TF-IDF vector. TH: สร้างเวกเตอร์ TF-IDF แบบ sparse

    def search(self, query: str, k: int = 3) -> list[tuple[int, float]]:  # EN: Rank local documents by cosine similarity. TH: จัดอันดับเอกสารในเครื่องด้วย cosine similarity
        qv = self._vec(Counter(_ngrams(query)))  # EN: Convert the query to a weighted n-gram vector. TH: แปลง query เป็นเวกเตอร์ n-gram ที่ถ่วงน้ำหนัก
        qn = math.sqrt(sum(v * v for v in qv.values())) or 1.0  # EN: Compute the query norm with a zero-safe fallback. TH: คำนวณ norm ของ query พร้อมค่า fallback เมื่อเป็นศูนย์
        scored = []  # EN: Collect each document index and its similarity. TH: เก็บ index เอกสารและคะแนนความคล้าย
        for i, dv in enumerate(self.vecs):  # EN: Compare the query against every precomputed document vector. TH: เทียบ query กับเวกเตอร์เอกสารที่คำนวณไว้ทุกตัว
            dot = sum(qv.get(t, 0.0) * val for t, val in dv.items())  # EN: Compute the sparse dot product. TH: คำนวณ dot product แบบ sparse
            scored.append((i, dot / (qn * self.norms[i])))  # EN: Normalize to cosine similarity and retain the score. TH: normalize เป็น cosine similarity และเก็บคะแนน
        scored.sort(key=lambda x: x[1], reverse=True)  # EN: Place the most relevant documents first. TH: เรียงเอกสารที่เกี่ยวข้องมากไว้ก่อน
        return [(i, s) for i, s in scored[:k] if s > 0]  # EN: Return only positive matches within the requested result bound. TH: คืนเฉพาะผลบวกภายในจำนวนที่ร้องขอ


_KB_PATH = os.path.join(os.path.dirname(__file__), "knowledge.json")  # EN: Resolve the local RAG file relative to this module. TH: หาไฟล์ RAG ในเครื่องโดยอิงตำแหน่ง module นี้
try:  # EN: Load the optional local knowledge base at startup. TH: โหลดคลังความรู้ในเครื่องที่เป็นตัวเลือกตอนเริ่มระบบ
    with open(_KB_PATH, encoding="utf-8") as f:  # EN: Read knowledge as UTF-8 text. TH: อ่านข้อมูลความรู้เป็นข้อความ UTF-8
        KB: list[dict[str, Any]] = json.load(f)  # EN: Parse the knowledge entries from JSON. TH: parse รายการความรู้จาก JSON
except Exception:  # EN: Keep the service available if the optional file is unavailable or invalid. TH: ให้ service ทำงานต่อเมื่อไฟล์ตัวเลือกหายหรือผิดรูป
    KB = []  # EN: Disable local retrieval instead of using partial unknown state. TH: ปิด local retrieval แทนการใช้ข้อมูลที่ไม่แน่นอน
_RETRIEVER = TfidfRetriever([f"{e.get('q', '')} {e.get('a', '')}" for e in KB]) if KB else None  # EN: Build retrieval index only when valid entries loaded. TH: สร้างดัชนีค้นคืนเมื่อโหลดรายการความรู้ได้


def _extract_question(prompt: str, explicit: str) -> str:  # EN: Select the bounded explicit question or extract it from a prompt. TH: เลือกคำถามที่ส่งแยกหรือดึงออกจาก prompt
    if explicit and explicit.strip():  # EN: Prefer a nonempty explicit question field. TH: ใช้ field คำถามที่ส่งแยกเมื่อไม่ว่าง
        return explicit.strip()  # EN: Remove surrounding whitespace from the explicit question. TH: ตัดช่องว่างรอบคำถามที่ส่งแยก
    m = re.search(r"(?:User question|คำถาม)\s*[:：]\s*(.+)", prompt, re.S)  # EN: Find the marked question section in legacy prompt text. TH: ค้นส่วนคำถามที่มี marker ใน prompt รุ่นเก่า
    return (m.group(1) if m else prompt).strip()  # EN: Use the extracted section or full prompt as a fallback. TH: ใช้ส่วนที่ดึงได้หรือ prompt ทั้งหมดเป็น fallback


def _retrieve(query: str) -> tuple[str, list[dict[str, Any]]]:  # EN: Retrieve relevant bounded local knowledge and source metadata. TH: ค้นความรู้ในเครื่องที่เกี่ยวข้องและ metadata แหล่งอ้างอิงแบบจำกัด
    if not _RETRIEVER or not query.strip():  # EN: Skip retrieval when the index or query is empty. TH: ข้ามการค้นเมื่อไม่มีดัชนีหรือ query ว่าง
        return "", []  # EN: Return no context and no sources. TH: คืนบริบทและแหล่งอ้างอิงเป็นรายการว่าง
    lines, used = [], []  # EN: Collect only accepted answer text and source records. TH: เก็บเฉพาะข้อความที่ผ่านเกณฑ์และข้อมูลแหล่งอ้างอิง
    for idx, score in _RETRIEVER.search(query, RAG_TOP_K):  # EN: Search only up to the configured top-k count. TH: ค้นไม่เกินจำนวน top-k ที่ตั้งไว้
        if score < RAG_MIN_SCORE:  # EN: Exclude weak matches to reduce irrelevant health context. TH: ตัดผลคล้ายต่ำเพื่อลดบริบทสุขภาพที่ไม่เกี่ยวข้อง
            continue  # EN: Skip weak matches so unrelated health context is not injected. TH: ข้ามผลที่เกี่ยวข้องต่ำเพื่อไม่แทรกบริบทสุขภาพที่ไม่เกี่ยว
        ans = KB[idx].get("a", "")  # EN: Read the answer text from the matched knowledge entry. TH: อ่านคำตอบจากรายการความรู้ที่ตรงกัน
        if ans:  # EN: Do not add empty answers to the prompt. TH: ไม่เพิ่มคำตอบว่างลงใน prompt
            lines.append(f"- {ans}")  # EN: Format accepted knowledge as a separate reference line. TH: จัดความรู้ที่ผ่านเกณฑ์เป็นบรรทัดอ้างอิงแยก
            used.append({**KB[idx], "score": round(float(score), 3)})  # EN: Record the source with a display-rounded relevance score. TH: เก็บ source พร้อมคะแนนความเกี่ยวข้องที่ปัดเศษสำหรับแสดงผล
    return "\n".join(lines), used  # EN: Return composed context and matched source metadata. TH: คืนบริบทที่ประกอบแล้วพร้อม metadata แหล่งที่ตรง


def _fallback_answer(prompt: str, context: str) -> str:  # EN: Provide a local answer when the LLM is unavailable. TH: ให้คำตอบในเครื่องเมื่อ LLM ใช้งานไม่ได้
    # ใช้เฉพาะตอน LLM ไม่พร้อม (ไม่มี token / เรียกไม่สำเร็จ)
    low = prompt.lower()  # EN: Normalize the prompt for simple keyword checks. TH: ปรับ prompt เป็นตัวเล็กเพื่อตรวจ keyword
    if "emergency" in low:  # EN: Prioritize the fixed emergency template for explicit English emergency text. TH: ให้ template ฉุกเฉินคงที่มาก่อนเมื่อพบข้อความฉุกเฉินภาษาอังกฤษ
        return "ตรวจพบการแจ้งเตือนระดับฉุกเฉิน หยุดกิจกรรมทันที อยู่ในที่ปลอดภัย และโทร 1669 หากอาการไม่ดีขึ้น"  # EN: Return fixed guidance without model inference. TH: คืนคำแนะนำคงที่โดยไม่ใช้การอนุมานของโมเดล
    if context:  # EN: Use retrieved local context when no emergency keyword matched. TH: ใช้บริบทในเครื่องที่ค้นคืนเมื่อไม่พบ keyword ฉุกเฉิน
        return "จากข้อมูลที่เกี่ยวข้อง:\n" + context  # EN: Clearly mark the local reference context. TH: ระบุชัดว่าเป็นข้อมูลอ้างอิงในเครื่อง
    if "history" in low or "trend" in low or "แนวโน้ม" in prompt:  # EN: Recognize history/trend requests without inventing analytics. TH: ตรวจคำขอประวัติ/แนวโน้มโดยไม่สร้างผลวิเคราะห์ขึ้นเอง
        return "ดูแนวโน้มได้จากประวัติการแจ้งเตือนและประเภทความเสี่ยงที่เกิดซ้ำ"  # EN: Direct the user to existing history rather than fabricate a result. TH: แนะนำให้ดูประวัติที่มีอยู่แทนการแต่งผลลัพธ์
    return (  # EN: Use a fixed unavailable message for unsupported general questions. TH: ใช้ข้อความคงที่เมื่อช่วยตอบคำถามทั่วไปไม่ได้
        "ขออภัย ตอนนี้ผู้ช่วย AI ยังเชื่อมต่อไม่ได้ จึงตอบคำถามทั่วไปไม่ได้ชั่วคราว "
        "(สำหรับเรื่องสุขภาพ/ความปลอดภัยยังให้คำแนะนำเบื้องต้นได้) กรุณาลองใหม่อีกครั้ง"
    )  # EN: Finish the safe LLM-unavailable message. TH: จบข้อความแจ้ง LLM ใช้งานไม่ได้แบบปลอดภัย


@app.post("/chat")
def chat(
    payload: ChatRequest,  # EN: Receive a schema-validated, size-bounded prompt. TH: รับ prompt ที่ตรวจ schema และจำกัดขนาดแล้ว
    authorization: Optional[str] = Header(default=None),  # EN: Read the caller's bearer credential from the header. TH: อ่าน bearer credential ของผู้เรียกจาก header
):  # EN: Return one authenticated chat response. TH: คืนคำตอบแชตสำหรับผู้ใช้ที่ยืนยันแล้ว
    """Authenticate and resource-limit a chat request. / ยืนยันตัวตนและจำกัดทรัพยากรคำขอแชต"""
    user_id = _verify_chat_user(authorization)  # EN: Authenticate before using the external AI provider. TH: ยืนยันตัวตนก่อนเรียกผู้ให้บริการ AI ภายนอก
    _enforce_ai_rate_limit(user_id)  # EN: Apply the per-account request limit. TH: ใช้เพดานคำขอต่อบัญชี
    if not _AI_IN_FLIGHT.acquire(blocking=False):  # EN: Reject excess concurrent provider work without waiting. TH: ปฏิเสธงาน provider ที่พร้อมกันเกินโดยไม่รอคิว
        # EN: Return a retry hint while keeping worker capacity bounded. TH: แจ้งเวลาให้ลองใหม่และรักษาขีดจำกัด worker
        raise HTTPException(  # EN: Refuse new work when all provider slots are occupied. TH: ปฏิเสธงานใหม่เมื่อช่องเรียก provider เต็ม
            status_code=503,  # EN: Mark temporary capacity exhaustion. TH: ระบุว่าความจุชั่วคราวเต็ม
            detail="Chat service is busy. Please retry shortly.",  # EN: Return a safe transient error. TH: ส่งข้อความผิดพลาดชั่วคราวที่ปลอดภัย
            headers={"Retry-After": "2"},  # EN: Suggest a short retry delay. TH: แนะนำเวลารอสั้น ๆ ก่อนลองใหม่
        )  # EN: Stop before generating or sending a prompt. TH: หยุดก่อนสร้างหรือส่ง prompt
    try:  # EN: Guarantee the concurrency slot is released after response generation. TH: รับประกันคืนช่อง concurrency หลังสร้างคำตอบ
        return _generate_chat_reply(payload)  # EN: Generate the response only after all access/resource gates pass. TH: สร้างคำตอบหลังผ่านการยืนยันและจำกัดทรัพยากรแล้ว
    finally:  # EN: Release capacity for success, fallback, and exception paths. TH: คืนความจุทั้งกรณีสำเร็จ fallback และ exception
        _AI_IN_FLIGHT.release()  # EN: Always release the concurrency slot, including on exceptions. TH: คืนช่อง concurrency เสมอแม้เกิด exception


def _generate_chat_reply(payload: ChatRequest) -> dict[str, Any]:  # EN: Compose retrieval, bounded provider call, and fallback response. TH: ประกอบ retrieval, การเรียก provider แบบจำกัด และคำตอบ fallback
    """Build a RAG/LLM reply after shared request guards. / สร้างคำตอบ RAG/LLM หลังผ่าน guard ส่วนกลาง"""
    # EN: Account identity and resource gates have already passed in `chat`. TH: ยืนยันบัญชีและจำกัดทรัพยากรแล้วใน `chat`
    prompt = payload.prompt  # EN: Use the bounded prompt accepted by the request model. TH: ใช้ prompt ที่ request model จำกัดความยาวแล้ว
    question = _extract_question(prompt, payload.question)  # EN: Prefer the explicit question for retrieval. TH: ใช้คำถามแยกสำหรับค้นความรู้ก่อน
    model = LLM_MODEL_DEFAULT  # EN: Select the model from server configuration, never from the client. TH: เลือกโมเดลจากค่าฝั่ง server ไม่รับค่าจาก client

    # [1+2] RAG retrieve ความรู้ที่เกี่ยวข้อง
    context, used = _retrieve(question)  # EN: Retrieve only knowledge above the configured relevance threshold. TH: ค้นเฉพาะความรู้ที่ผ่านเกณฑ์ความเกี่ยวข้อง
    sources = [e.get("q", "") for e in used]  # EN: Return source titles for transparency. TH: เตรียมชื่อแหล่งอ้างอิงเพื่อความโปร่งใส

    # [3] ประกอบ prompt (ความรู้อ้างอิง + prompt เดิมที่มีค่าเซนเซอร์ครบอยู่แล้ว)
    user_content = (  # EN: Keep retrieved material in user context, not in the trusted system role. TH: วางข้อมูลค้นคืนใน user context ไม่ปะปนกับ system ที่เชื่อถือ
        f"[ข้อมูลอ้างอิงที่อาจเกี่ยวข้อง — ใช้ประกอบถ้าตรงกับคำถามเท่านั้น]\n{context}\n\n"  # EN: Mark retrieved text as conditional reference material. TH: ระบุข้อความค้นคืนว่าเป็นข้อมูลอ้างอิงเมื่อเกี่ยวข้องเท่านั้น
        if context  # EN: Include the reference block only when retrieval found relevant content. TH: ใส่บล็อกอ้างอิงเมื่อค้นพบเนื้อหาที่เกี่ยวข้อง
        else ""  # EN: Keep the prompt unchanged when retrieval is empty. TH: คง prompt เดิมเมื่อไม่มีข้อมูลค้นคืน
    ) + prompt  # EN: Append the bounded user prompt after optional context. TH: ต่อ prompt ผู้ใช้ที่จำกัดขนาดหลังบริบทที่เลือก

    # [4] เรียก Pathumma LLM ผ่าน HuggingFace router (ไม่ต้องใช้ GPU)
    base_url = _validated_llm_base_url()  # EN: Validate the destination before attaching the provider key. TH: ตรวจปลายทางก่อนแนบ key ของ provider
    if LLM_API_KEY and base_url:  # EN: Call the provider only with a configured key and validated HTTPS URL. TH: เรียก provider เมื่อมี key และ URL HTTPS ผ่าน validation
        try:  # EN: Convert provider/network failures into the local fallback path. TH: เปลี่ยน provider/network failure ให้ไป fallback ในเครื่อง
            with httpx.stream(  # EN: Stream the provider reply to enforce its byte cap before buffering. TH: stream คำตอบ provider เพื่อบังคับเพดาน byte ก่อน buffer
                f"{base_url}/chat/completions",  # EN: Use the normalized HTTPS base URL. TH: ใช้ base URL HTTPS ที่ normalize แล้ว
                headers={"Authorization": f"Bearer {LLM_API_KEY}", "Accept-Encoding": "identity"},  # EN: Send the validated secret and request uncompressed bytes. TH: ส่ง secret ไปปลายทางที่ตรวจแล้วและขอ byte ที่ไม่บีบอัด
                json={  # EN: Construct the bounded chat-completion request. TH: สร้าง request chat completion ตามขอบเขต
                    "model": model,  # EN: Use the model selected by server configuration. TH: ใช้โมเดลที่เลือกจาก config ฝั่ง server
                    "messages": [  # EN: Separate trusted system rules from user-provided content. TH: แยกกฎ system ที่เชื่อถือจากเนื้อหาของผู้ใช้
                        {"role": "system", "content": SYSTEM_TH},  # EN: Provide the server-owned safety instructions. TH: ส่งคำสั่งความปลอดภัยที่ server กำหนด
                        {"role": "user", "content": user_content},  # EN: Place question and retrieved context in the user message. TH: ใส่คำถามและบริบทค้นคืนใน user message
                    ],  # EN: Finish the role-separated message list. TH: จบรายการข้อความที่แยก role
                    "max_tokens": 256,  # EN: Bound the provider's generated completion length. TH: จำกัดความยาวคำตอบที่ provider สร้าง
                    "temperature": 0.6,  # EN: Set the configured response variability. TH: กำหนดความแปรผันของคำตอบ
                },  # EN: Finish the JSON request body. TH: จบ request body แบบ JSON
                timeout=30.0,  # EN: Bound the time spent waiting for the external provider. TH: จำกัดเวลารอ provider ภายนอก
            ) as resp:  # EN: Keep the response stream open only while consuming bounded content. TH: เปิด response stream เฉพาะช่วงอ่านเนื้อหาที่จำกัด
                answer = _bounded_llm_text(resp)  # EN: Accept only a bounded, correctly shaped provider reply. TH: รับเฉพาะคำตอบ provider ที่ขนาดและโครงสร้างถูกต้อง
            if answer:  # EN: Skip empty model replies and use the deterministic fallback below. TH: ข้ามคำตอบว่างและใช้ fallback ด้านล่าง
                answer = _apply_guardrails(answer)  # EN: Filter high-risk diagnosis/dosage lines before returning chat output. TH: กรองบรรทัดวินิจฉัย/ขนาดยาที่เสี่ยงก่อนคืนคำตอบ
                return {  # EN: Construct the structured response after guardrail filtering. TH: สร้าง response แบบมีโครงสร้างหลังผ่าน guardrail
                    "mode": "llm",  # EN: Identify that an external model produced the response. TH: ระบุว่าคำตอบมาจากโมเดลภายนอก
                    "model": model,  # EN: Report the server-selected model name. TH: แสดงชื่อโมเดลที่ server เลือก
                    "answer": answer,  # EN: Return the guardrail-filtered text. TH: คืนข้อความหลังผ่าน guardrail
                    "rag_sources": sources,  # EN: Include retrieved source titles. TH: แนบชื่อแหล่งความรู้ที่ค้นคืน
                }  # EN: Finish the structured successful chat response. TH: จบ response แชตที่สำเร็จแบบมีโครงสร้าง
        except Exception as exc:  # EN: Use fallback for provider or response-shape errors. TH: ใช้ fallback เมื่อ provider หรือรูปแบบ response ผิดพลาด
            # EN: Keep request and provider exception text out of logs because it may contain user data.
            # TH: ไม่ log ข้อความ exception จาก request/provider เพราะอาจมีข้อมูลผู้ใช้
            print(f"[chat] LLM request failed ({type(exc).__name__}); using fallback")  # EN: Log only the exception class, not prompt or provider details. TH: log เฉพาะชนิด exception ไม่ log prompt หรือรายละเอียด provider
    elif LLM_API_KEY:  # EN: Keep the provider key unused when endpoint validation fails. TH: ไม่ใช้ provider key เมื่อ URL ไม่ผ่าน validation
        print("[chat] endpoint configuration rejected; using fallback")  # EN: Emit a fixed safe configuration diagnostic. TH: log ข้อความ config คงที่ที่ปลอดภัย

    # EN: Fall back to local retrieval/rules when no safe provider response is available.
    # TH: ใช้ retrieval/กฎในเครื่องเมื่อไม่มีคำตอบจาก provider ที่ปลอดภัย
    return {  # EN: Construct an explicit local fallback response. TH: สร้าง response fallback ในเครื่องที่ระบุโหมดชัดเจน
        "mode": "fallback",  # EN: Make fallback mode explicit to the client. TH: ระบุโหมด fallback ให้ client ทราบชัด
        "model": "vita-gaurd-rag-fallback",  # EN: Name the deterministic/RAG fallback path. TH: ระบุเส้นทาง fallback แบบกฎและ RAG
        "answer": _fallback_answer(prompt, context),  # EN: Use local fallback content when provider output is unavailable. TH: ใช้คำตอบสำรองในเครื่องเมื่อ provider ใช้ไม่ได้
        "rag_sources": sources,  # EN: Preserve the source list used by fallback. TH: คงรายการแหล่งที่ fallback ใช้
    }  # EN: Finish the explicit fallback response. TH: จบ response fallback ที่ระบุโหมดชัดเจน


# ─────────────────────────────────────────────────────────────────────────────
# LLM โหมด "ให้คำแนะนำอย่างเดียว" (ไม่ถามตอบ) — ใช้กับหน้า Status / Alert
# ─────────────────────────────────────────────────────────────────────────────
# TH: ข้อความปฏิเสธความรับผิด แนบทุกคำตอบ / EN: safety disclaimer, always attached
DISCLAIMER = (
    "อุปกรณ์ต้นแบบเพื่อความปลอดภัย ไม่ใช่เครื่องมือแพทย์ "
    "หากรู้สึกผิดปกติให้หยุดกิจกรรมและขอความช่วยเหลือ"
)

ADVICE_SYSTEM = (
    "คุณคือ doz AI ผู้ช่วยด้านความปลอดภัย หน้าที่เดียวคือ 'ให้คำแนะนำการปฏิบัติตัว' "
    "จากสถานะที่ระบบตรวจพบ\n"
    "- ให้คำแนะนำสั้นๆ เป็นข้อๆ 2-4 ข้อ ว่าควรทำอะไรตอนนี้\n"
    "- ห้ามถามกลับ ห้ามทักทาย ห้ามสนทนา — ให้คำแนะนำอย่างเดียว\n"
    "- ห้ามวินิจฉัยโรค ห้ามบอกชื่อยา/ขนาดยา\n"
    "- ภาษาไทย กระชับ เป็นมิตร ถ้าเป็นเหตุฉุกเฉินให้บอกโทร 1669 ก่อน"
)

# TH: แพตเทิร์นที่ห้ามหลุดมาในคำแนะนำ (วินิจฉัย/สั่งยา) / EN: guardrail deny patterns
_DENY_PATTERNS = re.compile(
    r"(คุณเป็นโรค|คุณน่าจะเป็น|วินิจฉัยว่า|you have|diagnos|"
    r"\d+\s*(mg|มก\.?|มิลลิกรัม|เม็ด|โดส|dose))",
    re.IGNORECASE,
)


def _apply_guardrails(text: str) -> str:  # EN: Filter selected risky lines and use a safe fixed reply if none remain. TH: กรองบรรทัดเสี่ยงที่กำหนดและใช้ข้อความคงที่หากไม่เหลือ
    """Remove unsafe lines; fail closed if nothing safe remains. / ตัดบรรทัดเสี่ยงและปิดแบบปลอดภัยเมื่อไม่เหลือข้อความ"""
    kept = [ln for ln in text.splitlines() if not _DENY_PATTERNS.search(ln)]  # EN: Remove whole lines matching diagnosis/dosage patterns. TH: ลบบรรทัดที่ตรงกับรูปแบบวินิจฉัยหรือขนาดยา
    cleaned = "\n".join(kept).strip()  # EN: Reassemble and trim the remaining text. TH: รวมบรรทัดที่เหลือและตัดช่องว่างรอบนอก
    # EN: Never restore the original text after filtering removed every line.
    # TH: ห้ามคืนข้อความเดิมหลังตัวกรองลบทุกบรรทัด เพราะจะทำให้ข้าม guardrail
    return cleaned or "ขออภัย ระบบไม่สามารถให้คำแนะนำนี้ได้อย่างปลอดภัย กรุณาติดต่อผู้เชี่ยวชาญหรือหน่วยฉุกเฉินหากจำเป็น"  # EN: Fail closed with a safe handoff message when all lines were filtered. TH: ปิดแบบปลอดภัยและส่งต่อผู้เชี่ยวชาญเมื่อถูกกรองทุกบรรทัด


def _deterministic_advice(status: str, level: str) -> str:  # EN: Choose a fixed local safety template from the supplied status. TH: เลือก template ความปลอดภัยในเครื่องจากสถานะที่ส่งมา
    """TH: คำแนะนำสำรองตายตัวต่อสถานะ (เมื่อ LLM/เน็ตล่ม) / EN: per-state offline fallback"""
    if "ออกซิเจน" in status:  # EN: Prioritize an oxygen-related fixed safety response. TH: ให้คำตอบความปลอดภัยเรื่องออกซิเจนก่อน
        return (  # EN: Return short fixed steps without diagnosing the cause. TH: คืนขั้นตอนคงที่สั้น ๆ โดยไม่วินิจฉัยสาเหตุ
            "• หยุดกิจกรรมทันที นั่งพักในที่อากาศถ่ายเท\n"  # EN: Advise stopping and resting in a ventilated place. TH: แนะนำหยุดกิจกรรมและพักในที่อากาศถ่ายเท
            "• หายใจช้าลึก แล้ววัดค่าซ้ำใน 2 นาที\n"  # EN: Suggest a repeat measurement after a short interval. TH: แนะนำวัดซ้ำหลังช่วงเวลาสั้น ๆ
            "• หากยังต่ำหรือมีอาการ โทร 1669"  # EN: Direct persistent or symptomatic cases to emergency help. TH: แนะนำติดต่อฉุกเฉินเมื่อค่ายังต่ำหรือมีอาการ
        )  # EN: Finish the oxygen-related template. TH: จบ template เรื่องออกซิเจน
    if "หลับใน" in status or "ง่วง" in status:  # EN: Handle drowsiness with immediate activity-stopping advice. TH: จัดการสถานะง่วงด้วยคำแนะนำให้หยุดกิจกรรมทันที
        return (  # EN: Return fixed driving and rest guidance. TH: คืนคำแนะนำคงที่เกี่ยวกับการขับและการพัก
            "• หาที่จอด/หยุดพักในจุดปลอดภัยทันที\n"  # EN: Recommend stopping in a safe location. TH: แนะนำจอดหรือหยุดในจุดปลอดภัย
            "• งีบสั้น 15-20 นาที และดื่มน้ำ\n"  # EN: Suggest a short rest and hydration. TH: แนะนำพักสั้นและดื่มน้ำ
            "• ยังไม่หายง่วง อย่าฝืนทำกิจกรรมต่อ"  # EN: Warn against continuing while still drowsy. TH: เตือนไม่ให้ฝืนทำกิจกรรมต่อเมื่อยังง่วง
        )  # EN: Finish the drowsiness template. TH: จบ template เรื่องง่วง
    if "เคลื่อนไหวผิดปกติ" in status:  # EN: Handle the configured abnormal-movement status. TH: จัดการสถานะการเคลื่อนไหวผิดปกติที่กำหนด
        return (  # EN: Return fixed immediate-safety steps. TH: คืนขั้นตอนความปลอดภัยเร่งด่วนแบบคงที่
            "• หยุดกิจกรรมทันที อยู่ในที่ปลอดภัย\n"  # EN: Recommend stopping and moving to safety. TH: แนะนำหยุดกิจกรรมและอยู่ในที่ปลอดภัย
            "• ให้คนใกล้ชิดช่วยดูอาการ\n"  # EN: Ask a nearby person to observe and assist. TH: ให้คนใกล้ช่วยสังเกตและช่วยเหลือ
            "• หากอาการไม่ดีขึ้น โทร 1669"  # EN: Escalate persistent symptoms to emergency services. TH: ติดต่อฉุกเฉินเมื่ออาการไม่ดีขึ้น
        )  # EN: Finish the abnormal-movement template. TH: จบ template การเคลื่อนไหวผิดปกติ
    if "พัก" in status or "อ่อนล้า" in status or "เครียด" in status:  # EN: Handle rest, fatigue, or stress statuses. TH: จัดการสถานะพัก อ่อนล้า หรือเครียด
        return (  # EN: Return a short rest-oriented template. TH: คืน template สั้นที่เน้นการพัก
            "• หยุดพัก 5-10 นาที หายใจช้าๆ\n"  # EN: Recommend a brief pause and slow breathing. TH: แนะนำพักสั้นและหายใจช้า
            "• ดื่มน้ำ ลดสิ่งกระตุ้น\n"  # EN: Suggest hydration and fewer stimuli. TH: แนะนำดื่มน้ำและลดสิ่งกระตุ้น
            "• ประเมินตัวเองก่อนทำกิจกรรมต่อ"  # EN: Encourage reassessment before resuming activity. TH: แนะนำประเมินตนเองก่อนทำกิจกรรมต่อ
        )  # EN: Finish the rest-oriented template. TH: จบ template การพัก
    if level == "Emergency":  # EN: Apply the emergency response when no more specific status matched. TH: ใช้คำตอบฉุกเฉินเมื่อไม่พบสถานะเฉพาะก่อนหน้า
        return (  # EN: Return the generic emergency safety steps. TH: คืนขั้นตอนความปลอดภัยฉุกเฉินทั่วไป
            "• หยุดกิจกรรมทันที อยู่ในที่ปลอดภัย\n"  # EN: Recommend stopping and reaching safety. TH: แนะนำหยุดและไปอยู่ในที่ปลอดภัย
            "• ประเมินอาการ หากรุนแรง โทร 1669\n"  # EN: Refer severe symptoms to emergency services. TH: ส่งต่ออาการรุนแรงให้หน่วยฉุกเฉิน
            "• แจ้งคนใกล้ชิดให้มาช่วย"  # EN: Recommend involving a nearby helper. TH: แนะนำแจ้งคนใกล้ชิดให้ช่วย
        )  # EN: Finish the emergency template. TH: จบ template ฉุกเฉิน
    return (  # EN: Return general monitoring guidance for other statuses. TH: คืนคำแนะนำติดตามทั่วไปสำหรับสถานะอื่น
        "• เฝ้าสังเกตอาการต่อเนื่อง\n"  # EN: Encourage continued observation. TH: แนะนำเฝ้าสังเกตอาการต่อ
        "• พักเมื่อรู้สึกล้า และดื่มน้ำสม่ำเสมอ\n"  # EN: Suggest rest and regular hydration. TH: แนะนำพักเมื่อเหนื่อยและดื่มน้ำสม่ำเสมอ
        "• หากผิดปกติให้ปรึกษาผู้ดูแลหรือแพทย์"  # EN: Recommend professional advice for persistent concerns. TH: แนะนำปรึกษาผู้ดูแลหรือแพทย์เมื่อมีข้อกังวล
    )  # EN: Finish the general guidance template. TH: จบ template คำแนะนำทั่วไป


def _call_llm(system: str, user_content: str, model: str) -> Optional[str]:  # EN: Request bounded provider text or signal the fallback path. TH: ขอข้อความ provider แบบจำกัดขนาดหรือส่งสัญญาณให้ใช้ fallback
    """Call the configured LLM. / เรียก LLM ที่ตั้งค่าไว้และคืน None เมื่อใช้ไม่ได้"""
    if not LLM_API_KEY:  # EN: Avoid a network request when provider credentials are absent. TH: ไม่เรียก network เมื่อไม่มี credential ของ provider
        return None  # EN: Signal the deterministic fallback path. TH: ส่งสัญญาณให้ใช้ fallback แบบกำหนดแน่นอน
    base_url = _validated_llm_base_url()  # EN: Validate the credential destination before sending a secret. TH: ตรวจปลายทางก่อนส่ง secret
    if base_url is None:  # EN: Fail closed to the local fallback for an unsafe endpoint. TH: ปฏิเสธ endpoint ที่ไม่ปลอดภัยและใช้ fallback ในเครื่อง
        print("[llm] endpoint configuration rejected")  # EN: Log a fixed category without revealing configured values. TH: log หมวดคงที่โดยไม่เปิดเผยค่าที่ตั้ง
        return None  # EN: Do not transmit the API key to an unchecked URL. TH: ห้ามส่ง API key ไปยัง URL ที่ไม่ผ่านการตรวจ
    try:  # EN: Convert network, HTTP, and response-shape failures into a fallback. TH: เปลี่ยนปัญหา network, HTTP และรูปแบบ response ให้ไป fallback
        with httpx.stream(  # EN: Stream the provider response to enforce the cap before buffering. TH: stream response provider เพื่อบังคับเพดานก่อน buffer
            f"{base_url}/chat/completions",  # EN: Use the normalized HTTPS URL after validation. TH: ใช้ URL HTTPS ที่ normalize หลังตรวจแล้ว
            headers={"Authorization": f"Bearer {LLM_API_KEY}", "Accept-Encoding": "identity"},  # EN: Send the validated key and request identity encoding. TH: ส่ง key ไปยัง host ที่ผ่าน validationและขอ identity encoding
            json={  # EN: Build the provider request from server-selected instructions and model. TH: สร้าง request ด้วยคำสั่งและโมเดลที่ server เลือก
                "model": model,  # EN: Use the configured server model. TH: ใช้โมเดลที่ตั้งค่าฝั่ง server
                "messages": [  # EN: Keep the trusted system role separate from user content. TH: แยก role system ที่เชื่อถือจากเนื้อหาผู้ใช้
                    {"role": "system", "content": system},  # EN: Include the server-owned instruction text. TH: ใส่คำสั่งที่ server เป็นผู้กำหนด
                    {"role": "user", "content": user_content},  # EN: Include the bounded composed user context. TH: ใส่บริบทผู้ใช้ที่ประกอบและจำกัดแล้ว
                ],  # EN: Finish the role-separated message list. TH: จบรายการข้อความที่แยก role
                "max_tokens": 220,  # EN: Ask the provider to bound generated output. TH: ขอให้ provider จำกัดความยาวข้อความที่สร้าง
                "temperature": 0.5,  # EN: Set the chosen generation variability. TH: ตั้งค่าความแปรผันของการสร้างข้อความ
            },  # EN: Finish the JSON body. TH: จบ JSON body
            timeout=30.0,  # EN: Limit total wait time for the provider request. TH: จำกัดเวลารอรวมสำหรับ request ไป provider
        ) as resp:  # EN: Keep the response stream within this bounded read scope. TH: จำกัดอายุ response stream ไว้ในช่วงอ่านที่กำหนด
            text = _bounded_llm_text(resp)  # EN: Parse only a bounded response with the expected schema. TH: parse เฉพาะ response ที่จำกัดขนาดและมี schema ตามที่คาด
        return text or None  # EN: Treat an empty answer as unavailable. TH: ถือคำตอบว่างว่า provider ใช้งานไม่ได้
    except Exception as exc:  # EN: Fall back for any transport or parsing failure. TH: ใช้ fallback เมื่อ transport หรือการ parse ล้มเหลว
        # Never log provider exception text; it can include request or endpoint details.
        print(f"[llm] request failed ({type(exc).__name__})")  # EN: Log only the exception type, never response or prompt contents. TH: log เฉพาะชนิด exception ไม่ log response หรือ prompt
        return None  # EN: Tell the caller to use deterministic fallback advice. TH: แจ้ง caller ให้ใช้คำแนะนำ fallback ที่กำหนดแน่นอน


def _bounded_llm_text(response: httpx.Response) -> Optional[str]:  # EN: Validate provider response size and extract bounded model text. TH: ตรวจขนาด response provider และดึงข้อความโมเดลที่จำกัดแล้ว
    """Reject oversized or malformed LLM responses. / ปฏิเสธ response LLM ที่ใหญ่หรือผิดรูป"""
    content_length = response.headers.get("content-length")  # EN: Read the optional provider-declared body size. TH: อ่านขนาด body ที่ provider ประกาศไว้ถ้ามี
    if content_length is not None:  # EN: Check a declared size before JSON decoding. TH: ตรวจขนาดที่ประกาศก่อนถอดรหัส JSON
        if not re.fullmatch(r"[0-9]{1,10}", content_length):  # EN: Reject malformed or excessively long length headers. TH: ปฏิเสธ length header ที่ผิดรูปหรือยาวเกิน
            raise ValueError("Invalid LLM response Content-Length.")  # EN: Stop parsing an ambiguous response size. TH: หยุด parse เมื่อขนาด response กำกวม
        if int(content_length) > MAX_LLM_RESPONSE_BYTES:  # EN: Reject responses above the configured parse bound. TH: ปฏิเสธ response ที่เกินขอบเขตการ parse
            raise ValueError("LLM response is too large.")  # EN: Avoid expanding an oversized JSON document. TH: ป้องกันการขยาย JSON ที่ใหญ่เกิน
    response.raise_for_status()  # EN: Treat provider error statuses as unavailable responses. TH: ถือ status error ของ provider ว่าใช้งานไม่ได้
    content_encoding = response.headers.get("content-encoding", "identity").strip().lower()  # EN: Inspect compression before reading raw bytes. TH: ตรวจการบีบอัดก่อนอ่าน raw bytes
    if content_encoding not in {"", "identity"}:  # EN: Reject compression to prevent decompression expansion bypassing the cap. TH: ปฏิเสธ compression เพื่อกัน decompression ขยายข้อมูลทะลุเพดาน
        raise ValueError("Compressed LLM responses are not accepted.")  # EN: Require identity encoding for predictable memory bounds. TH: บังคับ identity encoding เพื่อจำกัด memory ได้แน่นอน
    body_chunks: list[bytes] = []  # EN: Collect only chunks that fit within the response byte limit. TH: เก็บเฉพาะ chunk ที่ยังอยู่ในเพดาน byte
    body_size = 0  # EN: Track raw response bytes before retaining each chunk. TH: นับ raw response bytes ก่อนเก็บแต่ละ chunk
    for chunk in response.iter_raw():  # EN: Read undecoded bytes incrementally from the provider. TH: อ่าน byte ที่ยังไม่ decode จาก provider ทีละส่วน
        body_size += len(chunk)  # EN: Count the next raw chunk before appending it. TH: นับ raw chunk ก่อนเพิ่มเข้า buffer
        if body_size > MAX_LLM_RESPONSE_BYTES:  # EN: Stop immediately when the actual body crosses its cap. TH: หยุดทันทีเมื่อ body จริงเกินเพดาน
            raise ValueError("LLM response is too large.")  # EN: Abort streaming before buffering the oversized body. TH: ยกเลิก stream ก่อน buffer body ที่ใหญ่เกิน
        body_chunks.append(chunk)  # EN: Retain only the chunk confirmed to fit. TH: เก็บเฉพาะ chunk ที่ยืนยันแล้วว่าไม่เกินเพดาน
    body = b"".join(body_chunks)  # EN: Join the bounded chunks once for JSON parsing. TH: รวม chunk ที่จำกัดแล้วครั้งเดียวเพื่อ parse JSON
    payload = json.loads(body)  # EN: Parse only the bounded response bytes. TH: parse เฉพาะ byte response ที่ผ่านการจำกัดขนาด
    if not isinstance(payload, dict):  # EN: Require a JSON object at the response root. TH: บังคับ root ของ response เป็น JSON object
        raise ValueError("Invalid LLM response shape.")  # EN: Reject a response that cannot contain choices. TH: ปฏิเสธ response ที่ไม่มีโครงสร้าง choices
    choices = payload.get("choices")  # EN: Read the provider's completion choices. TH: อ่านรายการคำตอบจาก provider
    if not isinstance(choices, list) or not choices or not isinstance(choices[0], dict):  # EN: Require a first choice object. TH: บังคับให้มี choice แรกชนิด object
        raise ValueError("Invalid LLM response choices.")  # EN: Reject missing or malformed completion choices. TH: ปฏิเสธ choices ที่หายหรือผิดรูป
    message = choices[0].get("message")  # EN: Read the assistant message object. TH: อ่าน assistant message object
    if not isinstance(message, dict):  # EN: Require the expected message mapping. TH: บังคับ message เป็น mapping ตามรูปแบบที่คาด
        raise ValueError("Invalid LLM response message.")  # EN: Reject a completion without a structured message. TH: ปฏิเสธคำตอบที่ไม่มี message แบบมีโครงสร้าง
    text = message.get("content")  # EN: Read generated model content without coercing types. TH: อ่านข้อความโมเดลโดยไม่แปลงชนิดอัตโนมัติ
    if not isinstance(text, str) or len(text) > MAX_LLM_TEXT_CHARS:  # EN: Require bounded plain text before exposing it to clients. TH: บังคับข้อความธรรมดาที่มีความยาวจำกัดก่อนส่งให้ client
        raise ValueError("Invalid or oversized LLM text.")  # EN: Reject nested, non-text, or oversized output. TH: ปฏิเสธ output ซ้อน ไม่ใช่ข้อความ หรือยาวเกิน
    return text.strip() or None  # EN: Treat whitespace-only completions as unavailable. TH: ถือคำตอบที่มีแต่ช่องว่างว่าใช้ไม่ได้


def _validated_llm_base_url() -> Optional[str]:  # EN: Validate the provider URL before attaching its API key. TH: ตรวจ URL provider ก่อนแนบ API key
    """Accept bounded HTTPS URLs without embedded credentials or query data. / รับ URL HTTPS ที่จำกัดขนาดและไม่มี credential/query ฝังอยู่"""
    # EN: Parse the operator-configured URL without making a network request.
    # TH: parse URL ที่ผู้ดูแลตั้งไว้โดยไม่เรียก network
    try:  # EN: Convert the configured string to a parsed URL. TH: แปลงข้อความ config เป็น URL ที่ parse แล้ว
        endpoint = httpx.URL(LLM_BASE_URL.strip())  # EN: Trim outer whitespace before parsing. TH: ตัดช่องว่างรอบนอกก่อน parse
    except (TypeError, ValueError):  # EN: Treat malformed settings as unavailable. TH: ถือ config ที่ผิดรูปว่าใช้งานไม่ได้
        return None  # EN: Reject malformed URL configuration. TH: ปฏิเสธ URL config ที่ผิดรูป
    if (  # EN: Reject unsafe URL properties before making a provider request. TH: ปฏิเสธคุณสมบัติ URL ที่ไม่ปลอดภัยก่อนเรียก provider
        len(LLM_BASE_URL) > 2_048  # EN: Bound configuration parsing and logging risk. TH: จำกัดความยาว config และความเสี่ยงด้าน log
        or endpoint.scheme != "https"  # EN: Prevent sending the API key over plaintext HTTP. TH: ป้องกันส่ง API key ผ่าน HTTP ที่ไม่เข้ารหัส
        or not endpoint.host  # EN: Require a concrete destination host. TH: บังคับให้มี host ปลายทาง
        or endpoint.username  # EN: Disallow credentials embedded in the URL. TH: ห้ามฝัง username ใน URL
        or endpoint.password  # EN: Disallow passwords embedded in the URL. TH: ห้ามฝัง password ใน URL
        or endpoint.query  # EN: Disallow unexpected query data on the base endpoint. TH: ห้าม query ที่ไม่คาดหมายบน base endpoint
        or endpoint.fragment  # EN: Disallow fragments that can make endpoint interpretation ambiguous. TH: ห้าม fragment ที่ทำให้การตีความ endpoint กำกวม
    ):  # EN: Finish the unsafe-provider-URL condition. TH: จบเงื่อนไขตรวจ URL provider ที่ไม่ปลอดภัย
        # EN: Require a short HTTPS destination without embedded secrets or ambiguous suffixes.
        # TH: บังคับปลายทาง HTTPS ที่สั้นและไม่มี secret หรือส่วนต่อท้ายกำกวม
        return None  # EN: Fail closed and use the non-network fallback. TH: ปฏิเสธและใช้ fallback ที่ไม่เรียก network
    return str(endpoint).rstrip("/")  # EN: Normalize one trailing slash for endpoint joining. TH: normalize โดยตัด slash ท้ายก่อนต่อ path


@app.post("/advice")
def advice(
    payload: AdviceRequest,
    authorization: Optional[str] = Header(default=None),
):
    """Return bounded safety advice for an authenticated account. / คืนคำแนะนำความปลอดภัยแบบจำกัดสำหรับบัญชีที่ยืนยันแล้ว"""
    user_id = _verify_chat_user(authorization)  # EN: Authenticate the caller before processing health context. TH: ยืนยันผู้เรียกก่อนประมวลผลบริบทสุขภาพ
    _enforce_ai_rate_limit(user_id)  # EN: Apply the shared per-account AI request limit. TH: ใช้เพดาน AI ต่อบัญชีร่วมกัน
    if not _AI_IN_FLIGHT.acquire(blocking=False):  # EN: Bound concurrent provider calls across AI routes. TH: จำกัดการเรียก provider พร้อมกันข้าม route AI
        # EN: Ask the client to retry after a short delay. TH: แจ้ง client ให้ลองใหม่หลังรอสั้นๆ
        raise HTTPException(  # EN: Report temporary capacity exhaustion without exposing internals. TH: แจ้งว่าความจุชั่วคราวเต็มโดยไม่เปิดเผยข้อมูลภายใน
            status_code=503,
            detail="AI service is busy. Please retry shortly.",
            headers={"Retry-After": "2"},
        )
    try:  # EN: Guarantee the concurrency slot is released after generation. TH: รับประกันคืนช่อง concurrency หลังสร้างคำแนะนำ
        return _generate_advice(payload)  # EN: Generate advice after identity and resource checks. TH: สร้างคำแนะนำหลังตรวจ identity และทรัพยากร
    finally:
        _AI_IN_FLIGHT.release()  # EN: Release the slot regardless of success or failure. TH: คืนช่องการทำงานไม่ว่าผลสำเร็จหรือล้มเหลว


def _generate_advice(payload: AdviceRequest) -> dict[str, Any]:  # EN: Build advice after route-level identity and resource guards. TH: สร้างคำแนะนำหลัง route ตรวจ identity และทรัพยากรแล้ว
    """EN: Generate advice after shared guards pass. TH: สร้างคำแนะนำหลังผ่าน guard ส่วนกลาง"""
    status = payload.status.strip()  # EN: Normalize the bounded status label. TH: ปรับข้อความสถานะที่ถูกจำกัดความยาวแล้ว
    level = payload.alert_level.strip()  # EN: Normalize the optional alert level. TH: ปรับระดับ alert ที่เป็น optional
    sensor = payload.sensor.strip()  # EN: Normalize the bounded sensor summary text. TH: ปรับข้อความสรุป sensor ที่ถูกจำกัดความยาวแล้ว
    if not status:  # EN: Refuse to generate advice without a status. TH: ปฏิเสธการสร้างคำแนะนำเมื่อไม่มีสถานะ
        raise HTTPException(status_code=422, detail="status must not be blank.")  # EN: Reject whitespace-only status labels as invalid input. TH: ปฏิเสธสถานะที่มีแต่ช่องว่างเป็น input ไม่ถูกต้อง
    model = LLM_MODEL_DEFAULT  # EN: Select the model from server configuration. TH: เลือกโมเดลจากค่าฝั่ง server

    context, used = _retrieve(f"{status} {sensor}")  # EN: Retrieve relevant local references from bounded user text. TH: ค้นแหล่งอ้างอิงในเครื่องจากข้อความผู้ใช้ที่จำกัดแล้ว
    sources = [  # EN: Prepare source metadata without exposing retrieved document bodies. TH: เตรียม metadata แหล่งอ้างอิงโดยไม่เปิดเนื้อหาเอกสารที่ค้นคืน
        {"title": e.get("q", ""), "score": e.get("score", 0.0)} for e in used  # EN: Keep only each source label and relevance score. TH: เก็บเฉพาะชื่อแหล่งกับคะแนนความเกี่ยวข้อง
    ]  # EN: Finish the bounded source summary. TH: จบสรุปแหล่งอ้างอิงแบบจำกัด
    cause = f"สถานะที่ตรวจพบ: {status}" + (f" (ระดับ {level})" if level else "")  # EN: Describe the input status without inferring a diagnosis. TH: ระบุสถานะ input โดยไม่อนุมานการวินิจฉัย

    user_content = (  # EN: Compose provider input from bounded fields and optional retrieved context. TH: ประกอบ input provider จาก field ที่จำกัดและบริบทค้นคืนที่อาจมี
        (f"[ความรู้อ้างอิง]\n{context}\n\n" if context else "")  # EN: Include local references only when retrieval found them. TH: ใส่อ้างอิงในเครื่องเมื่อ retrieval พบข้อมูล
        + f"สถานะที่ระบบตรวจพบ: {status} (ระดับ {level})\n"  # EN: State the supplied status and level. TH: ระบุสถานะและระดับที่ส่งมา
        + (f"ค่าที่เกี่ยวข้อง: {sensor}\n" if sensor else "")  # EN: Include the optional bounded sensor summary. TH: ใส่ข้อความสรุป sensor ที่จำกัดแล้วเมื่อมี
        + "ให้คำแนะนำว่าควรปฏิบัติตัวอย่างไรตอนนี้"  # EN: Ask for practical next-step guidance. TH: ขอแนวทางปฏิบัติขั้นต่อไป
    )  # EN: Finish provider user content construction. TH: จบการสร้างเนื้อหาผู้ใช้สำหรับ provider

    text = _call_llm(ADVICE_SYSTEM, user_content, model)  # EN: Request a bounded model answer or get None for fallback. TH: ขอคำตอบโมเดลแบบจำกัดหรือรับ None เพื่อใช้ fallback
    if text:  # EN: Use provider text only when a valid nonempty answer was returned. TH: ใช้ข้อความ provider เมื่อได้คำตอบที่ถูกต้องและไม่ว่างเท่านั้น
        return {  # EN: Build the response and apply the shared output filter. TH: สร้าง response และใช้ตัวกรอง output ร่วม
            "mode": "rag",  # EN: Mark that retrieval/LLM path produced the answer. TH: ระบุว่าได้คำตอบจากเส้นทาง retrieval/LLM
            "model": model,  # EN: Report the server-selected model. TH: แสดงโมเดลที่ server เลือก
            "cause": cause,  # EN: Return a summary of the observed status. TH: คืนสรุปสถานะที่ตรวจพบ
            "advice": _apply_guardrails(text),  # EN: Remove matching risky lines before returning. TH: ตัดบรรทัดเสี่ยงที่ตรงตัวกรองก่อนคืนผล
            "sources": sources,  # EN: Include bounded source metadata for transparency. TH: แนบ metadata แหล่งอ้างอิงแบบจำกัดเพื่อความโปร่งใส
            "disclaimer": DISCLAIMER,  # EN: Preserve the health-advice disclaimer. TH: คงข้อความกำกับคำแนะนำสุขภาพ
        }  # EN: Finish the filtered provider response. TH: จบ response provider หลังกรอง

    # fallback: คำแนะนำตายตัวต่อสถานะ (ทำงานได้แม้ไม่มี token/เน็ต)
    return {  # EN: Return a deterministic local response when LLM output is unavailable. TH: คืนคำตอบในเครื่องแบบกำหนดแน่นอนเมื่อไม่มีผลจาก LLM
        "mode": "fallback",  # EN: Mark the response as fallback, not model-generated. TH: ระบุว่าเป็น fallback ไม่ใช่ผลที่โมเดลสร้าง
        "model": "rule-fallback",  # EN: Identify the deterministic advice path. TH: ระบุเส้นทางคำแนะนำแบบกฎ
        "cause": cause,  # EN: Preserve the supplied status summary. TH: คงข้อความสรุปสถานะที่ส่งมา
        "advice": _deterministic_advice(status, level),  # EN: Select a fixed safe template from the bounded status. TH: เลือก template คงที่จากสถานะที่จำกัดแล้ว
        "sources": sources,  # EN: Return any local reference metadata already retrieved. TH: คืน metadata อ้างอิงในเครื่องที่ค้นได้
        "disclaimer": DISCLAIMER,  # EN: Preserve the health-advice disclaimer. TH: คงข้อความกำกับคำแนะนำสุขภาพ
    }  # EN: Finish the explicit fallback response. TH: จบ response fallback ที่ระบุชัด


def _validate_sensor_event(event: dict[str, Any]) -> list[str]:  # EN: Validate a sensor event and return safe error messages. TH: ตรวจ sensor event และคืนข้อความผิดพลาดที่ปลอดภัย
    # EN: Validate the complete app sensor-event contract before persistence.
    # TH: ตรวจ contract sensor event จากแอปให้ครบก่อนบันทึก
    errors: list[str] = []  # EN: Accumulate safe validation messages for a single response. TH: รวบรวมข้อความตรวจข้อมูลที่ปลอดภัยไว้ตอบครั้งเดียว
    _validate_optional_timestamp(event, "timestamp", errors)  # EN: Check client event time without trusting it for ownership. TH: ตรวจเวลา event จาก client โดยไม่ใช้ยืนยันเจ้าของ
    sensor = event.get("sensorData")  # EN: Read the nested sensor measurements. TH: อ่านค่าการวัด sensor ที่ซ้อนอยู่
    if not isinstance(sensor, dict):  # EN: Require a JSON object before field-level validation. TH: บังคับเป็น JSON object ก่อนตรวจราย field
        errors.append("sensorData must be an object")  # EN: Record a schema error for the caller. TH: บันทึกข้อผิดพลาดด้านโครงสร้างข้อมูล
        sensor = {}  # EN: Use an empty mapping so later checks remain safe. TH: ใช้ mapping ว่างเพื่อให้การตรวจถัดไปทำงานได้ปลอดภัย
    _require_range(errors, sensor, "heart_rate", "heartRate", 0, 240)  # EN: Check heart rate and its legacy key. TH: ตรวจชีพจรและชื่อ field รุ่นเก่า
    _require_range(errors, sensor, "spo2", None, 0, 100)  # EN: Bound SpO2 percentage. TH: จำกัดค่า SpO2 ให้อยู่ในช่วงเปอร์เซ็นต์
    _require_range(errors, sensor, "ecg_rate", "ecgRate", 0, 240)  # EN: Check ECG rate and its legacy key. TH: ตรวจอัตรา ECG และชื่อ field รุ่นเก่า
    _require_range(errors, sensor, "ecg_rr_interval", "ecgRrInterval", 0, 3000)  # EN: Bound ECG interval in milliseconds. TH: จำกัดช่วง ECG หน่วยมิลลิวินาที
    _require_range(errors, sensor, "ecg_hrv", "ecgHrv", 0, 500)  # EN: Bound the HRV measurement. TH: จำกัดค่าการวัด HRV
    _require_range(errors, sensor, "gsr", None, 0, 1000)  # EN: Bound the GSR measurement. TH: จำกัดค่าการวัด GSR
    _require_range(errors, sensor, "temperature", None, 20, 45)  # EN: Bound temperature in Celsius. TH: จำกัดอุณหภูมิหน่วยองศาเซลเซียส
    for key in [  # EN: Enumerate motion channels that require finite numeric values. TH: ระบุช่องการเคลื่อนไหวที่ต้องเป็นตัวเลข finite
        "accel_x",  # EN: Validate acceleration on the X axis. TH: ตรวจความเร่งแกน X
        "accel_y",  # EN: Validate acceleration on the Y axis. TH: ตรวจความเร่งแกน Y
        "accel_z",  # EN: Validate acceleration on the Z axis. TH: ตรวจความเร่งแกน Z
        "gyro_x",  # EN: Validate angular rate on the X axis. TH: ตรวจอัตราการหมุนแกน X
        "gyro_y",  # EN: Validate angular rate on the Y axis. TH: ตรวจอัตราการหมุนแกน Y
        "gyro_z",  # EN: Validate angular rate on the Z axis. TH: ตรวจอัตราการหมุนแกน Z
        "motion_magnitude",  # EN: Validate the app's motion magnitude summary. TH: ตรวจค่าสรุปขนาดการเคลื่อนไหวของแอป
        "gyro_magnitude",  # EN: Validate the app's gyro magnitude summary. TH: ตรวจค่าสรุปขนาด gyro ของแอป
    ]:  # EN: Finish the required motion-field list. TH: จบรายการ field การเคลื่อนไหว
        _require_number(errors, sensor, key)  # EN: Reject missing, non-finite, and excessive motion values. TH: ปฏิเสธค่าการเคลื่อนไหวที่หาย ไม่ finite หรือสูงเกิน
    _validate_optional_adc(sensor, "red_adc_mean", errors)  # EN: Validate an optional raw Red ADC count. TH: ตรวจ raw ADC ของ Red หากส่งมา
    _validate_optional_adc(sensor, "ir_adc_mean", errors)  # EN: Validate an optional raw IR ADC count. TH: ตรวจ raw ADC ของ IR หากส่งมา
    _validate_optional_device_timestamp_ms(sensor, "device_timestamp_ms", errors)  # EN: Check device time type and Firestore-safe range when supplied. TH: ตรวจชนิดเวลาอุปกรณ์และช่วงที่ Firestore รองรับเมื่อมีการส่ง
    _validate_optional_percentage(event, "battery", errors)  # EN: Validate the optional battery percentage. TH: ตรวจเปอร์เซ็นต์แบตเตอรี่หากส่งมา
    if "riskResult" in event:  # EN: Validate optional AI/risk metadata when supplied. TH: ตรวจ metadata AI/risk เมื่อมีการส่งมา
        _validate_risk_result(event.get("riskResult"), errors, "riskResult")  # EN: Validate an included risk result. TH: ตรวจ risk result เมื่อมีการแนบมา
    profile = event.get("userProfile")  # EN: Read identity and device metadata. TH: อ่านข้อมูลผู้ใช้และอุปกรณ์
    if not isinstance(profile, dict):  # EN: Require object-shaped account/device metadata. TH: บังคับ metadata บัญชี/อุปกรณ์เป็น object
        errors.append("userProfile must be an object")  # EN: Report malformed profile metadata. TH: แจ้งว่า metadata โปรไฟล์ผิดรูป
        profile = {}  # EN: Continue safely without indexing the malformed value. TH: ดำเนินการต่ออย่างปลอดภัยโดยไม่ index ค่าที่ผิดรูป
    if not str(profile.get("userId") or "").strip():  # EN: Require an authenticated user identifier in the event. TH: บังคับให้ event มีรหัสผู้ใช้ที่ยืนยันแล้ว
        errors.append("userProfile.userId is required")  # EN: Record a missing user identifier. TH: บันทึกข้อผิดพลาดเมื่อไม่มีรหัสผู้ใช้
    device_id_error = _device_id_error(profile.get("deviceId"))  # EN: Validate the device ID before path construction. TH: ตรวจ device ID ก่อนนำไปสร้าง path
    if device_id_error:  # EN: Add any device identifier problem to the error list. TH: เพิ่มปัญหา device ID ลงในรายการข้อผิดพลาด
        errors.append(device_id_error)  # EN: Preserve the validator's safe error message. TH: เก็บข้อความ error ที่ปลอดภัยจาก validator
    return errors  # EN: Return every issue found to the route. TH: คืนรายการปัญหาทั้งหมดให้ route


_SENSOR_DATA_FIELDS = frozenset(
    {  # EN: Define the sensor fields that the app currently serializes. TH: กำหนด field sensor ที่แอป serialize ใช้อยู่
        "heart_rate", "heartRate", "spo2", "ecg_rate", "ecgRate",
        "ecg_rr_interval", "ecgRrInterval", "ecg_hrv", "ecgHrv", "gsr",
        "temperature", "accel_x", "accel_y", "accel_z", "gyro_x",
        "gyro_y", "gyro_z", "motion_magnitude", "gyro_magnitude",
        "red_adc_mean", "ir_adc_mean", "device_timestamp_ms",
    }  # EN: Close the allowlist so unknown keys are always discarded. TH: ปิด allowlist เพื่อทิ้ง key ที่ไม่รู้จักเสมอ
)
_RISK_RESULT_FIELDS = frozenset(
    {"riskClass", "alertLevel", "detectedSigns", "recommendation"}
)  # EN: Keep only the result fields shown or used by the app. TH: เก็บเฉพาะผลที่แอปแสดงหรือใช้งาน
_PROFILE_FIELDS = frozenset(
    {"userId", "deviceId"}
)  # EN: Exclude personal profile details from event storage. TH: ไม่นำข้อมูลส่วนตัวอื่นใน profile ไปเก็บกับ event


def _pick_fields(value: Any, allowed: frozenset[str]) -> dict[str, Any]:  # EN: Keep only allowlisted keys from an input mapping. TH: เก็บเฉพาะ key ที่อนุญาตจาก mapping ขาเข้า
    # EN: Copy allowlisted keys only from a parsed JSON object. TH: คัดลอกเฉพาะ key ที่อนุญาตจาก JSON object ที่ parse แล้ว
    if not isinstance(value, dict):  # EN: Fail closed for unexpected nested values. TH: ปฏิเสธแบบปลอดภัยเมื่อ nested value ผิดชนิด
        return {}  # EN: Return an empty object instead of persisting arbitrary input. TH: คืน object ว่างแทนการบันทึก input ที่ไม่รู้จัก
    return {key: value[key] for key in allowed if key in value}  # EN: Preserve present supported fields and drop all others. TH: คง field ที่รองรับและมีค่า พร้อมทิ้ง field อื่นทั้งหมด


def _sanitize_profile(profile: Any) -> dict[str, Any]:  # EN: Reduce profile data to the supported safe fields. TH: ลดข้อมูล profile ให้เหลือ field ปลอดภัยที่รองรับ
    # EN: Retain only server-bound identity and the validated device identifier. TH: เก็บเฉพาะ identity ที่ server ผูกให้และ device ID ที่ตรวจแล้ว
    return _pick_fields(profile, _PROFILE_FIELDS)  # EN: Drop names, age, contact, and other profile details. TH: ตัดชื่อ อายุ ช่องทางติดต่อ และรายละเอียดโปรไฟล์อื่น


def _sanitize_sensor_data(sensor: Any) -> dict[str, Any]:  # EN: Retain only validated sensor values. TH: เก็บเฉพาะค่า sensor ที่ผ่านการตรวจ
    # EN: Keep only recognized physiological, motion, and raw ADC measurements. TH: เก็บเฉพาะค่าชีวสัญญาณ การเคลื่อนไหว และ raw ADC ที่รู้จัก
    return _pick_fields(sensor, _SENSOR_DATA_FIELDS)  # EN: Discard any client-supplied nested extras. TH: ทิ้งข้อมูลเสริม nested ที่ client ส่งมา


def _sanitize_risk_result(result: Any) -> dict[str, Any]:  # EN: Retain only validated risk-result fields. TH: เก็บเฉพาะ field ผลความเสี่ยงที่ผ่านการตรวจ
    # EN: Retain the bounded risk fields checked by the validator. TH: เก็บ field risk ที่ validator จำกัดค่าแล้ว
    return _pick_fields(result, _RISK_RESULT_FIELDS)  # EN: Exclude arbitrary nested result metadata. TH: ตัด metadata ผลลัพธ์ที่ไม่กำหนด


def _sanitize_sensor_event(event: dict[str, Any]) -> dict[str, Any]:  # EN: Create a storage-safe copy of a sensor event. TH: สร้างสำเนา sensor event ที่ปลอดภัยสำหรับจัดเก็บ
    # EN: Build the minimal sensor event after validation has succeeded. TH: สร้าง sensor event ขั้นต่ำหลังผ่าน validation
    clean = {key: event[key] for key in ("timestamp", "battery") if key in event}  # EN: Keep only event time and validated battery metadata. TH: เก็บเฉพาะเวลา event และ battery ที่ตรวจแล้ว
    clean["sensorData"] = _sanitize_sensor_data(event.get("sensorData"))  # EN: Replace measurements with their allowlisted form. TH: แทนค่าการวัดด้วยชุด field ที่อนุญาต
    clean["userProfile"] = _sanitize_profile(event.get("userProfile"))  # EN: Remove unrelated profile data. TH: ลบข้อมูลโปรไฟล์ที่ไม่เกี่ยวข้อง
    if "riskResult" in event:  # EN: Preserve a risk result only when supplied. TH: เก็บ risk result เฉพาะเมื่อ client ส่งมา
        clean["riskResult"] = _sanitize_risk_result(event["riskResult"])  # EN: Keep only known risk fields. TH: เก็บเฉพาะ field risk ที่รู้จัก
    for key in ("bleStatus", "sensorStatus"):  # EN: Consider the two bounded status strings used by the app. TH: ตรวจ status string สองรายการที่แอปใช้งาน
        value = event.get(key)  # EN: Read each optional client status. TH: อ่านสถานะจาก client ทีละรายการ
        if isinstance(value, str) and len(value) <= 64:  # EN: Keep only short textual status values. TH: เก็บเฉพาะสถานะข้อความที่มีความยาวไม่เกินกำหนด
            clean[key] = value  # EN: Preserve a safe status for diagnostics. TH: คงสถานะที่ปลอดภัยไว้เพื่อดูสถานะระบบ
    return clean  # EN: Return the minimized validated event. TH: คืน event ที่ผ่านการลดข้อมูล


def _sanitize_alert_event(event: dict[str, Any]) -> dict[str, Any]:  # EN: Create a storage-safe copy of an alert event. TH: สร้างสำเนา alert event ที่ปลอดภัยสำหรับจัดเก็บ
    # EN: Build a minimal alert event without unrelated personal metadata. TH: สร้าง alert event ขั้นต่ำโดยไม่เก็บข้อมูลส่วนตัวที่ไม่เกี่ยวข้อง
    alert_value = event.get("alert")  # EN: Read the validated alert object. TH: อ่าน alert object ที่ผ่านการตรวจแล้ว
    clean_alert = _pick_fields(alert_value, frozenset({"id", "timestamp", "userResponse"}))  # EN: Keep alert identity, time, and user response only. TH: เก็บเฉพาะรหัส เวลา และคำตอบของผู้ใช้
    if isinstance(alert_value, dict) and "sensorData" in alert_value:  # EN: Keep an optional associated sensor snapshot. TH: เก็บ snapshot sensor ที่แนบมาเมื่อมี
        clean_alert["sensorData"] = _sanitize_sensor_data(alert_value["sensorData"])  # EN: Minimize the nested sensor object. TH: ลด field ใน sensor object ที่ซ้อนอยู่
    if isinstance(alert_value, dict) and "riskResult" in alert_value:  # EN: Keep an optional associated risk result. TH: เก็บผล risk ที่แนบมาเมื่อมี
        clean_alert["riskResult"] = _sanitize_risk_result(alert_value["riskResult"])  # EN: Minimize the nested result object. TH: ลด field ในผลลัพธ์ที่ซ้อนอยู่
    return {"alert": clean_alert, "userProfile": _sanitize_profile(event.get("userProfile"))}  # EN: Return only the alert and minimal owner/device metadata. TH: คืนเฉพาะ alert กับ metadata เจ้าของและอุปกรณ์ขั้นต่ำ


def _device_id_error(value: Any) -> Optional[str]:  # EN: Validate a device ID before using it as a database path segment. TH: ตรวจ device ID ก่อนนำไปใช้เป็น path segment ของฐานข้อมูล
    """Validate the client device ID before using it in a Firestore path."""
    if not isinstance(value, str) or not value.strip():  # EN: Require a non-empty text identifier. TH: บังคับรหัสเป็นข้อความที่ไม่ว่าง
        return "userProfile.deviceId is required"  # EN: Report absent or wrongly typed identifiers. TH: แจ้งเมื่อไม่มีรหัสหรือชนิดข้อมูลผิด
    # EN: Firestore path segments cannot contain slash and must stay bounded.
    # TH: segment ของ Firestore ห้ามมี slash และจำกัดความยาวก่อนใช้เป็น path
    if (  # EN: Reject long, padded, slash-containing, or control-character IDs. TH: ปฏิเสธ ID ที่ยาว มีช่องว่างหัวท้าย มี slash หรืออักขระควบคุม
        len(value) > 128  # EN: Bound ID length before storing or using it in paths. TH: จำกัดความยาวก่อนบันทึกหรือใช้ใน path
        or value != value.strip()  # EN: Reject leading or trailing whitespace. TH: ปฏิเสธช่องว่างหัวหรือท้าย
        or "/" in value  # EN: Prevent the value from creating extra path segments. TH: ป้องกันค่าทำให้เกิด path segment เพิ่ม
        or any(ord(character) < 0x20 for character in value)  # EN: Reject ASCII control characters. TH: ปฏิเสธอักขระควบคุม ASCII
    ):  # EN: Finish checking the unsafe device-ID forms. TH: จบการตรวจรูปแบบ device ID ที่ไม่ปลอดภัย
        return "userProfile.deviceId has an invalid format"  # EN: Return a fixed validation message without echoing input. TH: คืนข้อความตรวจแบบคงที่โดยไม่สะท้อน input
    return None  # EN: Signal that the identifier passed validation. TH: แจ้งว่ารหัสผ่านการตรวจแล้ว


def _validate_optional_timestamp(  # EN: Check one optional timestamp and append a safe error on failure. TH: ตรวจ timestamp ที่เป็นตัวเลือกหนึ่งค่าและเพิ่ม error ที่ปลอดภัยเมื่อผิด
    data: dict[str, Any],  # EN: Read the parsed object containing the timestamp. TH: อ่าน object ที่ parse แล้วซึ่งมี timestamp
    key: str,  # EN: Select the timestamp field name. TH: ระบุชื่อ field timestamp
    errors: list[str],  # EN: Append validation messages to the shared error list. TH: เพิ่มข้อความตรวจลงในรายการ error ร่วม
    *, prefix: str = ""  # EN: Prefix nested field paths for clear validation output. TH: เติม prefix path field ที่ซ้อนเพื่อให้ error ชัดเจน
) -> None:  # EN: Validate in place without returning or rewriting the input. TH: ตรวจข้อมูลโดยไม่คืนค่าหรือเขียนทับ input
    # EN: Validate an optional ISO-8601 timestamp without rewriting its source value.
    # TH: ตรวจ timestamp แบบ ISO-8601 ที่เป็นตัวเลือกโดยไม่แก้ค่าต้นทาง
    if key not in data or data[key] is None:  # EN: Skip absent optional timestamps. TH: ข้าม timestamp ที่เป็นตัวเลือกและไม่มีค่า
        return  # EN: Do not add an error for a field the caller omitted. TH: ไม่เพิ่ม error เมื่อ caller ไม่ส่ง field นี้
    value = data[key]  # EN: Read the untrusted timestamp value. TH: อ่าน timestamp ที่ยังไม่เชื่อถือ
    field = f"{prefix}{key}"  # EN: Build the safe field name used in validation errors. TH: สร้างชื่อ field สำหรับข้อความ validation
    if not isinstance(value, str) or not value or len(value) > 64:  # EN: Require a nonempty timestamp string within the parser bound. TH: บังคับ timestamp เป็นข้อความไม่ว่างและไม่เกินขนาด parser
        errors.append(f"{field} must be a valid timestamp string")  # EN: Reject non-text, empty, or oversized timestamps. TH: ปฏิเสธ timestamp ที่ไม่ใช่ข้อความ ว่าง หรือยาวเกิน
        return  # EN: Stop before invoking the date parser. TH: หยุดก่อนเรียกตัวแปลงวันที่
    try:  # EN: Parse supported ISO-8601 text without changing the stored value. TH: parse ข้อความ ISO-8601 ที่รองรับโดยไม่แก้ค่าที่จะจัดเก็บ
        datetime.fromisoformat(value.replace("Z", "+00:00"))  # EN: Parse UTC Z suffixes and ISO-8601 forms. TH: แปลงรูปแบบ ISO-8601 และ suffix UTC Z
    except ValueError:  # EN: Convert parser failures into a normal validation error. TH: แปลง parser failure ให้เป็น validation error ปกติ
        errors.append(f"{field} must be a valid timestamp string")  # EN: Record the parse failure without echoing input. TH: บันทึกว่าผิดรูปโดยไม่สะท้อน input กลับ


def _validate_optional_adc(data: dict[str, Any], key: str, errors: list[str]) -> None:  # EN: Validate one optional raw MAX30102 ADC channel. TH: ตรวจ raw ADC channel ของ MAX30102 ที่เป็นตัวเลือกหนึ่งค่า
    # EN: Accept MAX30102 raw ADC fields only as integer counts in the 18-bit range.
    # TH: รับค่า ADC ดิบของ MAX30102 เฉพาะจำนวนเต็มในช่วง 18 บิต
    if key not in data or data[key] is None:  # EN: Permit omitted optional raw channels. TH: อนุญาตให้ไม่ส่ง raw channel ที่เป็นตัวเลือก
        return  # EN: Skip validation when no ADC count was supplied. TH: ข้ามการตรวจเมื่อไม่ได้ส่งค่า ADC
    value = data[key]  # EN: Read the client-supplied ADC count. TH: อ่านจำนวน ADC ที่ client ส่งมา
    if isinstance(value, bool) or not isinstance(value, int):  # EN: Exclude booleans even though Python treats them as integers. TH: ปฏิเสธ boolean แม้ Python จะถือว่าเป็นจำนวนเต็ม
        errors.append(f"{key} must be an integer ADC count")  # EN: Reject booleans, floats, and strings. TH: ปฏิเสธ boolean, float และ string
        return  # EN: Stop before comparing an invalid type with the ADC range. TH: หยุดก่อนเทียบชนิดข้อมูลผิดกับช่วง ADC
    if value < 0 or value > MAX_MAX30102_ADC:  # EN: Enforce the unsigned 18-bit ADC limits. TH: บังคับขอบเขต ADC unsigned 18 บิต
        errors.append(f"{key} must be between 0 and {MAX_MAX30102_ADC}")  # EN: Reject counts outside the 18-bit ADC range. TH: ปฏิเสธ count นอกช่วง ADC 18 บิต


def _validate_optional_percentage(  # EN: Validate one optional whole-number percentage. TH: ตรวจเปอร์เซ็นต์จำนวนเต็มที่เป็นตัวเลือกหนึ่งค่า
    data: dict[str, Any],  # EN: Read the parsed source object. TH: อ่าน object ต้นทางที่ parse แล้ว
    key: str,  # EN: Select the percentage field. TH: ระบุ field เปอร์เซ็นต์
    errors: list[str],  # EN: Append any failure to the shared errors. TH: เพิ่มข้อผิดพลาดลงในรายการร่วม
) -> None:  # EN: Validate in place and return no transformed value. TH: ตรวจโดยไม่แปลงหรือคืนค่าข้อมูล
    # EN: Validate an optional battery percentage as a whole number from 0 to 100.
    # TH: ตรวจเปอร์เซ็นต์แบตเตอรี่ที่เป็นตัวเลือกให้เป็นจำนวนเต็ม 0 ถึง 100
    if key not in data or data[key] is None:  # EN: Permit a missing optional battery reading. TH: อนุญาตให้ไม่มีค่าแบตเตอรี่ที่เป็นตัวเลือก
        return  # EN: Skip checks when battery percentage was not reported. TH: ข้ามเมื่ออุปกรณ์ไม่ได้รายงานเปอร์เซ็นต์แบตเตอรี่
    value = data[key]  # EN: Read the reported battery value. TH: อ่านค่าแบตเตอรี่ที่รายงาน
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= 100:  # EN: Require an integer and exclude booleans and values outside 0–100. TH: บังคับจำนวนเต็มและปฏิเสธ boolean กับค่านอกช่วง 0–100
        errors.append(f"{key} must be an integer percentage from 0 to 100")  # EN: Require an integer percentage in range. TH: บังคับเปอร์เซ็นต์เป็นจำนวนเต็มในช่วงที่กำหนด


def _validate_optional_device_timestamp_ms(  # EN: Validate an optional monotonic device timestamp before persistence. TH: ตรวจ timestamp monotonic จากอุปกรณ์ที่เป็นตัวเลือกก่อนบันทึก
    data: dict[str, Any],  # EN: Read the nested sensor-data mapping. TH: อ่าน mapping sensor-data ที่ซ้อนอยู่
    key: str,  # EN: Select the device timestamp field. TH: ระบุ field timestamp ของอุปกรณ์
    errors: list[str],  # EN: Append failures to the caller's shared validation list. TH: เพิ่มข้อผิดพลาดลงในรายการตรวจร่วมของ caller
) -> None:  # EN: Validate in place without converting the timestamp. TH: ตรวจข้อมูลโดยไม่แปลง timestamp
    if key not in data or data[key] is None:  # EN: Keep the field optional for older app and firmware versions. TH: คง field เป็นตัวเลือกเพื่อรองรับแอปและ firmware รุ่นเก่า
        return  # EN: Skip checks when device time was not supplied. TH: ข้ามการตรวจเมื่อไม่ได้ส่งเวลาอุปกรณ์
    value = data[key]  # EN: Read the untrusted device timestamp. TH: อ่าน timestamp อุปกรณ์ที่ยังไม่เชื่อถือ
    if (  # EN: Require a non-negative integer within the database's supported range. TH: บังคับจำนวนเต็มไม่ติดลบและอยู่ในช่วงที่ฐานข้อมูลรองรับ
        isinstance(value, bool)  # EN: Reject booleans even though Python treats them as integers. TH: ปฏิเสธ boolean แม้ Python จะจัดเป็นจำนวนเต็ม
        or not isinstance(value, int)  # EN: Reject floats, strings, and nested JSON values. TH: ปฏิเสธ float, string และ JSON value แบบซ้อน
        or value < 0  # EN: Monotonic device time must not be negative. TH: เวลา monotonic ของอุปกรณ์ต้องไม่ติดลบ
        or value > MAX_DEVICE_TIMESTAMP_MS  # EN: Keep values representable by Firestore int64. TH: จำกัดค่าให้อยู่ในช่วง int64 ที่ Firestore บันทึกได้
    ):  # EN: Finish checking both type and supported range. TH: จบการตรวจชนิดและช่วงค่าที่รองรับ
        errors.append(f"{key} must be a non-negative integer timestamp in milliseconds")  # EN: Return a fixed message without echoing input. TH: คืนข้อความคงที่โดยไม่สะท้อน input


def _validate_risk_result(value: Any, errors: list[str], path: str) -> None:  # EN: Validate risk fields while collecting path-specific errors. TH: ตรวจ field ความเสี่ยงพร้อมรวบรวมข้อผิดพลาดตาม path
    # EN: Validate only fields that are present, preserving partial legacy records.
    # TH: ตรวจ field ที่ส่งมาเท่านั้นเพื่อคงการรองรับ record รุ่นเก่าที่มีข้อมูลบางส่วน
    if not isinstance(value, dict):  # EN: Require an object before reading risk fields. TH: บังคับเป็น object ก่อนอ่าน field risk
        errors.append(f"{path} must be an object")  # EN: Report a schema error to the caller. TH: แจ้ง schema error กลับ caller
        return  # EN: Avoid subscripting a malformed value. TH: ป้องกันการ index ค่าที่ผิดรูป
    allowed_levels = {"Safe", "Watch", "Warning", "Emergency", "Unknown"}  # EN: Allow only alert levels recognized by this API version. TH: อนุญาตเฉพาะระดับเตือนที่ API รุ่นนี้รู้จัก
    if "alertLevel" in value:  # EN: Validate the level only when supplied. TH: ตรวจระดับเมื่อมีการส่งมา
        level = value["alertLevel"]  # EN: Read the untrusted class-to-alert mapping. TH: อ่าน mapping class-to-alert ที่ยังไม่เชื่อถือ
        if not isinstance(level, str) or level not in allowed_levels:  # EN: Reject malformed or unsupported alert levels. TH: ปฏิเสธระดับเตือนที่ผิดชนิดหรือไม่รองรับ
            errors.append(f"{path}.alertLevel is invalid")  # EN: Reject unknown or non-text statuses. TH: ปฏิเสธสถานะที่ไม่รู้จักหรือไม่ใช่ข้อความ
    risk_class = value.get("riskClass")  # EN: Read the optional model class label. TH: อ่าน class label ของโมเดลที่เป็นตัวเลือก
    if risk_class is not None and (  # EN: Validate optional class labels without requiring legacy fields. TH: ตรวจ class label ที่เป็นตัวเลือกโดยไม่บังคับ field รุ่นเก่า
        not isinstance(risk_class, str) or len(risk_class) > 80  # EN: Require short text instead of arbitrary nested data. TH: บังคับเป็นข้อความสั้น ไม่รับข้อมูลซ้อนโดยพลการ
    ):  # EN: Finish the optional class-label validation condition. TH: จบเงื่อนไขตรวจ class label ที่เป็นตัวเลือก
        errors.append(f"{path}.riskClass is invalid")  # EN: Keep oversized or non-text labels out of storage. TH: กัน label ที่ไม่ใช่ข้อความหรือยาวเกินออกจาก storage
    recommendation = value.get("recommendation")  # EN: Read the optional user-facing recommendation. TH: อ่านคำแนะนำที่จะแสดงแก่ผู้ใช้
    if recommendation is not None and (  # EN: Bound optional recommendation text. TH: จำกัดข้อความคำแนะนำที่เป็นตัวเลือก
        not isinstance(recommendation, str) or len(recommendation) > 1000  # EN: Bound text type and length. TH: จำกัดชนิดและความยาวข้อความ
    ):  # EN: Finish the recommendation type-and-length check. TH: จบการตรวจชนิดและความยาวคำแนะนำ
        errors.append(f"{path}.recommendation is invalid")  # EN: Prevent arbitrary large advice text from being persisted. TH: ป้องกันการบันทึกข้อความคำแนะนำขนาดใหญ่โดยไม่จำกัด
    signs = value.get("detectedSigns")  # EN: Read the optional evidence strings. TH: อ่านข้อความหลักฐานที่เป็นตัวเลือก
    if signs is not None and (  # EN: Validate the evidence list only when present. TH: ตรวจรายการหลักฐานเมื่อมีการส่งมา
        not isinstance(signs, list)  # EN: Require a list-shaped evidence collection. TH: บังคับรายการหลักฐานเป็น list
        or len(signs) > 16  # EN: Cap the number of evidence entries. TH: จำกัดจำนวนรายการหลักฐาน
        or any(not isinstance(sign, str) or len(sign) > 160 for sign in signs)  # EN: Bound each entry to short plain text. TH: จำกัดแต่ละรายการให้เป็นข้อความธรรมดาความยาวสั้น
    ):  # EN: Finish validation of the bounded evidence-list structure. TH: จบการตรวจโครงสร้างรายการหลักฐานที่จำกัดขนาด
        errors.append(f"{path}.detectedSigns is invalid")  # EN: Bound evidence count and each text item. TH: จำกัดจำนวนหลักฐานและความยาวข้อความแต่ละรายการ


def _validate_partial_sensor_data(
    sensor: dict[str, Any], errors: list[str]  # EN: Accept the partial sensor object and shared error list. TH: รับ sensor object บางส่วนและรายการ error ร่วม
) -> None:  # EN: Validate fields only when a legacy/current event includes them. TH: ตรวจเฉพาะ field ที่ event รุ่นเก่าหรือปัจจุบันส่งมา
    # EN: Validate any sensor fields included in a legacy or current alert record.
    # TH: ตรวจ field sensor ทุกตัวที่แนบมากับ alert รุ่นเก่าหรือรุ่นปัจจุบัน
    bounded_fields = (  # EN: Define known physiological fields and accepted bounds. TH: กำหนด field สรีรวิทยาและขอบเขตที่ยอมรับ
        ("heart_rate", "heartRate", 0, 240),  # EN: Accept both current and legacy heart-rate keys. TH: รองรับ key ชีพจรทั้งชื่อปัจจุบันและชื่อเดิม
        ("spo2", None, 0, 100),  # EN: Bound oxygen percentage. TH: จำกัดเปอร์เซ็นต์ออกซิเจน
        ("ecg_rate", "ecgRate", 0, 240),  # EN: Accept current/legacy ECG rate fields. TH: รองรับ field อัตรา ECG ปัจจุบัน/เดิม
        ("ecg_rr_interval", "ecgRrInterval", 0, 3000),  # EN: Bound RR interval in milliseconds. TH: จำกัดช่วง RR หน่วยมิลลิวินาที
        ("ecg_hrv", "ecgHrv", 0, 500),  # EN: Bound the HRV summary. TH: จำกัดค่าสรุป HRV
        ("gsr", None, 0, 1000),  # EN: Bound the GSR reading. TH: จำกัดค่าการอ่าน GSR
        ("temperature", None, 20, 45),  # EN: Bound temperature in Celsius. TH: จำกัดอุณหภูมิหน่วยเซลเซียส
    )  # EN: Finish the allowed partial physiological field schema. TH: จบ schema field สรีรวิทยาที่อนุญาต
    for key, fallback_key, minimum, maximum in bounded_fields:  # EN: Visit each known bounded field. TH: ตรวจ field ทุกตัวที่กำหนดขอบเขต
        if key in sensor or (fallback_key is not None and fallback_key in sensor):  # EN: Validate only fields present in this partial record. TH: ตรวจเฉพาะ field ที่มีอยู่ใน record บางส่วนนี้
            _require_range(errors, sensor, key, fallback_key, minimum, maximum)  # EN: Enforce the configured numeric interval. TH: บังคับช่วงตัวเลขตามค่าที่กำหนด
    numeric_fields = (  # EN: List motion fields with a magnitude ceiling. TH: ระบุ field การเคลื่อนไหวที่ต้องมีเพดานขนาด
        "accel_x",  # EN: Include X-axis acceleration if present. TH: รวมความเร่งแกน X เมื่อมี
        "accel_y",  # EN: Include Y-axis acceleration if present. TH: รวมความเร่งแกน Y เมื่อมี
        "accel_z",  # EN: Include Z-axis acceleration if present. TH: รวมความเร่งแกน Z เมื่อมี
        "gyro_x",  # EN: Include X-axis angular rate if present. TH: รวมอัตราการหมุนแกน X เมื่อมี
        "gyro_y",  # EN: Include Y-axis angular rate if present. TH: รวมอัตราการหมุนแกน Y เมื่อมี
        "gyro_z",  # EN: Include Z-axis angular rate if present. TH: รวมอัตราการหมุนแกน Z เมื่อมี
        "motion_magnitude",  # EN: Include the motion magnitude summary. TH: รวมค่าสรุปขนาดการเคลื่อนไหว
        "gyro_magnitude",  # EN: Include the gyro magnitude summary. TH: รวมค่าสรุปขนาด gyro
    )  # EN: Finish the optional motion-field list. TH: จบรายการ field การเคลื่อนไหวที่เป็นตัวเลือก
    for key in numeric_fields:  # EN: Check every known motion channel. TH: ตรวจช่องการเคลื่อนไหวที่รู้จักทุกช่อง
        if key in sensor:  # EN: Preserve support for partial legacy payloads. TH: รองรับ payload รุ่นเก่าที่มีข้อมูลเพียงบาง field
            _require_number(errors, sensor, key)  # EN: Require a finite value within the magnitude ceiling. TH: บังคับค่า finite ที่ไม่เกินเพดานขนาด
    _validate_optional_adc(sensor, "red_adc_mean", errors)  # EN: Validate Red ADC when present. TH: ตรวจ ADC ของ Red เมื่อมีค่า
    _validate_optional_adc(sensor, "ir_adc_mean", errors)  # EN: Validate IR ADC when present. TH: ตรวจ ADC ของ IR เมื่อมีค่า
    _validate_optional_device_timestamp_ms(sensor, "device_timestamp_ms", errors)  # EN: Validate optional device time before sanitizing and storing an alert. TH: ตรวจเวลาอุปกรณ์ก่อน sanitize และบันทึก alert


def _require_range(  # EN: Validate one required numeric measurement and its accepted bounds. TH: ตรวจค่าการวัดตัวเลขที่จำเป็นและขอบเขตที่ยอมรับ
    errors: list[str],  # EN: Collect a validation message instead of raising per field. TH: สะสมข้อความตรวจแทนการ raise แยกทุก field
    data: dict[str, Any],  # EN: Read values from the parsed JSON object. TH: อ่านค่าจาก JSON object ที่ parse แล้ว
    key: str,  # EN: Name the preferred current field. TH: ระบุชื่อ field ปัจจุบันที่ต้องการก่อน
    fallback_key: Optional[str],  # EN: Support one optional legacy field name. TH: รองรับชื่อ field รุ่นเก่าได้หนึ่งชื่อ
    minimum: float,  # EN: Set the inclusive lower bound. TH: กำหนดขอบเขตล่างแบบรวมขอบ
    maximum: float,  # EN: Set the inclusive upper bound. TH: กำหนดขอบเขตบนแบบรวมขอบ
):  # EN: Finish the helper signature. TH: จบ signature ของ helper
    value = _number(data.get(key) if data.get(key) is not None else data.get(fallback_key))  # EN: Parse the preferred key, falling back for legacy clients. TH: แปลง field หลักหรือใช้ชื่อสำรองสำหรับ client รุ่นเก่า
    if value is None:  # EN: Detect absent or invalid numeric input. TH: ตรวจ input ตัวเลขที่หายหรือไม่ถูกต้อง
        errors.append(f"{key} is required")  # EN: Report the required measurement. TH: แจ้งว่าค่าการวัดนี้จำเป็น
        return  # EN: Skip range comparisons for an invalid value. TH: ข้ามการเทียบช่วงเมื่อค่าไม่ถูกต้อง
    if value < minimum or value > maximum:  # EN: Reject values outside the accepted interval. TH: ปฏิเสธค่าที่อยู่นอกช่วงยอมรับ
        errors.append(f"{key} must be between {minimum:g} and {maximum:g}")  # EN: Report the permitted bounds. TH: แจ้งขอบเขตค่าที่อนุญาต


def _require_number(errors: list[str], data: dict[str, Any], key: str):  # EN: Require a finite numeric value for one sensor field. TH: บังคับค่าตัวเลข finite สำหรับ field sensor หนึ่งช่อง
    value = _number(data.get(key))  # EN: Parse the supplied value while rejecting bool and non-finite inputs. TH: แปลงค่าที่ส่งมาโดยปฏิเสธ bool และค่าที่ไม่ finite
    if value is None:  # EN: Detect missing or malformed values. TH: ตรวจค่าที่หายหรือผิดรูป
        errors.append(f"{key} is required")  # EN: Report the missing numeric field. TH: แจ้งว่าไม่มี field ตัวเลขที่ต้องใช้
    elif abs(value) > MAX_ABS_SENSOR_VALUE:  # EN: Bound extreme values that may overflow downstream processing. TH: จำกัดค่ารุนแรงที่อาจทำให้การประมวลผลถัดไปล้น
        errors.append(f"{key} exceeds the supported numeric magnitude")  # EN: Report the supported magnitude ceiling. TH: แจ้งเพดานขนาดตัวเลขที่ระบบรองรับ


def _number(value: Any) -> Optional[float]:  # EN: Convert supported finite numeric input while rejecting booleans. TH: แปลงค่าตัวเลข finite ที่รองรับและปฏิเสธ boolean
    try:  # EN: Convert only values that are not rejected by the schema guard. TH: แปลงเฉพาะค่าที่ยังไม่ถูก schema guard ปฏิเสธ
        if value is None or value == "" or isinstance(value, bool):  # EN: Reject absent values, blank text, and booleans. TH: ปฏิเสธค่าที่หาย ข้อความว่าง และ boolean
            return None  # EN: Use None as the invalid-number sentinel. TH: ใช้ None แทนค่าตัวเลขที่ไม่ถูกต้อง
        number = float(value)  # EN: Convert supported numeric strings and numbers to float. TH: แปลง string ตัวเลขและ numeric เป็น float
        return number if math.isfinite(number) else None  # EN: Reject NaN and infinity. TH: ปฏิเสธ NaN และ infinity
    except (OverflowError, TypeError, ValueError):  # EN: Convert conversion failures into a validation result. TH: เปลี่ยนข้อผิดพลาดการแปลงให้เป็นผลตรวจข้อมูล
        return None  # EN: Keep malformed input from escaping as an exception. TH: ป้องกัน input ผิดรูปหลุดเป็น exception


def _write_firestore(collection: str, event: dict[str, Any]) -> bool:  # EN: Store an authenticated sanitized event in Firestore. TH: บันทึก event ที่ sanitize และยืนยันเจ้าของแล้วลง Firestore
    if not _FIRESTORE_CLIENT:  # EN: Signal that no durable Firestore write occurred. TH: แจ้งว่ายังไม่ได้เขียนข้อมูลลง Firestore แบบถาวร
        return False  # EN: Let the caller label the accepted data as ephemeral memory. TH: ให้ caller ระบุว่าข้อมูลอยู่ใน memory ชั่วคราว
    profile = event.get("userProfile") or {}  # EN: Read the already-sanitized account/device metadata. TH: อ่าน metadata บัญชีและอุปกรณ์ที่ sanitize แล้ว
    user_id = str(profile.get("userId") or "unknown-user")  # EN: Select the verified owner assigned by the route. TH: ใช้เจ้าของที่ route ผูกจาก token ที่ยืนยันแล้ว
    device_id = str(profile.get("deviceId") or "unknown-device")  # EN: Select the validated device identifier. TH: ใช้รหัสอุปกรณ์ที่ผ่าน validation
    doc_id = f"{datetime.utcnow().strftime('%Y%m%d%H%M%S%f')}-{device_id}"  # EN: Build a time-sortable event document ID. TH: สร้าง document ID ที่เรียงตามเวลาได้
    try:  # EN: Convert provider/storage failures into a controlled API error. TH: แปลงข้อผิดพลาด provider/storage เป็น API error ที่ควบคุมได้
        user_document = _FIRESTORE_CLIENT.collection(  # EN: Scope records under this API's collection namespace. TH: จำกัด record ไว้ใน namespace collection ของ API นี้
            f"{FIRESTORE_COLLECTION_PREFIX}_{collection}"  # EN: Separate sensor and alert collections by prefix. TH: แยก collection sensor กับ alert ด้วย prefix
        ).document(user_id)  # EN: Partition the top-level record by authenticated user. TH: แยกเอกสารระดับบนตามผู้ใช้ที่ยืนยันแล้ว
        # EN: Seed the transactional registry once for accounts with legacy subcollections.
        # TH: เริ่ม registry ใน transaction จาก subcollection เก่าที่มีอยู่แล้ว
        root_snapshot = user_document.get()  # EN: Read the device registry before applying legacy migration. TH: อ่าน registry อุปกรณ์ก่อนพิจารณาย้ายข้อมูลเก่า
        registry = root_snapshot.to_dict() if root_snapshot.exists else None  # EN: Treat a missing user document as an absent registry. TH: ถือว่าไม่มี registry เมื่อไม่พบ user document
        if not isinstance(registry, dict) or not isinstance(  # EN: Check both registry object shape and device list shape. TH: ตรวจทั้งชนิด registry object และ list ของอุปกรณ์
            registry.get("device_ids"), list  # EN: Require the stored registry field to be a list. TH: บังคับ field registry ที่เก็บไว้ให้เป็น list
        ):  # EN: Detect users whose registry predates the bounded device list. TH: ตรวจผู้ใช้ที่ registry ยังเป็น schema รุ่นเก่า
            legacy_device_ids = {item.id for item in user_document.collections()}  # EN: Seed the device cap from existing subcollections. TH: ตั้งต้นเพดานอุปกรณ์จาก subcollection เดิม
        else:  # EN: Avoid listing legacy collections once the registry is valid. TH: ไม่ไล่รายการ collection เก่าเมื่อ registry ถูกต้องแล้ว
            legacy_device_ids = set()  # EN: Use no migration additions for a current registry. TH: ไม่เพิ่มค่า migration สำหรับ registry รุ่นปัจจุบัน
        event_document = user_document.collection(device_id).document(doc_id)  # EN: Prepare a document path under the authenticated user's device. TH: เตรียม path เอกสารใต้ user/device ที่ยืนยันแล้ว
        _persist_firestore_event(  # EN: Atomically enforce device limits and store the event. TH: บังคับเพดานอุปกรณ์และบันทึก event แบบ atomic
            user_document,  # EN: Pass the owner registry document into the transaction. TH: ส่งเอกสาร registry ของเจ้าของเข้า transaction
            event_document,  # EN: Pass the target event document reference. TH: ส่ง reference ของ event ปลายทาง
            device_id,  # EN: Pass the validated device ID for cap enforcement. TH: ส่ง device ID ที่ตรวจแล้วไปบังคับเพดาน
            event,  # EN: Persist only the sanitized event. TH: บันทึกเฉพาะ event ที่ sanitize แล้ว
            legacy_device_ids,  # EN: Include discovered IDs during legacy migration. TH: รวม device ID เก่าที่พบระหว่าง migration
        )  # EN: Finish the transactional write request. TH: จบคำขอเขียนแบบ transaction
    except HTTPException:  # EN: Preserve deliberate API statuses such as device-limit rejection. TH: คง HTTP status ที่ตั้งใจ เช่น ปฏิเสธเพราะ device เต็ม
        raise  # EN: Let the route return the original controlled error. TH: ส่ง controlled error เดิมกลับให้ route
    except Exception:  # EN: Hide unexpected provider details from the client. TH: ซ่อนรายละเอียด provider ที่ไม่คาดคิดจาก client
        # EN: Fail as unavailable without returning a false success or leaking event data.
        # TH: แจ้ง storage ใช้ไม่ได้ ไม่ตอบสำเร็จเท็จหรือเปิดเผยข้อมูล event
        raise HTTPException(  # EN: Report storage unavailability without exposing event data. TH: แจ้ง storage ใช้ไม่ได้โดยไม่เปิดเผย event
            status_code=503,  # EN: Use service-unavailable for a failed durable write. TH: ใช้ service-unavailable เมื่อเขียนข้อมูลถาวรไม่สำเร็จ
            detail="Persistent health-data storage write failed.",  # EN: Return a generic safe storage message. TH: ส่งข้อความ storage แบบทั่วไปที่ปลอดภัย
        ) from None  # EN: Do not attach provider exception text to the response. TH: ไม่แนบข้อความ exception จาก provider ไปกับ response
    return True  # EN: Confirm that the Firestore transaction completed. TH: ยืนยันว่า Firestore transaction สำเร็จ


def _persist_firestore_event(  # EN: Atomically register a device and persist its event. TH: ลงทะเบียนอุปกรณ์และบันทึก event แบบ atomic
    user_document: Any,  # EN: Reference the authenticated owner's device registry. TH: reference registry อุปกรณ์ของเจ้าของที่ยืนยันแล้ว
    event_document: Any,  # EN: Reference the destination event document. TH: reference เอกสาร event ปลายทาง
    device_id: str,  # EN: Supply the validated device ID for quota checks. TH: ส่ง device ID ที่ตรวจแล้วเพื่อตรวจ quota
    event: dict[str, Any],  # EN: Supply the sanitized event to store. TH: ส่ง event ที่ sanitize แล้วเพื่อบันทึก
    legacy_device_ids: set[str],  # EN: Include old subcollection IDs during registry migration. TH: รวม ID subcollection เก่าระหว่างย้าย registry
) -> None:  # EN: Store one event and update the registry atomically. TH: บันทึก event หนึ่งรายการและปรับ registry แบบ atomic
    """Transactionally enforce the per-account device cap and store one event."""
    if firestore is None or _FIRESTORE_CLIENT is None:  # EN: Require the SDK and configured client before starting a transaction. TH: ต้องมี SDK และ client ที่ตั้งค่าแล้วก่อนเริ่ม transaction
        raise HTTPException(status_code=503, detail="Persistent storage is unavailable.")  # EN: Fail closed when persistent storage cannot run. TH: ปิดการเขียนเมื่อ storage ถาวรใช้ไม่ได้

    @firestore.transactional  # EN: Let Firestore retry this function after transaction conflicts. TH: ให้ Firestore retry ฟังก์ชันนี้เมื่อ transaction conflict
    def persist(transaction):  # EN: Define one retryable transaction for registry and event writes. TH: กำหนด transaction ที่ retry ได้สำหรับ registry และ event
        # EN: Read registry in the transaction so concurrent workers serialize updates.
        # TH: อ่าน registry ใน transaction เพื่อให้ worker ที่เขียนพร้อมกัน serialize กัน
        snapshot = user_document.get(transaction=transaction)  # EN: Read the current registry inside the transaction. TH: อ่าน registry ล่าสุดภายใน transaction
        raw_device_ids = snapshot.get("device_ids") if snapshot.exists else []  # EN: Treat a new account as having no registered devices. TH: ถือว่าบัญชีใหม่ยังไม่มีอุปกรณ์ลงทะเบียน
        registered_ids = (  # EN: Retain only string IDs from the stored registry. TH: เก็บเฉพาะ ID ชนิดข้อความจาก registry
            {item for item in raw_device_ids if isinstance(item, str)}  # EN: Keep only text IDs from the stored list. TH: เก็บเฉพาะ ID ข้อความจาก list ที่บันทึกไว้
            if isinstance(raw_device_ids, list)  # EN: Normalize only a valid list value. TH: normalize เฉพาะค่าที่เป็น list ถูกชนิด
            else set()  # EN: Treat invalid registry shapes as empty before merging known legacy IDs. TH: ถือ registry ที่ผิดรูปเป็นค่าว่างก่อนรวม ID เก่า
        )  # EN: Finish normalizing registered device IDs. TH: จบการ normalize device ID ที่ลงทะเบียน
        registered_ids.update(legacy_device_ids)  # EN: Count legacy subcollections during schema migration. TH: นับ subcollection เก่าระหว่าง migration schema
        if (  # EN: Check whether this write would exceed the account device cap. TH: ตรวจว่าการเขียนนี้ทำให้เกินเพดานอุปกรณ์หรือไม่
            device_id not in registered_ids  # EN: Existing devices do not consume an additional slot. TH: อุปกรณ์เดิมไม่ใช้ slot เพิ่ม
            and len(registered_ids) >= MAX_FIRESTORE_DEVICES_PER_USER  # EN: Reject a new device when the cap is already full. TH: ปฏิเสธอุปกรณ์ใหม่เมื่อเต็มเพดานแล้ว
        ):  # EN: Finish the device-cap condition. TH: จบเงื่อนไขเพดานอุปกรณ์
            raise HTTPException(  # EN: Refuse registration without altering stored state. TH: ปฏิเสธการลงทะเบียนโดยไม่เปลี่ยนข้อมูล
                status_code=429,  # EN: Mark the account-specific quota as exceeded. TH: ระบุว่า quota ของบัญชีเต็ม
                detail="This account has reached its registered device limit.",  # EN: Return a non-sensitive quota message. TH: ส่งข้อความ quota ที่ไม่เปิดเผยข้อมูล
            )  # EN: Stop before registering or writing the event. TH: หยุดก่อนลงทะเบียนหรือเขียน event
        registered_ids.add(device_id)  # EN: Include the current valid device in the registry. TH: เพิ่มอุปกรณ์ที่ตรวจแล้วลง registry
        transaction.set(user_document, {"device_ids": sorted(registered_ids)}, merge=True)  # EN: Persist the stable sorted registry in the transaction. TH: บันทึก registry ที่เรียงแล้วใน transaction
        transaction.set(event_document, event)  # EN: Write the sanitized event atomically with the registry. TH: เขียน event ที่ sanitize พร้อม registry แบบ atomic

    # EN: Firestore retries this transaction if another worker changes the registry.
    # TH: Firestore retry transaction เมื่อ worker อื่นแก้ registry พร้อมกัน
    persist(_FIRESTORE_CLIENT.transaction())  # EN: Execute the atomic registry-and-event transaction. TH: เรียก transaction ที่บันทึก registry และ event พร้อมกัน


def _read_firestore_events(  # EN: Read a bounded newest-first event history for one verified user. TH: อ่านประวัติ event ล่าสุดแบบจำกัดของผู้ใช้ที่ยืนยันแล้ว
    collection: str,  # EN: Select the sensor or alert event namespace. TH: เลือก namespace ของ sensor หรือ alert
    user_id: str,  # EN: Use only an identity verified by the request route. TH: ใช้เฉพาะ identity ที่ route ยืนยันแล้ว
    limit: int,  # EN: Bound the total number of events returned. TH: จำกัดจำนวน event รวมที่ส่งกลับ
    *,  # EN: Require per-device limit to be passed by name. TH: บังคับส่งเพดานต่ออุปกรณ์ด้วยชื่อ argument
    per_device_limit: Optional[int] = None,  # EN: Optionally tighten the read bound for each device. TH: ลดเพดานการอ่านต่ออุปกรณ์ได้
) -> list[dict[str, Any]]:  # EN: Return the newest verified events for this user. TH: คืน event ล่าสุดที่ตรวจเจ้าของแล้ว
    """Read the authenticated user's latest events across the bounded device set."""
    if not _FIRESTORE_CLIENT:  # EN: Require durable storage for authenticated history reads. TH: ต้องมี storage ถาวรสำหรับอ่านประวัติที่ยืนยันตัวตน
        raise HTTPException(status_code=503, detail="Persistent storage is unavailable.")  # EN: Do not fall back to another user's worker-local view. TH: ห้าม fallback ไปใช้ข้อมูลใน worker ที่อาจไม่ตรงผู้ใช้
    try:  # EN: Convert database failures into a controlled unavailable response. TH: แปลง database failure เป็น response unavailable ที่ควบคุมได้
        user_document = _FIRESTORE_CLIENT.collection(  # EN: Select the correct event namespace. TH: เลือก namespace ของ event ให้ถูกต้อง
            f"{FIRESTORE_COLLECTION_PREFIX}_{collection}"  # EN: Keep collection names isolated by the configured prefix. TH: แยกชื่อ collection ด้วย prefix ที่ตั้งไว้
        ).document(user_id)  # EN: Limit the query root to the verified user. TH: จำกัดราก query ให้เป็นผู้ใช้ที่ยืนยันแล้ว
        device_collections = list(user_document.collections())  # EN: Enumerate this user's registered event subcollections. TH: ไล่ subcollection event ของผู้ใช้นี้
        if len(device_collections) > MAX_FIRESTORE_DEVICES_PER_USER:  # EN: Fail closed if stored state exceeds the supported device bound. TH: ปิดการอ่านเมื่อข้อมูลเดิมเกินจำนวนอุปกรณ์ที่รองรับ
            raise HTTPException(  # EN: Avoid unbounded reads from unexpectedly large stored state. TH: หลีกเลี่ยงการอ่านไม่จำกัดจากข้อมูลเดิมที่ผิดคาด
                status_code=503,  # EN: Report a storage state requiring operator review. TH: แจ้ง storage state ที่ต้องให้ผู้ดูแลตรวจ
                detail="Stored device data exceeds the configured read limit.",  # EN: Keep internal collection details private. TH: ไม่เปิดเผยรายละเอียด collection ภายใน
            )  # EN: Stop before querying event documents. TH: หยุดก่อน query เอกสาร event
        events: list[tuple[str, dict[str, Any]]] = []  # EN: Buffer bounded candidate events with their document IDs. TH: เก็บ event ที่มีขอบเขตพร้อม document ID
        for device_collection in device_collections:  # EN: Query each device only after enforcing the collection cap. TH: query ทีละอุปกรณ์หลังบังคับเพดาน collection
            snapshots = (  # EN: Build a newest-first bounded query for this device. TH: สร้าง query ล่าสุดก่อนและจำกัดจำนวนต่ออุปกรณ์
                device_collection.order_by(  # EN: Start ordering this device's documents. TH: เริ่มเรียงเอกสารของอุปกรณ์นี้
                    "__name__", direction=firestore.Query.DESCENDING  # EN: Order by document ID, which embeds receipt time. TH: เรียงตาม document ID ซึ่งฝังเวลารับข้อมูล
                )  # EN: Finish the descending document-name order. TH: จบการเรียง document name จากใหม่ไปเก่า
                .limit(per_device_limit or limit)  # EN: Bound documents read from each device. TH: จำกัดจำนวนเอกสารที่อ่านต่ออุปกรณ์
                .stream()  # EN: Fetch only the query's bounded snapshot iterator. TH: ดึง iterator snapshot ตาม query ที่จำกัดแล้ว
            )  # EN: Finish query construction. TH: จบการสร้าง query
            for snapshot in snapshots:  # EN: Inspect each bounded document snapshot. TH: ตรวจ snapshot ของเอกสารที่ถูกจำกัดแล้วทีละรายการ
                event = snapshot.to_dict()  # EN: Decode the stored event mapping. TH: แปลง event ที่เก็บไว้ออกมาเป็น mapping
                if not isinstance(event, dict) or event.get("authUserId") != user_id:  # EN: Recheck owner and shape before returning stored data. TH: ตรวจ owner และชนิดข้อมูลซ้ำก่อนส่งข้อมูลกลับ
                    continue  # EN: Skip malformed or mismatched documents. TH: ข้ามเอกสารผิดรูปหรือ owner ไม่ตรง
                events.append((snapshot.id, event))  # EN: Keep the verified event with a stable tie-break ID. TH: เก็บ event ที่ยืนยันพร้อม ID สำหรับเรียงกรณีเวลาเท่ากัน
        events.sort(key=lambda item: (str(item[1].get("receivedAt", "")), item[0]))  # EN: Order merged events by receipt time and document ID. TH: เรียง event รวมตามเวลารับและ document ID
        return [event for _, event in events[-limit:]]  # EN: Return only the requested newest events. TH: คืนเฉพาะ event ล่าสุดตามจำนวนที่ขอ
    except HTTPException:  # EN: Preserve deliberate bounds and availability responses. TH: คง response ที่ตั้งใจสำหรับเพดานและสถานะระบบ
        raise  # EN: Let the route return the original HTTP error. TH: ส่ง HTTP error เดิมกลับ route
    except Exception:  # EN: Hide database internals and health payloads from clients. TH: ซ่อนรายละเอียด database และ payload สุขภาพจาก client
        # EN: Keep provider details and health data out of the HTTP error body.
        # TH: ไม่เปิดเผยรายละเอียด provider หรือข้อมูลสุขภาพใน body ของ error
        raise HTTPException(  # EN: Report a generic durable-read failure. TH: แจ้งความผิดพลาดการอ่าน storage ถาวรแบบทั่วไป
            status_code=503,  # EN: Mark the persistent storage as unavailable. TH: ระบุว่า storage ถาวรใช้งานไม่ได้
            detail="Persistent health-data storage read failed.",  # EN: Keep database details and health contents private. TH: ซ่อนรายละเอียด database และข้อมูลสุขภาพ
        ) from None  # EN: Do not expose provider exceptions through the response. TH: ไม่เปิดเผย exception provider ผ่าน response
