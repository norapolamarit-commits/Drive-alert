from datetime import datetime
from html import escape
import json
import math
import os
import re
from collections import Counter, OrderedDict, deque
from math import ceil
from threading import BoundedSemaphore, Lock
import time
from typing import Any, Optional
from urllib.parse import quote

import httpx
from fastapi import FastAPI, Header, HTTPException, Query, Request
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel, ConfigDict, Field

try:
    from google.cloud import firestore
except ImportError:
    firestore = None


app = FastAPI(title="doz Cloud API")

# EN: Bound incoming event bodies and per-worker in-memory history against RAM exhaustion.
# TH: จำกัด body event และประวัติใน RAM ของแต่ละ worker เพื่อป้องกันใช้หน่วยความจำจนหมด
MAX_CLOUD_EVENT_BYTES = 32 * 1024
MAX_AI_REQUEST_BYTES = 64 * 1024
MAX_IN_MEMORY_EVENTS = 1_000
MAX_FIRESTORE_DEVICES_PER_USER = 16


def _bounded_env_int(name: str, default: int, minimum: int, maximum: int) -> int:
    """Read a bounded integer setting. / อ่านจำนวนเต็มตามช่วงที่กำหนด"""
    # EN: Read the optional setting. TH: อ่านค่าที่ตั้งผ่าน environment
    raw_value = os.getenv(name)
    if raw_value is None:
        return default  # EN: Use default. TH: ใช้ค่าเริ่มต้น
    try:
        value = int(raw_value)  # EN: Parse integer. TH: แปลงเป็นจำนวนเต็ม
    except (TypeError, ValueError) as exc:
        # EN: Name the invalid setting without echoing its value. TH: แจ้งชื่อค่าโดยไม่แสดงค่าจริง
        raise ValueError(
            f"{name} must be an integer in {minimum}..{maximum}."
        ) from exc
    if not minimum <= value <= maximum:
        # EN: Reject out-of-range values. TH: ปฏิเสธค่านอกช่วง
        raise ValueError(f"{name} must be an integer in {minimum}..{maximum}.")
    return value  # EN: Return validated value. TH: คืนค่าที่ผ่านการตรวจ


def _bounded_env_float(
    name: str, default: float, minimum: float, maximum: float
) -> float:
    """Read a finite bounded float. / อ่านทศนิยม finite ที่อยู่ในช่วงกำหนด"""
    # EN: Read the optional setting. TH: อ่านค่าจาก environment
    raw_value = os.getenv(name)
    if raw_value is None:
        return default  # EN: Use default. TH: ใช้ค่าเริ่มต้น
    try:
        value = float(raw_value)  # EN: Parse float. TH: แปลงเป็นทศนิยม
    except (TypeError, ValueError) as exc:
        # EN: Do not echo configuration contents. TH: ไม่แสดงเนื้อหาของค่าตั้งต้นที่ผิด
        raise ValueError(
            f"{name} must be a finite number in {minimum}..{maximum}."
        ) from exc
    if not math.isfinite(value) or not minimum <= value <= maximum:
        # EN: Reject NaN, infinity, and out-of-range values. TH: ปฏิเสธ NaN, infinity และค่านอกช่วง
        raise ValueError(f"{name} must be a finite number in {minimum}..{maximum}.")
    return value  # EN: Return validated value. TH: คืนค่าที่ผ่านการตรวจ


@app.middleware("http")
async def limit_cloud_event_body(request: Request, call_next):
    # EN: Bound JSON request bytes before FastAPI parses event/chat/advice bodies.
    # TH: จำกัดขนาด JSON ก่อน FastAPI parse body ของ event/chat/advice
    body_limits = {
        "/sensor": MAX_CLOUD_EVENT_BYTES,
        "/alert": MAX_CLOUD_EVENT_BYTES,
        "/chat": MAX_AI_REQUEST_BYTES,
        "/advice": MAX_AI_REQUEST_BYTES,
    }
    body_limit = body_limits.get(request.url.path)
    if request.method == "POST" and body_limit is not None:
        raw_length = request.headers.get("content-length")
        if raw_length is None:
            return JSONResponse(
                status_code=411,
                content={"detail": "Content-Length is required for this request."},
            )
        try:
            body_length = int(raw_length)
        except ValueError:
            return JSONResponse(status_code=400, content={"detail": "Invalid Content-Length."})
        if body_length < 0 or body_length > body_limit:
            return JSONResponse(
                status_code=413,
                content={"detail": "Request body exceeds the endpoint size limit."},
            )
    return await call_next(request)


def _append_bounded_event(events: list[dict[str, Any]], event: dict[str, Any]) -> None:
    """Keep only the newest bounded in-process event history. / เก็บ event ล่าสุดใน RAM ตามเพดาน"""
    if len(events) >= MAX_IN_MEMORY_EVENTS:
        del events[: len(events) - MAX_IN_MEMORY_EVENTS + 1]
    events.append(event)

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


