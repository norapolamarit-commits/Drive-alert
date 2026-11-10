from contextlib import redirect_stdout
from io import StringIO
import os
import unittest
from unittest.mock import patch

import httpx
from fastapi import HTTPException
from fastapi.testclient import TestClient

import main


class SupabaseChatAuthTests(unittest.TestCase):
    def setUp(self):
        main.SENSOR_EVENTS.clear()
        main.ALERT_EVENTS.clear()
        main._AI_REQUEST_TIMES.clear()
        self.env = patch.dict(
            os.environ,
            {
                "SUPABASE_URL": "https://project.example.supabase.co/",
                "SUPABASE_PUBLISHABLE_KEY": "public-test-key",
            },
        )
        self.env.start()

    def tearDown(self):
        self.env.stop()

    def test_valid_bearer_returns_supabase_user_id(self):
        request = httpx.Request("GET", "https://project.example.supabase.co/auth/v1/user")
        response = httpx.Response(200, json={"id": "user-123"}, request=request)
        with patch("main.httpx.get", return_value=response) as get:
            user_id = main._verify_chat_user("Bearer access-token")

        self.assertEqual(user_id, "user-123")
        self.assertEqual(
            get.call_args.kwargs["headers"]["Authorization"],
            "Bearer access-token",
        )

    def test_missing_token_is_rejected_without_network_call(self):
        with patch("main.httpx.get") as get:
            with self.assertRaises(HTTPException) as error:
                main._verify_chat_user(None)

        self.assertEqual(error.exception.status_code, 401)
        get.assert_not_called()

    def test_expired_token_is_rejected(self):
        request = httpx.Request("GET", "https://project.example.supabase.co/auth/v1/user")
        response = httpx.Response(401, json={"message": "expired"}, request=request)
        with patch("main.httpx.get", return_value=response):
            with self.assertRaises(HTTPException) as error:
                main._verify_chat_user("Bearer expired-token")

        self.assertEqual(error.exception.status_code, 401)

    def test_missing_server_configuration_fails_closed(self):
        with patch.dict(os.environ, {"SUPABASE_URL": "", "SUPABASE_PUBLISHABLE_KEY": ""}):
            with patch("main.httpx.get") as get:
                with self.assertRaises(HTTPException) as error:
                    main._verify_chat_user("Bearer access-token")

        self.assertEqual(error.exception.status_code, 503)
        get.assert_not_called()

    def test_advice_requires_a_verified_bearer_token(self):
        client = TestClient(main.app)
        response = client.post("/advice", json={"status": "Watch"})

        self.assertEqual(response.status_code, 401)

    def test_advice_verifies_token_before_returning_fallback(self):
        request = httpx.Request(
            "GET", "https://project.example.supabase.co/auth/v1/user"
        )
        verified_user = httpx.Response(
            200, json={"id": "user-123"}, request=request
        )
        with patch("main.httpx.get", return_value=verified_user):
            response = TestClient(main.app).post(
                "/advice",
                headers={"Authorization": "Bearer valid-token"},
                json={"status": "Watch", "alertLevel": "Warning"},
            )

        self.assertEqual(response.status_code, 200)
        self.assertIn("advice", response.json())

    def test_advice_ignores_client_model_override(self):
        with patch("main._verify_chat_user", return_value="user-123"):
            with patch("main.LLM_MODEL_DEFAULT", "trusted/server-model"):
                with patch("main._call_llm", return_value="Take a safe break.") as call:
                    response = TestClient(main.app).post(
                        "/advice",
                        headers={"Authorization": "Bearer valid-token"},
                        json={
                            "status": "Watch",
                            "alertLevel": "Warning",
                            "sensor": "",
                            "model": "attacker/expensive-model",
                        },
                    )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["mode"], "rag")
        self.assertEqual(call.call_args.args[2], "trusted/server-model")

    def test_advice_payload_is_bounded_before_auth_or_provider_calls(self):
        client = TestClient(main.app)
        with patch("main._verify_chat_user") as verify:
            with patch("main._call_llm") as call:
                response = client.post(
                    "/advice",
                    json={"status": "Watch", "sensor": "x" * 2001},
                )

        self.assertEqual(response.status_code, 422)
        verify.assert_not_called()
        call.assert_not_called()

    def test_chat_fallback_identifies_that_no_llm_answer_was_generated(self):
        with patch("main._verify_chat_user", return_value="user-123"):
            with patch("main.LLM_API_KEY", ""):
                response = TestClient(main.app).post(
                    "/chat",
                    headers={"Authorization": "Bearer valid-token"},
                    json={"question": "hello", "prompt": "hello"},
                )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["mode"], "fallback")
        self.assertIn("answer", response.json())

    def test_chat_calls_configured_llm_and_marks_response_as_llm(self):
        request = httpx.Request("POST", "https://router.example/v1/chat/completions")
        provider_response = httpx.Response(
            200,
            json={"choices": [{"message": {"content": "Take a safe break."}}]},
            request=request,
        )
        with patch("main._verify_chat_user", return_value="user-123"):
            with patch("main._retrieve", return_value=("Relevant safe-driving info", [])):
                with patch("main.LLM_API_KEY", "test-server-key"):
                    with patch("main.httpx.post", return_value=provider_response) as post:
                        response = TestClient(main.app).post(
                            "/chat",
                            headers={"Authorization": "Bearer valid-token"},
                            json={
                                "question": "How do I stay safe?",
                                "prompt": "How do I stay safe?",
                                "model": "attacker/expensive-model",
                            },
                        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["mode"], "llm")
        self.assertEqual(response.json()["answer"], "Take a safe break.")
        self.assertEqual(post.call_args.kwargs["headers"]["Authorization"], "Bearer test-server-key")
        self.assertEqual(post.call_args.kwargs["json"]["model"], main.LLM_MODEL_DEFAULT)

    def test_ai_rate_limit_applies_only_after_user_authentication(self):
        client = TestClient(main.app)
        with patch("main.AI_RATE_LIMIT_MAX", 1):
            with patch("main._verify_chat_user", return_value="user-123"):
                with patch("main.LLM_API_KEY", ""):
                    payload = {"question": "hello", "prompt": "hello"}
                    first = client.post(
                        "/chat",
                        headers={"Authorization": "Bearer valid-token"},
                        json=payload,
                    )
                    second = client.post(
                        "/chat",
                        headers={"Authorization": "Bearer valid-token"},
                        json=payload,
                    )

        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 429)
        self.assertIn("Retry-After", second.headers)

    def test_ai_rate_limit_is_independent_per_verified_account(self):
        with patch("main.AI_RATE_LIMIT_MAX", 1):
            main._enforce_ai_rate_limit("user-123", now=100.0)
            main._enforce_ai_rate_limit("user-456", now=100.0)
            with self.assertRaises(HTTPException) as error:
                main._enforce_ai_rate_limit("user-123", now=101.0)

        self.assertEqual(error.exception.status_code, 429)
        self.assertGreaterEqual(int(error.exception.headers["Retry-After"]), 1)

    def test_chat_rejects_when_concurrency_capacity_is_full(self):
        with patch("main._verify_chat_user", return_value="user-123"):
            with patch("main._AI_IN_FLIGHT") as semaphore:
                semaphore.acquire.return_value = False
                response = TestClient(main.app).post(
                    "/chat",
                    headers={"Authorization": "Bearer valid-token"},
                    json={"question": "hello", "prompt": "hello"},
                )

        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.headers["Retry-After"], "2")
        semaphore.release.assert_not_called()

    def test_chat_and_advice_share_account_rate_limit(self):
        client = TestClient(main.app)
        with patch("main.AI_RATE_LIMIT_MAX", 1):
            with patch("main._verify_chat_user", return_value="user-123"):
                with patch("main.LLM_API_KEY", ""):
                    chat_response = client.post(
                        "/chat",
                        headers={"Authorization": "Bearer valid-token"},
                        json={"question": "hello", "prompt": "hello"},
                    )
                    advice_response = client.post(
                        "/advice",
                        headers={"Authorization": "Bearer valid-token"},
                        json={"status": "Watch", "alertLevel": "Warning"},
                    )

        self.assertEqual(chat_response.status_code, 200)
        self.assertEqual(advice_response.status_code, 429)
        self.assertIn("Retry-After", advice_response.headers)

    def test_advice_rejects_when_shared_concurrency_capacity_is_full(self):
        with patch("main._verify_chat_user", return_value="user-123"):
            with patch("main._AI_IN_FLIGHT") as semaphore:
                semaphore.acquire.return_value = False
                response = TestClient(main.app).post(
                    "/advice",
                    headers={"Authorization": "Bearer valid-token"},
                    json={"status": "Watch", "alertLevel": "Warning"},
                )

        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.headers["Retry-After"], "2")
        semaphore.release.assert_not_called()

    def test_chat_rejects_oversized_user_content_before_auth_or_llm_calls(self):
        with patch("main._verify_chat_user") as verify:
            with patch("main.httpx.post") as post:
                response = TestClient(main.app).post(
                    "/chat",
                    json={"question": "x" * 2001, "prompt": "too long"},
                )

        self.assertEqual(response.status_code, 422)
        verify.assert_not_called()
        post.assert_not_called()

    def test_chat_provider_timeout_returns_explicit_fallback(self):
        with patch("main._verify_chat_user", return_value="user-123"):
            with patch("main._retrieve", return_value=("", [])):
                with patch("main.LLM_API_KEY", "test-server-key"):
                    with patch("main.httpx.post", side_effect=httpx.ReadTimeout("timeout")):
                        response = TestClient(main.app).post(
                            "/chat",
                            headers={"Authorization": "Bearer valid-token"},
                            json={"question": "How do I stay safe?", "prompt": "How do I stay safe?"},
                        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["mode"], "fallback")
        self.assertIn("AI", response.json()["answer"])

    def test_llm_provider_exception_text_is_not_written_to_logs(self):
        log = StringIO()
        with patch("main.LLM_API_KEY", "test-api-key"):
            with patch(
                "main.httpx.post",
                side_effect=RuntimeError("private prompt text and provider URL"),
            ):
                with redirect_stdout(log):
                    result = main._call_llm("system", "private prompt text", "model")

        self.assertIsNone(result)
        self.assertIn("RuntimeError", log.getvalue())
        self.assertNotIn("private prompt text", log.getvalue())
        self.assertNotIn("provider URL", log.getvalue())

    def test_health_data_read_routes_require_authentication(self):
        client = TestClient(main.app)
        for path in ("/sensor", "/alert", "/devices"):
            with self.subTest(path=path):
                self.assertEqual(client.get(path).status_code, 401)

    def test_health_data_read_routes_are_disabled_by_default(self):
        client = TestClient(main.app)
        with patch("main._verify_chat_user", return_value="user-123"):
            with patch.dict(os.environ, {"HEALTH_DATA_SYNC_ENABLED": "false"}):
                for path in ("/sensor", "/alert", "/devices"):
                    with self.subTest(path=path):
                        response = client.get(
                            path,
                            headers={"Authorization": "Bearer valid-token"},
                        )
                        self.assertEqual(response.status_code, 503)

    def test_health_data_write_routes_are_disabled_without_storing(self):
        client = TestClient(main.app)
        with patch("main._verify_chat_user", return_value="user-123"):
            with patch.dict(os.environ, {"HEALTH_DATA_SYNC_ENABLED": "false"}):
                sensor_response = client.post(
                    "/sensor",
                    headers={"Authorization": "Bearer valid-token"},
                    json={
                        "sensorData": {
                            "heart_rate": 70,
                            "spo2": 98,
                            "ecg_rate": 70,
                            "ecg_rr_interval": 850,
                            "ecg_hrv": 20,
                            "gsr": 1,
                            "temperature": 36.5,
                            "accel_x": 0,
                            "accel_y": 0,
                            "accel_z": 0,
                            "gyro_x": 0,
                            "gyro_y": 0,
                            "gyro_z": 0,
                            "motion_magnitude": 0,
                            "gyro_magnitude": 0,
                        },
                        "userProfile": {"userId": "claimed-user", "deviceId": "test"},
                    },
                )
                alert_response = client.post(
                    "/alert",
                    headers={"Authorization": "Bearer valid-token"},
                    json={"alert": {"id": "test"}, "userProfile": {}},
                )

        self.assertEqual(sensor_response.status_code, 503)
        self.assertEqual(alert_response.status_code, 503)
        self.assertEqual(main.SENSOR_EVENTS, [])
        self.assertEqual(main.ALERT_EVENTS, [])

    def test_public_health_check_does_not_disclose_event_counts_or_storage(self):
        client = TestClient(main.app)
        response = client.get("/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

    def test_account_deletion_requires_authentication(self):
        response = TestClient(main.app).delete("/account")
        self.assertEqual(response.status_code, 401)

    def test_account_deletion_fails_closed_without_server_admin_key(self):
        client = TestClient(main.app)
        with patch("main._verify_chat_user", return_value="user-123"):
            with patch.dict(os.environ, {"SUPABASE_SERVICE_ROLE_KEY": ""}):
                with patch("main.httpx.delete") as delete:
                    response = client.delete(
                        "/account",
                        headers={"Authorization": "Bearer valid-token"},
                    )

        self.assertEqual(response.status_code, 503)
        delete.assert_not_called()

    def test_account_deletion_uses_only_verified_user_id_and_clears_events(self):
        client = TestClient(main.app)
        main.SENSOR_EVENTS.extend(
            [
                {"authUserId": "user-123", "id": "owned"},
                {"authUserId": "user-456", "id": "other"},
            ]
        )
        main.ALERT_EVENTS.extend(
            [
                {"authUserId": "user-123", "id": "owned-alert"},
                {"authUserId": "user-456", "id": "other-alert"},
            ]
        )
        admin_response = httpx.Response(
            200, request=httpx.Request("DELETE", "https://project.example/admin")
        )
        with patch("main._verify_chat_user", return_value="user-123"):
            with patch.dict(
                os.environ,
                {"SUPABASE_SERVICE_ROLE_KEY": "server-only-test-key"},
            ):
                with patch("main.httpx.delete", return_value=admin_response) as delete:
                    response = client.delete(
                        "/account",
                        headers={"Authorization": "Bearer valid-token"},
                    )

        self.assertEqual(response.status_code, 204)
        self.assertTrue(delete.call_args.args[0].endswith("/admin/users/user-123"))
        self.assertEqual(
            delete.call_args.kwargs["headers"]["Authorization"],
            "Bearer server-only-test-key",
        )
        self.assertEqual(main.SENSOR_EVENTS, [{"authUserId": "user-456", "id": "other"}])
        self.assertEqual(main.ALERT_EVENTS, [{"authUserId": "user-456", "id": "other-alert"}])

    def test_alert_events_are_bound_to_verified_account(self):
        client = TestClient(main.app)

        def verified_user(authorization):
            return (authorization or "").removeprefix("Bearer ")

        with patch("main._verify_chat_user", side_effect=verified_user):
            with patch.dict(os.environ, {"HEALTH_DATA_SYNC_ENABLED": "true"}):
                client.post(
                    "/alert",
                    headers={"Authorization": "Bearer user-a"},
                    json={"alert": {"id": "a1"}, "userProfile": {"userId": "victim"}},
                )
                client.post(
                    "/alert",
                    headers={"Authorization": "Bearer user-b"},
                    json={"alert": {"id": "b1"}, "userProfile": {"userId": "victim"}},
                )
                user_a_events = client.get(
                    "/alert", headers={"Authorization": "Bearer user-a"}
                ).json()
                user_b_events = client.get(
                    "/alert", headers={"Authorization": "Bearer user-b"}
                ).json()

        self.assertEqual(len(user_a_events), 1)
        self.assertEqual(len(user_b_events), 1)
        self.assertEqual(user_a_events[0]["userProfile"]["userId"], "user-a")
        self.assertEqual(user_b_events[0]["userProfile"]["userId"], "user-b")


if __name__ == "__main__":
    unittest.main()
