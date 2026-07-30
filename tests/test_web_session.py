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
