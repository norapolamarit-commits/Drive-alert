import os
import unittest
from unittest.mock import patch

import preflight_chat


class PreflightChatTests(unittest.TestCase):
    def test_base_url_requires_clean_https_api_base(self):
        self.assertEqual(
            preflight_chat.parse_base_url("https://api.example.org/v1/"),
            "https://api.example.org/v1",
        )
        for url in (
            "http://api.example.org",
            "https://user:pass@api.example.org",
            "https://api.example.org/chat",
            "https://api.example.org/health",
            "https://api.example.org?debug=1",
        ):
            with self.subTest(url=url), self.assertRaises(ValueError):
                preflight_chat.parse_base_url(url)

    @patch.dict(
        os.environ,
        {
            "DOZ_API_BASE_URL": "https://api.example.org",
            "DOZ_CHAT_TEST_TOKEN": "test-token-not-for-real-use",
        },
        clear=True,
    )
    @patch("preflight_chat.request_json")
    def test_preflight_checks_health_chat_advice_and_invalid_tokens(self, request_json):
        request_json.side_effect = [
            (200, {"status": "ok"}),
            (200, {"mode": "llm", "answer": "READY"}),
            (200, {"mode": "rag", "advice": "Take a safe break."}),
            (401, None),
            (401, None),
        ]

        with patch("sys.argv", ["preflight_chat.py"]):
            self.assertEqual(preflight_chat.main(), 0)
        self.assertEqual(request_json.call_count, 5)
        self.assertEqual(
            request_json.call_args_list[1].kwargs["token"],
            "test-token-not-for-real-use",
        )
        self.assertEqual(
            request_json.call_args_list[2].kwargs["token"],
            "test-token-not-for-real-use",
        )
        self.assertEqual(request_json.call_args_list[2].args[0], "https://api.example.org/advice")
        self.assertEqual(
            request_json.call_args_list[3].kwargs["token"],
            "doz-preflight-invalid-token",
        )
        self.assertEqual(
            request_json.call_args_list[4].kwargs["token"],
            "doz-preflight-invalid-token",
        )

    @patch.dict(
        os.environ,
        {
            "DOZ_API_BASE_URL": "https://api.example.org",
            "DOZ_CHAT_TEST_TOKEN": "test-token",
        },
        clear=True,
    )
    @patch("preflight_chat.request_json")
    def test_require_llm_rejects_explicit_fallback_mode(self, request_json):
        request_json.side_effect = [
            (200, {"status": "ok"}),
            (200, {"mode": "fallback", "answer": "Local response"}),
        ]

        with patch("sys.argv", ["preflight_chat.py", "--require-llm"]):
            self.assertEqual(preflight_chat.main(), 1)
        self.assertEqual(request_json.call_count, 2)

    @patch.dict(
        os.environ,
        {
            "DOZ_API_BASE_URL": "https://api.example.org",
            "DOZ_CHAT_TEST_TOKEN": "test-token",
        },
        clear=True,
    )
    @patch("preflight_chat.request_json")
    def test_require_llm_rejects_advice_fallback_mode(self, request_json):
        request_json.side_effect = [
            (200, {"status": "ok"}),
            (200, {"mode": "llm", "answer": "READY"}),
            (200, {"mode": "fallback", "advice": "Generic advice."}),
        ]

        with patch("sys.argv", ["preflight_chat.py", "--require-llm"]):
            self.assertEqual(preflight_chat.main(), 1)
        self.assertEqual(request_json.call_count, 3)

    @patch.dict(os.environ, {"DOZ_API_BASE_URL": "https://api.example.org"}, clear=True)
    def test_preflight_requires_test_access_token(self):
        with patch("sys.argv", ["preflight_chat.py"]):
            self.assertEqual(preflight_chat.main(), 2)


if __name__ == "__main__":
    unittest.main()
