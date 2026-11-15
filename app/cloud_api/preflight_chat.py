#!/usr/bin/env python3
"""Check a deployed doz API without sending sensor or profile data. / ตรวจ API โดยไม่ส่งข้อมูลเซนเซอร์หรือโปรไฟล์"""

import argparse
import json
import os
import sys
from typing import Dict, Optional, Tuple, Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit, urlunsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener  # EN: Open HTTPS requests with redirect control. TH: เปิดคำขอ HTTPS โดยควบคุม redirect


class _RejectRedirects(HTTPRedirectHandler):  # EN: Keep the test token on the configured origin. TH: จำกัด test token ให้อยู่กับ origin ที่กำหนด
    def redirect_request(self, request, fp, code, msg, headers, newurl):  # EN: Intercept every redirect before a follow-up request. TH: ดัก redirect ทุกครั้งก่อนส่งคำขอถัดไป
        return None  # EN: Turn redirects into HTTP errors without forwarding Authorization. TH: ทำ redirect เป็น HTTP error โดยไม่ส่ง Authorization ต่อ


_OPENER = build_opener(_RejectRedirects())  # EN: Reuse a non-redirecting opener for all preflight calls. TH: ใช้ opener ที่ไม่ตาม redirect กับทุกคำขอ preflight


def parse_base_url(value: str) -> str:
    """EN: Accept only a clean HTTPS API base. TH: รับเฉพาะ URL ตั้งต้น HTTPS ที่สะอาด"""
    parts = urlsplit(value.strip())
    if (
        parts.scheme != "https"
        or not parts.hostname
        or parts.username is not None
        or parts.password is not None
        or parts.query
        or parts.fragment
        or parts.path.rstrip("/").endswith(("/chat", "/health", "/ready"))
    ):
        raise ValueError("DOZ_API_BASE_URL must be a clean HTTPS API base URL.")
    return urlunsplit((parts.scheme, parts.netloc, parts.path.rstrip("/"), "", ""))


def request_json(
    url: str,
    *,
    token: Optional[str] = None,
    body: Optional[Dict[str, Any]] = None,
) -> Tuple[int, Any]:
    """Issue one bounded JSON request and return only status plus parsed JSON."""
    headers = {"Accept": "application/json"}
    payload = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        payload = json.dumps(body).encode("utf-8")
    if token is not None:
        headers["Authorization"] = f"Bearer {token}"
    request = Request(url, data=payload, headers=headers, method="POST" if payload else "GET")
    try:
        with _OPENER.open(request, timeout=12) as response:  # EN: Never follow a redirect carrying the test token. TH: ห้ามตาม redirect ที่อาจพา test token ไปด้วย
            raw = response.read(64_001)
            if len(raw) > 64_000:
                raise ValueError("API response exceeded the 64 KB preflight limit.")
            return response.status, json.loads(raw.decode("utf-8"))
    except HTTPError as error:
        return error.code, None


def main() -> int:
    """EN: Check readiness, authenticated routes, and invalid-token rejection. TH: ตรวจความพร้อม route ที่ยืนยันตัวตนและการปฏิเสธ token ผิด"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--require-llm",
        action="store_true",
        help="Fail unless /chat confirms mode=llm and /advice confirms mode=rag.",
    )
    args = parser.parse_args()
    try:
        base_url = parse_base_url(os.environ.get("DOZ_API_BASE_URL", ""))
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 2
    token = os.environ.get("DOZ_CHAT_TEST_TOKEN", "").strip()
    if not token:
        print("Set DOZ_CHAT_TEST_TOKEN to a short-lived test-account access token.", file=sys.stderr)
        return 2

    try:
        # EN: Readiness requires Auth configuration, unlike process liveness at /health.
        # TH: /ready ต้องตั้งค่า Auth ครบ ต่างจาก /health ที่ตรวจแค่ว่า process ยังทำงาน
        ready_status, ready = request_json(f"{base_url}/ready")
        if ready_status != 200 or not isinstance(ready, dict) or ready.get("status") != "ready":
            print(f"Readiness check failed: HTTP {ready_status}.", file=sys.stderr)
            return 1
        print("Readiness check: HTTP 200; status=ready.")

        chat_status, chat = request_json(
            f"{base_url}/chat",
            token=token,
            body={
                "question": "Reply with READY only. This is a deployment test; no sensor or personal data.",
                "prompt": "Reply with READY only. This is a deployment test; no sensor or personal data.",
            },
        )
        if chat_status != 200 or not isinstance(chat, dict):
            print(f"Authenticated chat check failed: HTTP {chat_status}.", file=sys.stderr)
            return 1
        mode = chat.get("mode")
        answer = chat.get("answer")
        if mode not in {"llm", "fallback"} or not isinstance(answer, str) or not answer.strip():
            print("Chat response contract failed (expected mode and non-empty answer).", file=sys.stderr)
            return 1
        print(f"Authenticated chat: HTTP 200; mode={mode}; answer_present=yes.")
        if args.require_llm and mode != "llm":
            print("LLM was required, but the server returned fallback mode.", file=sys.stderr)
            return 1

        advice_status, advice = request_json(
            f"{base_url}/advice",
            token=token,
            body={
                "status": "Watch",
                "alertLevel": "Info",
                "sensor": "",
            },
        )
        if advice_status != 200 or not isinstance(advice, dict):
            print(f"Authenticated advice check failed: HTTP {advice_status}.", file=sys.stderr)
            return 1
        advice_mode = advice.get("mode")
        advice_text = advice.get("advice")
        if (
            advice_mode not in {"rag", "fallback"}
            or not isinstance(advice_text, str)
            or not advice_text.strip()
        ):
            print("Advice response contract failed (expected mode and non-empty advice).", file=sys.stderr)
            return 1
        print(f"Authenticated advice: HTTP 200; mode={advice_mode}; advice_present=yes.")
        if args.require_llm and advice_mode != "rag":
            print("LLM was required, but /advice returned deterministic fallback mode.", file=sys.stderr)
            return 1

        invalid_status, _ = request_json(
            f"{base_url}/chat",
            token="doz-preflight-invalid-token",
            body={"question": "invalid-token check", "prompt": "invalid-token check"},
        )
        if invalid_status != 401:
            print(f"Invalid-token check failed: expected HTTP 401, got {invalid_status}.", file=sys.stderr)
            return 1
        invalid_advice_status, _ = request_json(
            f"{base_url}/advice",
            token="doz-preflight-invalid-token",
            body={"status": "Watch", "alertLevel": "Info", "sensor": ""},
        )
        if invalid_advice_status != 401:
            print(
                f"Invalid-token advice check failed: expected HTTP 401, got {invalid_advice_status}.",
                file=sys.stderr,
            )
            return 1
        print("Invalid-token checks: HTTP 401 for /chat and /advice as expected.")
    except (TimeoutError, URLError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Preflight failed ({type(error).__name__}); response details were not printed.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
