"""Server-only Supabase PostgREST storage for validated Doz health events."""

import hashlib
import json
import os
from urllib.parse import urlsplit

import httpx


class SupabaseStorageError(RuntimeError):
    """A storage operation failed; callers must not expose provider details."""


class SupabaseStore:
    TABLE = "doz_health_events"
    COLLECTIONS = frozenset({"sensor_events", "alert_events"})

    def __init__(self, base_url: str, service_key: str):
        parsed = urlsplit(base_url)
        if (parsed.scheme != "https" or not parsed.hostname or
                not parsed.hostname.endswith(".supabase.co") or
                parsed.username or parsed.password or parsed.port or
                parsed.path not in ("", "/") or parsed.query or parsed.fragment):
            raise SupabaseStorageError("Invalid Supabase project URL")
        if not service_key or any(ord(c) < 33 or ord(c) > 126 for c in service_key):
            raise SupabaseStorageError("Invalid server credential")
        self.endpoint = f"https://{parsed.hostname}/rest/v1/{self.TABLE}"
        self.headers = {"apikey": service_key, "Authorization": f"Bearer {service_key}"}

    @staticmethod
    def _collection(value: str) -> str:
        if value not in SupabaseStore.COLLECTIONS:
            raise SupabaseStorageError("Unsupported collection")
        return value

    def _request(self, method: str, *, params=None, body=None, prefer=None):
        headers = dict(self.headers)
        if prefer:
            headers["Prefer"] = prefer
        try:
            response = httpx.request(method, self.endpoint, params=params, json=body,
                                     headers=headers, timeout=10.0)
            if response.status_code < 200 or response.status_code >= 300:
                raise SupabaseStorageError("Supabase storage request failed")
            if len(response.content) > 20_000_000:
                raise SupabaseStorageError("Supabase storage response too large")
            return response
        except httpx.HTTPError as exc:
            raise SupabaseStorageError("Supabase storage unavailable") from exc

    def check_ready(self):
        self._request("GET", params={"select": "event_id", "limit": "0"})

    def append(self, collection: str, event: dict):
        kind = self._collection(collection)
        user_id = event.get("authUserId")
        profile = event.get("userProfile") or {}
        device_id = profile.get("deviceId")
        if not isinstance(user_id, str) or not user_id or not isinstance(device_id, str) or not device_id:
            raise SupabaseStorageError("Validated owner and device are required")
        stable_event = {key: value for key, value in event.items() if key != "receivedAt"}
        canonical = json.dumps(stable_event, sort_keys=True, separators=(",", ":"), allow_nan=False)
        event_id = hashlib.sha256(f"{kind}\n{user_id}\n{canonical}".encode()).hexdigest()
        self._request("POST", params={"on_conflict": "event_id"},
                      body={"event_id": event_id, "kind": kind,
                            "auth_user_id": user_id, "device_id": device_id,
                            "event_json": event},
                      prefer="resolution=ignore-duplicates,return=minimal")

    def read(self, collection: str, user_id: str, limit: int) -> list[dict]:
        kind = self._collection(collection)
        if not isinstance(user_id, str) or not user_id or not 1 <= limit <= 500:
            raise SupabaseStorageError("Invalid read scope")
        response = self._request("GET", params={"select": "event_json,auth_user_id",
                                                 "kind": f"eq.{kind}",
                                                 "auth_user_id": f"eq.{user_id}",
                                                 "order": "received_at.desc", "limit": str(limit)})
        try:
            rows = response.json()
            if not isinstance(rows, list) or len(rows) > limit:
                raise ValueError("Invalid result")
            if any(not isinstance(row, dict) or row.get("auth_user_id") != user_id or
                   not isinstance(row.get("event_json"), dict) or
                   row["event_json"].get("authUserId") != user_id for row in rows):
                raise ValueError("Cross-account or malformed row")
            return [row["event_json"] for row in rows]
        except (ValueError, TypeError, KeyError) as exc:
            raise SupabaseStorageError("Invalid storage response") from exc

    def delete_user(self, user_id: str):
        if not isinstance(user_id, str) or not user_id:
            raise SupabaseStorageError("Invalid account")
        self._request("DELETE", params={"auth_user_id": f"eq.{user_id}"},
                      prefer="return=minimal")


def store_from_env():
    """Opt in explicitly; a missing configuration fails closed."""
    if os.getenv("HEALTH_DATA_STORE", "").strip().lower() != "supabase":
        return None
    return SupabaseStore(os.getenv("SUPABASE_URL", ""),
                         os.getenv("SUPABASE_SERVICE_ROLE_KEY", ""))
