"""Server-only Google Sheets storage for bounded Doz event histories."""
from __future__ import annotations

import json
import os
import re
from typing import Any
from urllib.parse import quote

from google.auth.transport.requests import AuthorizedSession
from google.oauth2.service_account import Credentials


HEADERS = ["auth_user_id", "received_at", "event_id", "event_json"]
MAX_ROWS = 2_000
MAX_EVENT_CHARS = 8_000
MAX_RESPONSE_BYTES = 8 * 1024 * 1024
_ID_RE = re.compile(r"^[A-Za-z0-9_-]{20,100}$")


class SheetsStorageError(Exception):
    """A provider failure or invalid storage configuration."""


class SheetsStore:
    """Read and write only two fixed tabs in one server-owned spreadsheet."""

    def __init__(self, spreadsheet_id: str, credentials_json: str, session: Any = None):
        if not _ID_RE.fullmatch(spreadsheet_id):
            raise SheetsStorageError("Invalid spreadsheet ID")
        if len(credentials_json) > 20_000:
            raise SheetsStorageError("Credentials are too large")
        try:
            info = json.loads(credentials_json)
            if info.get("type") != "service_account":
                raise ValueError("Expected service account")
            credentials = Credentials.from_service_account_info(
                info, scopes=["https://www.googleapis.com/auth/spreadsheets"]
            ) if session is None else None
        except (ValueError, TypeError, KeyError) as exc:
            raise SheetsStorageError("Invalid Sheets credentials") from exc
        self.spreadsheet_id = spreadsheet_id
        self.session = session or AuthorizedSession(credentials)
        self.base = f"https://sheets.googleapis.com/v4/spreadsheets/{spreadsheet_id}"

    @staticmethod
    def _tab(collection: str) -> str:
        tabs = {"sensor_events": "SensorEvents", "alert_events": "AlertEvents"}
        if collection not in tabs:
            raise SheetsStorageError("Unsupported event collection")
        return tabs[collection]

    def _request(self, method: str, url: str, **kwargs: Any) -> dict[str, Any]:
        try:
            response = self.session.request(method, url, timeout=10, stream=True, **kwargs)
            if response.status_code < 200 or response.status_code >= 300:
                raise SheetsStorageError("Sheets request failed")
            if hasattr(response, "iter_content"):
                chunks = []
                size = 0
                for chunk in response.iter_content(chunk_size=65_536):
                    size += len(chunk)
                    if size > MAX_RESPONSE_BYTES:
                        raise SheetsStorageError("Sheets response exceeds size limit")
                    chunks.append(chunk)
                body = json.loads(b"".join(chunks))
            else:
                body = response.json()
            if not isinstance(body, dict):
                raise SheetsStorageError("Invalid Sheets response")
            return body
        except SheetsStorageError:
            raise
        except Exception as exc:
            raise SheetsStorageError("Sheets request failed") from exc
        finally:
            if "response" in locals() and hasattr(response, "close"):
                response.close()

    def _rows(self, collection: str) -> list[list[Any]]:
        tab = self._tab(collection)
        # Read one extra row to detect capacity overflow before accepting writes/deletes.
        encoded = quote(f"{tab}!A1:D{MAX_ROWS + 2}", safe="")
        result = self._request("GET", f"{self.base}/values/{encoded}")
        rows = result.get("values", [])
        if not isinstance(rows, list) or not rows or rows[0] != HEADERS:
            raise SheetsStorageError("Sheets tab headers are missing")
        if len(rows) > MAX_ROWS + 1:
            raise SheetsStorageError("Sheets row limit exceeded")
        return rows

    def append(self, collection: str, event: dict[str, Any]) -> None:
        rows = self._rows(collection)
        if len(rows) >= MAX_ROWS + 1:
            raise SheetsStorageError("Sheets row limit reached")
        owner = event.get("authUserId")
        if not isinstance(owner, str) or not owner or len(owner) > 256:
            raise SheetsStorageError("Invalid event owner")
        payload = json.dumps(event, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
        if len(payload) > MAX_EVENT_CHARS:
            raise SheetsStorageError("Event exceeds Sheets cell limit")
        from uuid import uuid4
        tab = self._tab(collection)
        encoded = quote(f"{tab}!A:D", safe="")
        result = self._request(
            "POST",
            f"{self.base}/values/{encoded}:append",
            params={"valueInputOption": "RAW", "insertDataOption": "INSERT_ROWS"},
            json={"majorDimension": "ROWS", "values": [[owner, event.get("receivedAt", ""), uuid4().hex, payload]]},
        )
        if result.get("updates", {}).get("updatedRows") != 1:
            raise SheetsStorageError("Sheets did not confirm the appended row")

    def read(self, collection: str, owner: str, limit: int) -> list[dict[str, Any]]:
        rows = self._rows(collection)
        events = []
        for row in rows[1:]:
            if not isinstance(row, list) or len(row) != 4 or row[0] != owner:
                continue
            try:
                event = json.loads(row[3])
            except (ValueError, TypeError):
                continue
            if isinstance(event, dict) and event.get("authUserId") == owner:
                events.append(event)
        events.sort(key=lambda item: str(item.get("receivedAt", "")))
        return events[-limit:]

    def delete_owner(self, owner: str) -> None:
        # Clearing cells preserves other users' rows and avoids index shifts.
        # The operator must periodically compact empty rows before capacity is reached.
        for collection in ("sensor_events", "alert_events"):
            rows = self._rows(collection)
            tab = self._tab(collection)
            ranges = [f"{tab}!A{index}:D{index}" for index, row in enumerate(rows[1:], 2)
                      if isinstance(row, list) and row and row[0] == owner]
            for offset in range(0, len(ranges), 100):
                self._request("POST", f"{self.base}/values:batchClear",
                              json={"ranges": ranges[offset:offset + 100]})


def store_from_env() -> SheetsStore | None:
    spreadsheet_id = os.getenv("DOZ_SHEETS_SPREADSHEET_ID", "").strip()
    credentials_json = os.getenv("DOZ_GOOGLE_SERVICE_ACCOUNT_JSON", "").strip()
    if not spreadsheet_id and not credentials_json:
        return None
    if not spreadsheet_id or not credentials_json:
        raise SheetsStorageError("Incomplete Sheets configuration")
    return SheetsStore(spreadsheet_id, credentials_json)
