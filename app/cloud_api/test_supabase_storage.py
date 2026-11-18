import os
import unittest
from unittest.mock import patch

import httpx
from fastapi import HTTPException

import main
from supabase_storage import SupabaseStorageError, SupabaseStore, store_from_env


class SupabaseStorageTests(unittest.TestCase):
    def setUp(self):
        self.store = SupabaseStore("https://project.supabase.co", "server-only-test-key")
        self.event = {"authUserId": "11111111-1111-1111-1111-111111111111",
                      "userProfile": {"deviceId": "doz-1"},
                      "timestamp": "2026-11-18T00:00:00Z",
                      "sensorData": {"red_adc_mean": 123, "ir_adc_mean": 456},
                      "receivedAt": "2026-11-18T00:00:01Z"}

    def test_explicit_opt_in_and_complete_server_credentials_required(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertIsNone(store_from_env())
        with patch.dict(os.environ, {"HEALTH_DATA_STORE": "supabase",
                                     "SUPABASE_URL": "http://unsafe.example",
                                     "SUPABASE_SERVICE_ROLE_KEY": "key"}, clear=True):
            with self.assertRaises(SupabaseStorageError):
                store_from_env()

    def test_repeat_event_uses_same_id_despite_different_receive_time(self):
        with patch("supabase_storage.httpx.request", return_value=httpx.Response(201, request=httpx.Request("POST", self.store.endpoint))) as request:
            self.store.append("sensor_events", self.event)
            second = dict(self.event, receivedAt="2026-11-18T00:00:09Z")
            self.store.append("sensor_events", second)
        first_id = request.call_args_list[0].kwargs["json"]["event_id"]
        second_id = request.call_args_list[1].kwargs["json"]["event_id"]
        self.assertEqual(first_id, second_id)
        self.assertEqual(request.call_args_list[0].kwargs["params"], {"on_conflict": "event_id"})

    def test_read_rejects_cross_account_response(self):
        owner = self.event["authUserId"]
        response = httpx.Response(200, json=[{"auth_user_id": "another-user", "event_json": self.event}],
                                  request=httpx.Request("GET", self.store.endpoint))
        with patch("supabase_storage.httpx.request", return_value=response):
            with self.assertRaises(SupabaseStorageError):
                self.store.read("sensor_events", owner, 10)

    def test_backend_write_failure_is_not_acknowledged_as_success(self):
        with patch.object(main, "_SUPABASE_STORE", self.store):
            with patch.object(self.store, "append", side_effect=SupabaseStorageError("private details")):
                with self.assertRaises(HTTPException) as caught:
                    main._write_health_event("sensor_events", self.event)
        self.assertEqual(caught.exception.status_code, 503)
        self.assertNotIn("private details", caught.exception.detail)

    def test_account_delete_is_scoped_to_verified_id(self):
        with patch("supabase_storage.httpx.request", return_value=httpx.Response(204, request=httpx.Request("DELETE", self.store.endpoint))) as request:
            self.store.delete_user(self.event["authUserId"])
        self.assertEqual(request.call_args.kwargs["params"], {"auth_user_id": f"eq.{self.event['authUserId']}"})


if __name__ == "__main__":
    unittest.main()