class CloudPayload(BaseModel):
    # EN: Keep forward-compatible event fields while using Pydantic v2 config.
    # TH: ยอมรับฟิลด์ event เพิ่มเติมเพื่อรองรับรุ่นใหม่ และใช้ config ของ Pydantic v2
    model_config = ConfigDict(extra="allow")


class ChatRequest(BaseModel):
    # Ignore client-only fields (including its requested model); the server owns
    # provider/model selection and bounds user-controlled content before billing.
    model_config = ConfigDict(extra="ignore")

    question: str = Field(min_length=1, max_length=2000)
    prompt: str = Field(min_length=1, max_length=10000)


class AdviceRequest(BaseModel):
    # Keep the advice payload bounded and prevent clients from selecting a provider model.
    model_config = ConfigDict(extra="ignore", populate_by_name=True)

    status: str = Field(min_length=1, max_length=80)
    alert_level: str = Field(default="", alias="alertLevel", max_length=40)
    sensor: str = Field(default="", max_length=2000)


def _verify_chat_user(authorization: Optional[str]) -> str:
    """Validate a Supabase access token; fail closed if auth is unavailable."""
    supabase_url = os.getenv("SUPABASE_URL", "").rstrip("/")
    supabase_key = os.getenv("SUPABASE_PUBLISHABLE_KEY") or os.getenv(
        "SUPABASE_ANON_KEY", ""
    )
    if not supabase_url or not supabase_key:
        raise HTTPException(
            status_code=503,
            detail="Chat authentication is not configured on this server.",
        )
    scheme, _, token = (authorization or "").partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise HTTPException(status_code=401, detail="Bearer access token required.")
    try:
        response = httpx.get(
            f"{supabase_url}/auth/v1/user",
            headers={
                "apikey": supabase_key,
                "Authorization": f"Bearer {token.strip()}",
            },
            timeout=5.0,
        )
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=503, detail="Authentication provider is unavailable."
        ) from exc
    if response.status_code in (401, 403):
        raise HTTPException(status_code=401, detail="Invalid or expired token.")
    if response.status_code < 200 or response.status_code >= 300:
        raise HTTPException(status_code=503, detail="Could not verify access token.")
    try:
        user_id = response.json().get("id")
    except (ValueError, AttributeError):
        user_id = None
    if not isinstance(user_id, str) or not user_id:
        raise HTTPException(status_code=401, detail="Invalid user identity.")
    return user_id


def _memory_health_storage_enabled() -> bool:
    """Return true only when an operator explicitly enables ephemeral storage."""
    value = os.getenv("HEALTH_DATA_MEMORY_STORAGE_ENABLED", "false")
    return value.strip().lower() in {"1", "true", "yes"}


def _require_health_data_sync_enabled() -> None:
    """Keep health-data routes closed until deployment review explicitly enables them."""
    enabled = os.getenv("HEALTH_DATA_SYNC_ENABLED", "false").strip().lower()
    if enabled not in {"1", "true", "yes"}:
        raise HTTPException(
            status_code=503,
            detail="Health-data sync is disabled on this deployment.",
        )
    # EN: Do not claim sync succeeded when only process memory is available.
    # TH: ห้ามแจ้งว่าสำเร็จเมื่อมีเพียงหน่วยความจำชั่วคราว เว้นแต่เปิด opt-in สำหรับพัฒนา
    if not _FIRESTORE_CLIENT and not _memory_health_storage_enabled():
        raise HTTPException(
            status_code=503,
            detail="Persistent health-data storage is unavailable.",
        )


def _enforce_ai_rate_limit(user_id: str, *, now: Optional[float] = None) -> None:
    """Limit verified accounts per process; return HTTP 429 with retry guidance."""
    current = time.monotonic() if now is None else now
    cutoff = current - AI_RATE_LIMIT_WINDOW_SECONDS
    with _AI_RATE_LIMIT_LOCK:
        # Expire this account's timestamps before checking the current window.
        requests = _AI_REQUEST_TIMES.get(user_id)
        if requests is None:
            # Reclaim expired identities and cap memory used by authenticated IDs.
            if len(_AI_REQUEST_TIMES) >= 10_000:
                for old_user_id, old_requests in list(_AI_REQUEST_TIMES.items()):
                    if not old_requests or old_requests[-1] <= cutoff:
                        _AI_REQUEST_TIMES.pop(old_user_id, None)
                        if len(_AI_REQUEST_TIMES) < 10_000:
                            break
            if len(_AI_REQUEST_TIMES) >= 10_000:
                raise HTTPException(
                    status_code=503,
                    detail="AI rate-limit capacity is temporarily full.",
                    headers={"Retry-After": str(AI_RATE_LIMIT_WINDOW_SECONDS)},
                )
            requests = deque()
            _AI_REQUEST_TIMES[user_id] = requests
        while requests and requests[0] <= cutoff:
            requests.popleft()
        if len(requests) >= AI_RATE_LIMIT_MAX:
            retry_after = max(
                1, ceil(AI_RATE_LIMIT_WINDOW_SECONDS - (current - requests[0]))
            )
            raise HTTPException(
                status_code=429,
                detail="AI request limit reached. Please wait before retrying.",
                headers={"Retry-After": str(retry_after)},
            )
        requests.append(current)
        _AI_REQUEST_TIMES.move_to_end(user_id)


