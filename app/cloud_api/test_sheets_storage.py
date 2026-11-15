"""Storage contract tests without Google credentials or network access."""

import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

import main
from sheets_storage import HEADERS, SheetsStorageError, SheetsStore, store_from_env


class _Response:
    def __init__(self, body, status=200):
        self._body = body
        self.status_code = status

    def json(self):
        return self._body


class _Session:
    def __init__(self):
        self.rows = {"SensorEvents": [HEADERS[:]], "AlertEvents": [HEADERS[:]]}
        self.calls = []

    def request(self, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        if method == "GET":
            tab = "SensorEvents" if "SensorEvents" in url else "AlertEvents"
            return _Response({"values": self.rows[tab]})
        if url.endswith(":append"):
            tab = "SensorEvents" if "SensorEvents" in url else "AlertEvents"
            self.rows[tab].extend(kwargs["json"]["values"])
            return _Response({"updates": {"updatedRows": 1}})
        if url.endswith(":batchClear"):
            for cell_range in kwargs["json"]["ranges"]:
                tab, cells = cell_range.split("!")
                row_number = int(cells.split(":")[0][1:])
                self.rows[tab][row_number - 1] = []
            return _Response({"clearedRanges": kwargs["json"]["ranges"]})
        return _Response({}, 404)


class SheetsStoreTests(unittest.TestCase):
    def setUp(self):
        self.session = _Session()
        self.store = SheetsStore("a" * 30, '{"type":"service_account"}', session=self.session)

    def test_partial_configuration_is_detected_without_credentials(self):
        with patch.dict("os.environ", {"DOZ_SHEETS_SPREADSHEET_ID": "a" * 30, "DOZ_GOOGLE_SERVICE_ACCOUNT_JSON": ""}):
            with self.assertRaises(SheetsStorageError):
                store_from_env()

    def test_invalid_sheets_setup_blocks_sync_even_with_memory_opt_in(self):
        with patch.object(main, "_SHEETS_CONFIG_ERROR", True):
            with patch.object(main, "_SHEETS_STORE", None):
                with patch.dict("os.environ", {
                    "SUPABASE_URL": "https://example.supabase.co",
                    "SUPABASE_PUBLISHABLE_KEY": "public-test-key",
                    "HEALTH_DATA_SYNC_ENABLED": "true",
                    "HEALTH_DATA_MEMORY_STORAGE_ENABLED": "true",
                }):
                    self.assertEqual(TestClient(main.app).get("/ready").status_code, 503)

    def test_owner_isolated_read_raw_append_and_delete(self):
        self.store.append("sensor_events", {"authUserId": "alice", "receivedAt": "1", "value": "=HYPERLINK(\"x\")"})
        self.store.append("sensor_events", {"authUserId": "bob", "receivedAt": "2", "value": 9})
        self.assertEqual(len(self.store.read("sensor_events", "alice", 10)), 1)
        self.assertEqual(self.store.read("sensor_events", "alice", 10)[0]["value"], '=HYPERLINK("x")')
        append_call = next(call for call in self.session.calls if call[1].endswith(":append"))
        self.assertEqual(append_call[2]["params"]["valueInputOption"], "RAW")
        self.store.delete_owner("alice")
        self.assertEqual(self.store.read("sensor_events", "alice", 10), [])
        self.assertEqual(len(self.store.read("sensor_events", "bob", 10)), 1)

    def test_invalid_headers_fail_closed(self):
        self.session.rows["SensorEvents"] = [["wrong"]]
        with self.assertRaises(SheetsStorageError):
            self.store.read("sensor_events", "alice", 10)

    def test_readiness_checks_both_sheets_tabs_when_sync_is_enabled(self):
        with patch.object(main, "_SHEETS_STORE", self.store):
            with patch.dict("os.environ", {
                "SUPABASE_URL": "https://example.supabase.co",
                "SUPABASE_PUBLISHABLE_KEY": "public-test-key",
                "HEALTH_DATA_SYNC_ENABLED": "true",
            }):
                client = TestClient(main.app)
                self.assertEqual(client.get("/ready").status_code, 200)
                self.session.rows["AlertEvents"] = [["wrong"]]
                self.assertEqual(client.get("/ready").status_code, 503)

    def test_api_fails_closed_when_sheets_write_fails(self):
        class FailingStore:
            def append(self, collection, event):
                raise SheetsStorageError("provider error")

        with patch.object(main, "_SHEETS_STORE", FailingStore()):
            with self.assertRaises(main.HTTPException) as error:
                main._write_health_event("sensor_events", {"authUserId": "alice"})
        self.assertEqual(error.exception.status_code, 503)

    def test_overview_uses_authenticated_sheets_rows(self):
        self.store.append("sensor_events", {"authUserId": "alice", "riskResult": {"alertLevel": "Watch"}})
        self.store.append("sensor_events", {"authUserId": "bob", "riskResult": {"alertLevel": "Emergency"}})
        with patch.object(main, "_SHEETS_STORE", self.store):
            with patch.object(main, "_verify_chat_user", return_value="alice"):
                with patch.dict("os.environ", {"HEALTH_DATA_SYNC_ENABLED": "true"}):
                    response = TestClient(main.app).get("/overview", headers={"Authorization": "Bearer test"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["levelCounts"]["Watch"], 1)
        self.assertEqual(response.json()["levelCounts"]["Emergency"], 0)

    def test_account_deletion_does_not_claim_erasure_from_sheets_history(self):
        with patch.object(main, "_SHEETS_STORE", self.store):
            with patch.object(main, "_verify_chat_user", return_value="alice"):
                with patch.dict("os.environ", {
                    "SUPABASE_URL": "https://example.supabase.co",
                    "SUPABASE_SERVICE_ROLE_KEY": "server-test-key",
                }):
                    with patch.object(main.httpx, "delete") as remote_delete:
                        response = TestClient(main.app).delete(
                            "/account", headers={"Authorization": "Bearer test"}
                        )
        self.assertEqual(response.status_code, 503)
        remote_delete.assert_not_called()


if __name__ == "__main__":
    unittest.main()
