from datetime import datetime
from html import escape
from typing import Any

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel


app = FastAPI(title="Vita gaurd Cloud API")

SENSOR_EVENTS: list[dict[str, Any]] = []
ALERT_EVENTS: list[dict[str, Any]] = []


class CloudPayload(BaseModel):
    class Config:
        extra = "allow"


@app.get("/health")
def health():
    return {
        "status": "ok",
        "sensor_events": len(SENSOR_EVENTS),
        "alert_events": len(ALERT_EVENTS),
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
  <title>Vita gaurd Local Dashboard</title>
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
            f"<td>{escape(str(sensor.get('heartRate', '-')))}</td>"
            f"<td>{escape(str(sensor.get('spo2', '-')))}</td>"
            f"<td>{escape(str(sensor.get('gsr', '-')))}</td>"
            f"<td>{escape(str(sensor.get('temperature', '-')))}</td>"
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
  <title>Vita gaurd Device Dashboard</title>
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
  <h1>Vita gaurd Device Dashboard</h1>
  <p class="muted">Auto-refresh every 5 seconds. Devices: {len(latest_by_device)} | Sensor events: {len(SENSOR_EVENTS)} | Alerts: {len(ALERT_EVENTS)}</p>
  <div class="card">
    <h2>Latest Device Data</h2>
    <table>
      <thead>
        <tr><th>Device ID</th><th>Received</th><th>Age</th><th>Gender</th><th>HR</th><th>SpO2</th><th>GSR</th><th>Temp</th><th>Risk</th><th>Level</th></tr>
      </thead>
      <tbody>{''.join(rows) if rows else '<tr><td colspan="10">No device data yet.</td></tr>'}</tbody>
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
    event["receivedAt"] = datetime.utcnow().isoformat()
    SENSOR_EVENTS.append(event)
    return {"ok": True, "stored": len(SENSOR_EVENTS)}


@app.post("/alert")
def alert(payload: CloudPayload):
    event = payload.model_dump()
    event["receivedAt"] = datetime.utcnow().isoformat()
    ALERT_EVENTS.append(event)
    return {"ok": True, "stored": len(ALERT_EVENTS)}


@app.post("/chat")
def chat(payload: CloudPayload):
    prompt = str(payload.model_dump().get("prompt", ""))
    if "Emergency" in prompt:
        answer = (
            "Emergency early warning is active. Stop activity, stay in a safe "
            "place, and contact emergency support if the condition continues."
        )
    elif "history" in prompt.lower() or "trend" in prompt.lower():
        answer = "Recent history can be reviewed from alert trends and repeated risk types."
    else:
        answer = (
            "Vita gaurd cloud assistant is online. I can explain current sensor "
            "values, Risk Detection results, and safety recommendations."
        )
    return {"model": "vita-gaurd-cloud-mock", "answer": answer}