@app.get("/health")
def health():
    # Public liveness checks must not disclose health-event counts or storage details.
    return {"status": "ok"}


@app.get("/")
def service_root():
    """Give the public service URL a minimal status response without exposing data."""
    return {"service": "doz Cloud API", "status": "ok", "health": "/health"}


@app.delete("/account", status_code=204)
def delete_account(authorization: Optional[str] = Header(default=None)):
    """Delete only the authenticated user's records and Supabase Auth account."""
    user_id = _verify_chat_user(authorization)
    supabase_url = os.getenv("SUPABASE_URL", "").rstrip("/")
    service_role_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not supabase_url or not service_role_key:
        raise HTTPException(
            status_code=503,
            detail="Account deletion is not configured on this server.",
        )

    # EN: Do not delete the identity when health records cannot be checked/deleted.
    # TH: ห้ามลบบัญชีเมื่อยังตรวจ/ลบข้อมูลสุขภาพใน persistent storage ไม่ได้
    if not _FIRESTORE_CLIENT and not _memory_health_storage_enabled():
        raise HTTPException(
            status_code=503,
            detail="Persistent health-data storage is unavailable for account deletion.",
        )

    # Health events are keyed by the verified user ID in Firestore subcollections.
    if _FIRESTORE_CLIENT:
        try:
            for collection in ("sensor_events", "alert_events"):
                root = _FIRESTORE_CLIENT.collection(
                    f"{FIRESTORE_COLLECTION_PREFIX}_{collection}"
                ).document(user_id)
                for device_collection in root.collections():
                    for event_document in device_collection.stream():
                        event_document.reference.delete()
                root.delete()
        except Exception as exc:
            raise HTTPException(
                status_code=503,
                detail="Could not remove account data from persistent storage.",
            ) from exc

    # Remove in-process records before deleting identity; retry remains safe.
    SENSOR_EVENTS[:] = [e for e in SENSOR_EVENTS if e.get("authUserId") != user_id]
    ALERT_EVENTS[:] = [e for e in ALERT_EVENTS if e.get("authUserId") != user_id]
    try:
        response = httpx.delete(
            f"{supabase_url}/auth/v1/admin/users/{quote(user_id, safe='')}",
            headers={
                "apikey": service_role_key,
                "Authorization": f"Bearer {service_role_key}",
            },
            timeout=10.0,
        )
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=503, detail="Account provider is unavailable."
        ) from exc
    if response.status_code < 200 or response.status_code >= 300:
        raise HTTPException(
            status_code=503, detail="Account provider did not confirm deletion."
        )
    return None


@app.get("/sensor")
def sensor_events(
    limit: int = Query(default=100, ge=1, le=500),
    authorization: Optional[str] = Header(default=None),
):
    user_id = _verify_chat_user(authorization)
    _require_health_data_sync_enabled()
    if _FIRESTORE_CLIENT:
        return _read_firestore_events("sensor_events", user_id, limit)
    events = [event for event in SENSOR_EVENTS if event.get("authUserId") == user_id]
    return events[-limit:]


@app.get("/alert")
def alert_events(
    limit: int = Query(default=100, ge=1, le=500),
    authorization: Optional[str] = Header(default=None),
):
    user_id = _verify_chat_user(authorization)
    _require_health_data_sync_enabled()
    if _FIRESTORE_CLIENT:
        return _read_firestore_events("alert_events", user_id, limit)
    events = [event for event in ALERT_EVENTS if event.get("authUserId") == user_id]
    return events[-limit:]


@app.get("/devices")
def devices(authorization: Optional[str] = Header(default=None)):
    user_id = _verify_chat_user(authorization)
    _require_health_data_sync_enabled()
    if _FIRESTORE_CLIENT:
        events = _read_firestore_events(
            "sensor_events",
            user_id,
            MAX_FIRESTORE_DEVICES_PER_USER,
            per_device_limit=1,
        )
    else:
        events = [event for event in SENSOR_EVENTS if event.get("authUserId") == user_id]
    latest: dict[str, dict[str, Any]] = {}
    for event in events:
        profile = event.get("userProfile") or {}
        device_id = str(profile.get("deviceId") or "unknown-device")
        if device_id not in latest or str(event.get("receivedAt", "")) > str(
            latest[device_id].get("receivedAt", "")
        ):
            latest[device_id] = event
    return list(latest.values())


def _is_local_request(request: Request) -> bool:
    client_host = request.client.host if request.client else ""
    # Never trust client-controlled X-Forwarded-For to authorize local dashboards.
    return client_host in {"127.0.0.1", "::1", "localhost", "testclient"}


