from datetime import datetime
from html import escape
import json
import math
import os
import re
from collections import Counter
from typing import Any, Optional

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

try:
    from google.cloud import firestore
except ImportError:
    firestore = None


app = FastAPI(title="doz Cloud API")

SENSOR_EVENTS: list[dict[str, Any]] = []
ALERT_EVENTS: list[dict[str, Any]] = []
FIRESTORE_COLLECTION_PREFIX = os.getenv("FIRESTORE_COLLECTION_PREFIX", "vita_guard")
USE_FIRESTORE = os.getenv("USE_FIRESTORE", "").lower() in {"1", "true", "yes"}
_FIRESTORE_CLIENT = firestore.Client() if USE_FIRESTORE and firestore else None


class CloudPayload(BaseModel):
    class Config:
        extra = "allow"


@app.get("/health")
def health():
    return {
        "status": "ok",
        "sensor_events": len(SENSOR_EVENTS),
        "alert_events": len(ALERT_EVENTS),
        "storage": "firestore" if _FIRESTORE_CLIENT else "memory",
    }


@app.get("/sensor")
def sensor_events(limit: int = 100):
    return SENSOR_EVENTS[-limit:]


@app.get("/alert")
def alert_events(limit: int = 100):
    return ALERT_EVENTS[-limit:]


@app.get("/devices")
def devices():
    latest: dict[str, dict[str, Any]] = {}
    for event in SENSOR_EVENTS:
        profile = event.get("userProfile") or {}
        device_id = str(profile.get("deviceId") or "unknown-device")
        latest[device_id] = event
    return list(latest.values())


def _is_local_request(request: Request) -> bool:
    client_host = request.client.host if request.client else ""
    forwarded_for = request.headers.get("x-forwarded-for", "").split(",")[0].strip()
    host = forwarded_for or client_host
    return host in {"127.0.0.1", "::1", "localhost"}


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
def sensor(payload: CloudPayload):
    event = payload.model_dump()
    errors = _validate_sensor_event(event)
    if errors:
        raise HTTPException(status_code=422, detail={"errors": errors})
    event["receivedAt"] = datetime.utcnow().isoformat()
    SENSOR_EVENTS.append(event)
    _write_firestore("sensor_events", event)
    return {"ok": True, "stored": len(SENSOR_EVENTS)}


@app.post("/alert")
def alert(payload: CloudPayload):
    event = payload.model_dump()
    event["receivedAt"] = datetime.utcnow().isoformat()
    ALERT_EVENTS.append(event)
    _write_firestore("alert_events", event)
    return {"ok": True, "stored": len(ALERT_EVENTS)}


# ─────────────────────────────────────────────────────────────────────────────
# RAG: คลังความรู้ + retriever (char n-gram TF-IDF — รองรับไทย ไม่ต้องใช้ torch/faiss)
# ─────────────────────────────────────────────────────────────────────────────
LLM_BASE_URL = os.getenv("LLM_BASE_URL", "https://router.huggingface.co/v1")
LLM_API_KEY = os.getenv("LLM_API_KEY") or os.getenv("HF_TOKEN") or ""
LLM_MODEL_DEFAULT = os.getenv("LLM_MODEL", "nectec/Pathumma-llm-text-1.0.0:featherless-ai")
RAG_TOP_K = int(os.getenv("RAG_TOP_K", "3"))
# คะแนนความเกี่ยวข้องขั้นต่ำ — ต่ำกว่านี้ถือว่าไม่เกี่ยว (กันดึงความรู้สุขภาพใส่คำถามทั่วไป)
RAG_MIN_SCORE = float(os.getenv("RAG_MIN_SCORE", "0.12"))

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
def chat(payload: CloudPayload):
    data = payload.model_dump()
    prompt = str(data.get("prompt", ""))
    model = str(data.get("model") or LLM_MODEL_DEFAULT)
    question = _extract_question(prompt, str(data.get("question", "")))

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
                return {"model": model, "answer": answer, "rag_sources": sources}
        except Exception as exc:  # LLM ล่ม/ไม่ได้ตั้ง token → ใช้ fallback
            print(f"[chat] LLM error, falling back: {exc}")

    # fallback: ตอบจากความรู้ที่ดึงมา (ยังทำงานได้แม้ไม่มี token)
    return {
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
    """TH: ตัดประโยควินิจฉัย/สั่งยาออก / EN: strip diagnostic or dosage lines"""
    kept = [ln for ln in text.splitlines() if not _DENY_PATTERNS.search(ln)]
    cleaned = "\n".join(kept).strip()
    return cleaned or text.strip()


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
        print(f"[llm] error: {exc}")
        return None


@app.post("/advice")
def advice(payload: CloudPayload):
    """รับสถานะที่ระบบตรวจพบ + ค่าเซนเซอร์ → คืน 'คำแนะนำ' จาก LLM (ไม่ถามตอบ)"""
    data = payload.model_dump()
    status = str(data.get("status", "")).strip()       # riskClass เช่น "เสี่ยงหลับใน"
    level = str(data.get("alertLevel", "")).strip()
    sensor = str(data.get("sensor", "")).strip()       # สรุปค่าเซนเซอร์ (ข้อความ)
    model = str(data.get("model") or LLM_MODEL_DEFAULT)

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
    sensor = event.get("sensorData") or {}
    errors: list[str] = []
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
    profile = event.get("userProfile") or {}
    if not str(profile.get("userId") or "").strip():
        errors.append("userProfile.userId is required")
    if not str(profile.get("deviceId") or "").strip():
        errors.append("userProfile.deviceId is required")
    return errors


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
        if value is None or value == "":
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def _write_firestore(collection: str, event: dict[str, Any]):
    if not _FIRESTORE_CLIENT:
        return
    profile = event.get("userProfile") or {}
    user_id = str(profile.get("userId") or "unknown-user")
    device_id = str(profile.get("deviceId") or "unknown-device")
    doc_id = f"{datetime.utcnow().strftime('%Y%m%d%H%M%S%f')}-{device_id}"
    (
        _FIRESTORE_CLIENT.collection(f"{FIRESTORE_COLLECTION_PREFIX}_{collection}")
        .document(user_id)
        .collection(device_id)
        .document(doc_id)
        .set(event)
    )
