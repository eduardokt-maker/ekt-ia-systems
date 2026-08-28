import unittest
from unittest.mock import patch

import web_app


def _scope(token: str) -> dict:
    return {
        "headers": [
            (b"authorization", f"Bearer {token}".encode("utf-8")),
        ]
    }


class BudgetSessionTest(unittest.TestCase):
    def setUp(self):
        with web_app._LOGIN_RATE_LIMIT_LOCK:
            web_app._LOGIN_RATE_LIMITS.clear()

    def test_session_secret_does_not_fall_back_to_login_password(self):
        with patch.dict(
            web_app.os.environ,
            {"INVESTMENTS_PASSWORD": "senha-nao-deve-assinar-sessoes"},
            clear=False,
        ):
            web_app.os.environ.pop("BUDGET_SESSION_SECRET", None)
            with self.assertRaises(RuntimeError):
                web_app._budget_session_secret()

    def test_login_rate_limit_is_progressive_and_resets_after_success(self):
        keys = ("ip:192.0.2.10", "login:teste")
        with patch.object(web_app, "LOGIN_MAX_FAILURES", 2), patch.object(
            web_app, "LOGIN_INITIAL_BLOCK_SECONDS", 60
        ), patch.object(web_app, "LOGIN_MAX_BLOCK_SECONDS", 3600):
            self.assertEqual(0, web_app._record_login_failure(keys, now=100))
            self.assertEqual(60, web_app._record_login_failure(keys, now=101))
            self.assertEqual(60, web_app._login_retry_after(keys, now=101))
            self.assertEqual(0, web_app._record_login_failure(keys, now=162))
            self.assertEqual(120, web_app._record_login_failure(keys, now=163))
            web_app._clear_login_failures(keys)
            self.assertEqual(0, web_app._login_retry_after(keys, now=163))

    def test_signed_session_survives_without_process_memory(self):
        with patch.dict(
            web_app.os.environ,
            {"BUDGET_SESSION_SECRET": "stable-test-secret"},
            clear=False,
        ):
            with patch.object(web_app.time, "time", return_value=1_000):
                token = web_app.create_budget_api_session()
            with patch.object(web_app.time, "time", return_value=1_100):
                self.assertTrue(web_app.has_valid_budget_api_session(_scope(token)))

    def test_rejects_tampered_and_expired_sessions(self):
        with patch.dict(
            web_app.os.environ,
            {"BUDGET_SESSION_SECRET": "stable-test-secret"},
            clear=False,
        ):
            with patch.object(web_app.time, "time", return_value=1_000):
                token = web_app.create_budget_api_session()
            encoded, signature = token.split(".", 1)
            tampered = f"{encoded[:-1]}A.{signature}"
            self.assertFalse(web_app.has_valid_budget_api_session(_scope(tampered)))
            with patch.object(
                web_app.time,
                "time",
                return_value=1_000 + web_app.BUDGET_API_SESSION_TTL_SECONDS + 1,
            ):
                self.assertFalse(web_app.has_valid_budget_api_session(_scope(token)))

    def test_refresh_token_outlives_access_and_cannot_authorize_requests(self):
        with patch.dict(
            web_app.os.environ,
            {"BUDGET_SESSION_SECRET": "stable-test-secret"},
            clear=False,
        ):
            with patch.object(web_app.time, "time", return_value=1_000):
                access = web_app.create_budget_api_session("usuario")
                refresh = web_app.create_budget_refresh_token("usuario")
                self.assertTrue(
                    web_app.has_valid_budget_api_session(_scope(access))
                )
                self.assertFalse(
                    web_app.has_valid_budget_api_session(_scope(refresh))
                )
                claims = web_app._session_claims_from_token(refresh, "refresh")
                self.assertEqual("usuario", claims["user"])

            with patch.object(
                web_app.time,
                "time",
                return_value=1_000 + web_app.ACCESS_TOKEN_TTL_SECONDS + 1,
            ):
                self.assertFalse(web_app.has_valid_budget_api_session(_scope(access)))
                self.assertIsNotNone(
                    web_app._session_claims_from_token(refresh, "refresh")
                )


if __name__ == "__main__":
    unittest.main()