def _local_only_response() -> HTMLResponse:
    return HTMLResponse(
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


def _dashboard_html() -> str:
    latest_by_device: dict[str, dict[str, Any]] = {}
    for event in SENSOR_EVENTS:
        profile = event.get("userProfile") or {}
        device_id = str(profile.get("deviceId") or "unknown-device")
        latest_by_device[device_id] = event

    rows = []
    for device_id, event in latest_by_device.items():
        profile = event.get("userProfile") or {}
        sensor = event.get("sensorData") or {}
        risk = event.get("riskResult") or {}
        rows.append(
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

    alert_rows = []
    for event in ALERT_EVENTS[-30:]:
        profile = event.get("userProfile") or {}
        alert_data = event.get("alert") or {}
        risk = alert_data.get("riskResult") or {}
        alert_rows.append(
            "<tr>"
            f"<td>{escape(str(profile.get('deviceId', 'unknown-device')))}</td>"
            f"<td>{escape(str(event.get('receivedAt', '-')))}</td>"
            f"<td>{escape(str(risk.get('riskClass', '-')))}</td>"
            f"<td>{escape(str(risk.get('alertLevel', '-')))}</td>"
            f"<td>{escape(str(alert_data.get('userResponse', 'Pending') or 'Pending'))}</td>"
            "</tr>"
        )

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


def _sensor_value(sensor: dict[str, Any], key: str, fallback_key: Optional[str] = None):
    value = sensor.get(key)
    if value is None and fallback_key:
        value = sensor.get(fallback_key)
    return "-" if value is None else value


@app.get("/dashboard", response_class=HTMLResponse)
def dashboard(request: Request):
    if not _is_local_request(request):
        return _local_only_response()
    return _dashboard_html()


@app.get("/local-dashboard", response_class=HTMLResponse)
def local_dashboard(request: Request):
    if not _is_local_request(request):
        return _local_only_response()
    return _dashboard_html()


@app.post("/sensor")
def sensor(
    payload: CloudPayload,
    authorization: Optional[str] = Header(default=None),
):
    user_id = _verify_chat_user(authorization)
    _require_health_data_sync_enabled()
    event = payload.model_dump()
    # EN: Bind ownership from verified auth before validation; never trust a client user ID.
    # TH: ใส่เจ้าของจาก token ที่ตรวจแล้วก่อน validate และไม่เชื่อ user ID ที่ client ส่ง
    profile = event.get("userProfile")
    if not isinstance(profile, dict):
        profile = {}
    profile["userId"] = user_id
    event["userProfile"] = profile
    errors = _validate_sensor_event(event)
    if errors:
        raise HTTPException(status_code=422, detail={"errors": errors})
    event["authUserId"] = user_id
    event["receivedAt"] = datetime.utcnow().isoformat()
    persisted = _write_firestore("sensor_events", event)
    _append_bounded_event(SENSOR_EVENTS, event)
    return {
        "ok": True,
        "stored": len(SENSOR_EVENTS),
        "storage": "firestore" if persisted else "memory-ephemeral",
    }


@app.post("/alert")
def alert(
    payload: CloudPayload,
    authorization: Optional[str] = Header(default=None),
):
    user_id = _verify_chat_user(authorization)
    _require_health_data_sync_enabled()
    event = payload.model_dump()
    profile = event.get("userProfile")
    if not isinstance(profile, dict):
        profile = {}
    profile["userId"] = user_id
    event["userProfile"] = profile
    device_id_error = _device_id_error(profile.get("deviceId"))
    if device_id_error:
        raise HTTPException(status_code=422, detail=device_id_error)
    event["authUserId"] = user_id
    event["receivedAt"] = datetime.utcnow().isoformat()
    persisted = _write_firestore("alert_events", event)
    _append_bounded_event(ALERT_EVENTS, event)
    return {
        "ok": True,
        "stored": len(ALERT_EVENTS),
        "storage": "firestore" if persisted else "memory-ephemeral",
    }


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
    "- ห้ามวินิจฉัยโรคแทนแพทย์ ถ้าเป็นเหตุฉุกเฉินรุนแรงให้แนะนำโทร 1669 ก่อนเป็นอันดับแรก"
)


def _ngrams(text: str, n: int = 3) -> list[str]:
    text = re.sub(r"\s+", "", text.lower())
    if len(text) < n:
        return [text] if text else []
    return [text[i : i + n] for i in range(len(text) - n + 1)]


class TfidfRetriever:
    """retriever แบบ char n-gram TF-IDF (pure python) — เหมาะภาษาไทยที่ไม่มีเว้นวรรค"""

    def __init__(self, docs: list[str]):
        self.docs = docs
        tokens = [Counter(_ngrams(d)) for d in docs]
        df: Counter = Counter()
        for c in tokens:
            df.update(c.keys())
        n = max(len(docs), 1)
        self.idf = {t: math.log((1 + n) / (1 + dft)) + 1 for t, dft in df.items()}
        self.vecs = [self._vec(c) for c in tokens]
        self.norms = [math.sqrt(sum(v * v for v in vec.values())) or 1.0 for vec in self.vecs]

    def _vec(self, counter: Counter) -> dict:
        return {t: tf * self.idf.get(t, 0.0) for t, tf in counter.items()}

    def search(self, query: str, k: int = 3) -> list[tuple[int, float]]:
        qv = self._vec(Counter(_ngrams(query)))
        qn = math.sqrt(sum(v * v for v in qv.values())) or 1.0
        scored = []
        for i, dv in enumerate(self.vecs):
            dot = sum(qv.get(t, 0.0) * val for t, val in dv.items())
            scored.append((i, dot / (qn * self.norms[i])))
        scored.sort(key=lambda x: x[1], reverse=True)
        return [(i, s) for i, s in scored[:k] if s > 0]


_KB_PATH = os.path.join(os.path.dirname(__file__), "knowledge.json")
try:
    with open(_KB_PATH, encoding="utf-8") as f:
        KB: list[dict[str, Any]] = json.load(f)
except Exception:
    KB = []
_RETRIEVER = TfidfRetriever([f"{e.get('q', '')} {e.get('a', '')}" for e in KB]) if KB else None


def _extract_question(prompt: str, explicit: str) -> str:
    if explicit and explicit.strip():
        return explicit.strip()
    m = re.search(r"(?:User question|คำถาม)\s*[:：]\s*(.+)", prompt, re.S)
    return (m.group(1) if m else prompt).strip()


def _retrieve(query: str) -> tuple[str, list[dict[str, Any]]]:
    if not _RETRIEVER or not query.strip():
        return "", []
    lines, used = [], []
    for idx, score in _RETRIEVER.search(query, RAG_TOP_K):
        if score < RAG_MIN_SCORE:
            continue  # ไม่เกี่ยวพอ → ข้าม (คำถามทั่วไปจะได้ไม่มีความรู้สุขภาพปน)
        ans = KB[idx].get("a", "")
        if ans:
            lines.append(f"- {ans}")
            used.append({**KB[idx], "score": round(float(score), 3)})
    return "\n".join(lines), used


def _fallback_answer(prompt: str, context: str) -> str:
    # ใช้เฉพาะตอน LLM ไม่พร้อม (ไม่มี token / เรียกไม่สำเร็จ)
    low = prompt.lower()
    if "emergency" in low:
        return "ตรวจพบการแจ้งเตือนระดับฉุกเฉิน หยุดกิจกรรมทันที อยู่ในที่ปลอดภัย และโทร 1669 หากอาการไม่ดีขึ้น"
    if context:
        return "จากข้อมูลที่เกี่ยวข้อง:\n" + context
    if "history" in low or "trend" in low or "แนวโน้ม" in prompt:
        return "ดูแนวโน้มได้จากประวัติการแจ้งเตือนและประเภทความเสี่ยงที่เกิดซ้ำ"
    return (
        "ขออภัย ตอนนี้ผู้ช่วย AI ยังเชื่อมต่อไม่ได้ จึงตอบคำถามทั่วไปไม่ได้ชั่วคราว "
        "(สำหรับเรื่องสุขภาพ/ความปลอดภัยยังให้คำแนะนำเบื้องต้นได้) กรุณาลองใหม่อีกครั้ง"
    )


@app.post("/chat")
def chat(
    payload: ChatRequest,
    authorization: Optional[str] = Header(default=None),
):
    user_id = _verify_chat_user(authorization)
    _enforce_ai_rate_limit(user_id)
    if not _AI_IN_FLIGHT.acquire(blocking=False):
        raise HTTPException(
            status_code=503,
            detail="Chat service is busy. Please retry shortly.",
            headers={"Retry-After": "2"},
        )
    try:
        return _generate_chat_reply(payload)
    finally:
        _AI_IN_FLIGHT.release()


def _generate_chat_reply(payload: ChatRequest) -> dict[str, Any]:
    # All account identity and resource gates run in `chat` before reaching this function.
    prompt = payload.prompt
    question = _extract_question(prompt, payload.question)
    model = LLM_MODEL_DEFAULT

    # [1+2] RAG retrieve ความรู้ที่เกี่ยวข้อง
    context, used = _retrieve(question)
    sources = [e.get("q", "") for e in used]

    # [3] ประกอบ prompt (ความรู้อ้างอิง + prompt เดิมที่มีค่าเซนเซอร์ครบอยู่แล้ว)
    user_content = (
        f"[ข้อมูลอ้างอิงที่อาจเกี่ยวข้อง — ใช้ประกอบถ้าตรงกับคำถามเท่านั้น]\n{context}\n\n"
        if context
        else ""
    ) + prompt

    # [4] เรียก Pathumma LLM ผ่าน HuggingFace router (ไม่ต้องใช้ GPU)
    if LLM_API_KEY:
        try:
            resp = httpx.post(
                f"{LLM_BASE_URL}/chat/completions",
                headers={"Authorization": f"Bearer {LLM_API_KEY}"},
                json={
                    "model": model,
                    "messages": [
                        {"role": "system", "content": SYSTEM_TH},
                        {"role": "user", "content": user_content},
                    ],
                    "max_tokens": 256,
                    "temperature": 0.6,
                },
                timeout=30.0,
            )
            resp.raise_for_status()
            answer = resp.json()["choices"][0]["message"]["content"].strip()
            if answer:
                return {
                    "mode": "llm",
                    "model": model,
                    "answer": answer,
                    "rag_sources": sources,
                }
        except Exception as exc:  # LLM ล่ม/ไม่ได้ตั้ง token → ใช้ fallback
            # Do not log request/provider exception text; it can contain user data.
            print(f"[chat] LLM request failed ({type(exc).__name__}); using fallback")

    # fallback: ตอบจากความรู้ที่ดึงมา (ยังทำงานได้แม้ไม่มี token)
    return {
        "mode": "fallback",
        "model": "vita-gaurd-rag-fallback",
        "answer": _fallback_answer(prompt, context),
        "rag_sources": sources,
    }


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


def _apply_guardrails(text: str) -> str:
    """Remove unsafe lines; fail closed if nothing safe remains. / ตัดบรรทัดเสี่ยงและปิดแบบปลอดภัยเมื่อไม่เหลือข้อความ"""
    kept = [ln for ln in text.splitlines() if not _DENY_PATTERNS.search(ln)]
    cleaned = "\n".join(kept).strip()
    # EN: Never restore the original text after filtering removed every line.
    # TH: ห้ามคืนข้อความเดิมหลังตัวกรองลบทุกบรรทัด เพราะจะทำให้ข้าม guardrail
    return cleaned or "ขออภัย ระบบไม่สามารถให้คำแนะนำนี้ได้อย่างปลอดภัย กรุณาติดต่อผู้เชี่ยวชาญหรือหน่วยฉุกเฉินหากจำเป็น"


def _deterministic_advice(status: str, level: str) -> str:
    """TH: คำแนะนำสำรองตายตัวต่อสถานะ (เมื่อ LLM/เน็ตล่ม) / EN: per-state offline fallback"""
    if "ออกซิเจน" in status:
        return ("• หยุดกิจกรรมทันที นั่งพักในที่อากาศถ่ายเท\n"
                "• หายใจช้าลึก แล้ววัดค่าซ้ำใน 2 นาที\n"
                "• หากยังต่ำหรือมีอาการ โทร 1669")
    if "หลับใน" in status or "ง่วง" in status:
        return ("• หาที่จอด/หยุดพักในจุดปลอดภัยทันที\n"
                "• งีบสั้น 15-20 นาที และดื่มน้ำ\n"
                "• ยังไม่หายง่วง อย่าฝืนทำกิจกรรมต่อ")
    if "เคลื่อนไหวผิดปกติ" in status:
        return ("• หยุดกิจกรรมทันที อยู่ในที่ปลอดภัย\n"
                "• ให้คนใกล้ชิดช่วยดูอาการ\n"
                "• หากอาการไม่ดีขึ้น โทร 1669")
    if "พัก" in status or "อ่อนล้า" in status or "เครียด" in status:
        return ("• หยุดพัก 5-10 นาที หายใจช้าๆ\n"
                "• ดื่มน้ำ ลดสิ่งกระตุ้น\n"
                "• ประเมินตัวเองก่อนทำกิจกรรมต่อ")
    if level == "Emergency":
        return ("• หยุดกิจกรรมทันที อยู่ในที่ปลอดภัย\n"
                "• ประเมินอาการ หากรุนแรง โทร 1669\n"
                "• แจ้งคนใกล้ชิดให้มาช่วย")
    return ("• เฝ้าสังเกตอาการต่อเนื่อง\n"
            "• พักเมื่อรู้สึกล้า และดื่มน้ำสม่ำเสมอ\n"
            "• หากผิดปกติให้ปรึกษาผู้ดูแลหรือแพทย์")


def _call_llm(system: str, user_content: str, model: str) -> Optional[str]:
    """เรียก LLM (Pathumma ผ่าน HF) — คืน text หรือ None ถ้าไม่พร้อม/ล้มเหลว"""
    if not LLM_API_KEY:
        return None
    try:
        resp = httpx.post(
            f"{LLM_BASE_URL}/chat/completions",
            headers={"Authorization": f"Bearer {LLM_API_KEY}"},
            json={
                "model": model,
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": user_content},
                ],
                "max_tokens": 220,
                "temperature": 0.5,
            },
            timeout=30.0,
        )
        resp.raise_for_status()
        text = resp.json()["choices"][0]["message"]["content"].strip()
        return text or None
    except Exception as exc:
        # Never log provider exception text; it can include request or endpoint details.
        print(f"[llm] request failed ({type(exc).__name__})")
        return None


@app.post("/advice")
def advice(
    payload: AdviceRequest,
    authorization: Optional[str] = Header(default=None),
):
    """รับสถานะที่ระบบตรวจพบ + ค่าเซนเซอร์ → คืน 'คำแนะนำ' จาก LLM (ไม่ถามตอบ)"""
    user_id = _verify_chat_user(authorization)
    _enforce_ai_rate_limit(user_id)
    if not _AI_IN_FLIGHT.acquire(blocking=False):
        raise HTTPException(
            status_code=503,
            detail="AI service is busy. Please retry shortly.",
            headers={"Retry-After": "2"},
        )
    try:
        return _generate_advice(payload)
    finally:
        _AI_IN_FLIGHT.release()


def _generate_advice(payload: AdviceRequest) -> dict[str, Any]:
    """Generate advice after shared auth, rate and concurrency guards pass."""
    status = payload.status.strip()  # riskClass เช่น "เสี่ยงหลับใน"
    level = payload.alert_level.strip()
    sensor = payload.sensor.strip()  # สรุปค่าเซนเซอร์ (ข้อความ)
    if not status:
        raise HTTPException(status_code=422, detail="status must not be blank.")
    model = LLM_MODEL_DEFAULT

    context, used = _retrieve(f"{status} {sensor}")
    sources = [
        {"title": e.get("q", ""), "score": e.get("score", 0.0)} for e in used
    ]
    cause = f"สถานะที่ตรวจพบ: {status}" + (f" (ระดับ {level})" if level else "")

    user_content = (
        (f"[ความรู้อ้างอิง]\n{context}\n\n" if context else "")
        + f"สถานะที่ระบบตรวจพบ: {status} (ระดับ {level})\n"
        + (f"ค่าที่เกี่ยวข้อง: {sensor}\n" if sensor else "")
        + "ให้คำแนะนำว่าควรปฏิบัติตัวอย่างไรตอนนี้"
    )

    text = _call_llm(ADVICE_SYSTEM, user_content, model)
    if text:
        return {
            "mode": "rag",
            "model": model,
            "cause": cause,
            "advice": _apply_guardrails(text),  # กรองวินิจฉัย/สั่งยา
            "sources": sources,
            "disclaimer": DISCLAIMER,
        }

    # fallback: คำแนะนำตายตัวต่อสถานะ (ทำงานได้แม้ไม่มี token/เน็ต)
    return {
        "mode": "fallback",
        "model": "rule-fallback",
        "cause": cause,
        "advice": _deterministic_advice(status, level),
        "sources": sources,
        "disclaimer": DISCLAIMER,
    }


def _validate_sensor_event(event: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    sensor = event.get("sensorData")
    if not isinstance(sensor, dict):
        errors.append("sensorData must be an object")
        sensor = {}
    _require_range(errors, sensor, "heart_rate", "heartRate", 0, 240)
    _require_range(errors, sensor, "spo2", None, 0, 100)
    _require_range(errors, sensor, "ecg_rate", "ecgRate", 0, 240)
    _require_range(errors, sensor, "ecg_rr_interval", "ecgRrInterval", 0, 3000)
    _require_range(errors, sensor, "ecg_hrv", "ecgHrv", 0, 500)
    _require_range(errors, sensor, "gsr", None, 0, 1000)
    _require_range(errors, sensor, "temperature", None, 20, 45)
    for key in [
        "accel_x",
        "accel_y",
        "accel_z",
        "gyro_x",
        "gyro_y",
        "gyro_z",
        "motion_magnitude",
        "gyro_magnitude",
    ]:
        _require_number(errors, sensor, key)
    profile = event.get("userProfile")
    if not isinstance(profile, dict):
        errors.append("userProfile must be an object")
        profile = {}
    if not str(profile.get("userId") or "").strip():
        errors.append("userProfile.userId is required")
    device_id_error = _device_id_error(profile.get("deviceId"))
    if device_id_error:
        errors.append(device_id_error)
    return errors


def _device_id_error(value: Any) -> Optional[str]:
    """Validate the client device ID before using it in a Firestore path."""
    if not isinstance(value, str) or not value.strip():
        return "userProfile.deviceId is required"
    # EN: Firestore path segments cannot contain slash and must stay bounded.
    # TH: segment ของ Firestore ห้ามมี slash และจำกัดความยาวก่อนใช้เป็น path
    if len(value) > 128 or "/" in value:
        return "userProfile.deviceId has an invalid format"
    return None


def _require_range(
    errors: list[str],
    data: dict[str, Any],
    key: str,
    fallback_key: Optional[str],
    minimum: float,
    maximum: float,
):
    value = _number(data.get(key) if data.get(key) is not None else data.get(fallback_key))
    if value is None:
        errors.append(f"{key} is required")
        return
    if value < minimum or value > maximum:
        errors.append(f"{key} must be between {minimum:g} and {maximum:g}")


def _require_number(errors: list[str], data: dict[str, Any], key: str):
    if _number(data.get(key)) is None:
        errors.append(f"{key} is required")


def _number(value: Any) -> Optional[float]:
    try:
        if value is None or value == "" or isinstance(value, bool):
            return None
        number = float(value)
        return number if math.isfinite(number) else None
    except (TypeError, ValueError):
        return None


def _write_firestore(collection: str, event: dict[str, Any]) -> bool:
    if not _FIRESTORE_CLIENT:
        return False
    profile = event.get("userProfile") or {}
    user_id = str(profile.get("userId") or "unknown-user")
    device_id = str(profile.get("deviceId") or "unknown-device")
    doc_id = f"{datetime.utcnow().strftime('%Y%m%d%H%M%S%f')}-{device_id}"
    try:
        user_document = _FIRESTORE_CLIENT.collection(
            f"{FIRESTORE_COLLECTION_PREFIX}_{collection}"
        ).document(user_id)
        # EN: Seed the transactional registry once for accounts with legacy subcollections.
        # TH: เริ่ม registry ใน transaction จาก subcollection เก่าที่มีอยู่แล้ว
        root_snapshot = user_document.get()
        registry = root_snapshot.to_dict() if root_snapshot.exists else None
        if not isinstance(registry, dict) or not isinstance(
            registry.get("device_ids"), list
        ):
            legacy_device_ids = {item.id for item in user_document.collections()}
        else:
            legacy_device_ids = set()
        event_document = user_document.collection(device_id).document(doc_id)
        _persist_firestore_event(
            user_document,
            event_document,
            device_id,
            event,
            legacy_device_ids,
        )
    except HTTPException:
        raise
    except Exception:
        # EN: Fail as unavailable without returning a false success or leaking event data.
        # TH: แจ้ง storage ใช้ไม่ได้ ไม่ตอบสำเร็จเท็จหรือเปิดเผยข้อมูล event
        raise HTTPException(
            status_code=503,
            detail="Persistent health-data storage write failed.",
        ) from None
    return True


def _persist_firestore_event(
    user_document: Any,
    event_document: Any,
    device_id: str,
    event: dict[str, Any],
    legacy_device_ids: set[str],
) -> None:
    """Transactionally enforce the per-account device cap and store one event."""
    if firestore is None or _FIRESTORE_CLIENT is None:
        raise HTTPException(status_code=503, detail="Persistent storage is unavailable.")

    @firestore.transactional
    def persist(transaction):
        # EN: Read registry in the transaction so concurrent workers serialize updates.
        # TH: อ่าน registry ใน transaction เพื่อให้ worker ที่เขียนพร้อมกัน serialize กัน
        snapshot = user_document.get(transaction=transaction)
        raw_device_ids = snapshot.get("device_ids") if snapshot.exists else []
        registered_ids = (
            {item for item in raw_device_ids if isinstance(item, str)}
            if isinstance(raw_device_ids, list)
            else set()
        )
        registered_ids.update(legacy_device_ids)
        if (
            device_id not in registered_ids
            and len(registered_ids) >= MAX_FIRESTORE_DEVICES_PER_USER
        ):
            raise HTTPException(
                status_code=429,
                detail="This account has reached its registered device limit.",
            )
        registered_ids.add(device_id)
        transaction.set(user_document, {"device_ids": sorted(registered_ids)}, merge=True)
        transaction.set(event_document, event)

    # EN: Firestore retries this transaction if another worker changes the registry.
    # TH: Firestore retry transaction เมื่อ worker อื่นแก้ registry พร้อมกัน
    persist(_FIRESTORE_CLIENT.transaction())


def _read_firestore_events(
    collection: str,
    user_id: str,
    limit: int,
    *,
    per_device_limit: Optional[int] = None,
) -> list[dict[str, Any]]:
    """Read the authenticated user's latest events across the bounded device set."""
    if not _FIRESTORE_CLIENT:
        raise HTTPException(status_code=503, detail="Persistent storage is unavailable.")
    try:
        user_document = _FIRESTORE_CLIENT.collection(
            f"{FIRESTORE_COLLECTION_PREFIX}_{collection}"
        ).document(user_id)
        device_collections = list(user_document.collections())
        if len(device_collections) > MAX_FIRESTORE_DEVICES_PER_USER:
            raise HTTPException(
                status_code=503,
                detail="Stored device data exceeds the configured read limit.",
            )
        events: list[tuple[str, dict[str, Any]]] = []
        for device_collection in device_collections:
            snapshots = (
                device_collection.order_by(
                    "__name__", direction=firestore.Query.DESCENDING
                )
                .limit(per_device_limit or limit)
                .stream()
            )
            for snapshot in snapshots:
                event = snapshot.to_dict()
                if not isinstance(event, dict) or event.get("authUserId") != user_id:
                    continue
                events.append((snapshot.id, event))
        events.sort(key=lambda item: (str(item[1].get("receivedAt", "")), item[0]))
        return [event for _, event in events[-limit:]]
    except HTTPException:
        raise
    except Exception:
        # EN: Keep provider details and health data out of the HTTP error body.
        # TH: ไม่เปิดเผยรายละเอียด provider หรือข้อมูลสุขภาพใน body ของ error
        raise HTTPException(
            status_code=503,
            detail="Persistent health-data storage read failed.",
        ) from None
