import asyncio
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import auth_store
import main
import web_app


async def _request(path: str, method: str, payload=None, token: str = ""):
    body = json.dumps(payload or {}).encode("utf-8")
    delivered = False
    messages = []

    async def receive():
        nonlocal delivered
        if delivered:
            return {"type": "http.request", "body": b"", "more_body": False}
        delivered = True
        return {"type": "http.request", "body": body, "more_body": False}

    async def send(message):
        messages.append(message)

    headers = [(b"content-type", b"application/json")]
    if token:
        headers.append((b"authorization", f"Bearer {token}".encode("utf-8")))
    scope = {
        "type": "http",
        "method": method,
        "path": path,
        "headers": headers,
        "client": ("192.0.2.20", 1234),
    }
    await web_app._application(scope, receive, send)
    status = next(item["status"] for item in messages if item["type"] == "http.response.start")
    response_body = next(item["body"] for item in messages if item["type"] == "http.response.body")
    return status, json.loads(response_body)


class AuthApiTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        data_directory = Path(self.temporary_directory.name)
        self.patches = [
            patch.dict(
                auth_store.os.environ,
                {
                    "EKT_DISABLE_POSTGRES": "true",
                    "INVESTMENTS_USER": "adm",
                    "INVESTMENTS_PASSWORD": "senha-legada-segura",
                    "BUDGET_SESSION_SECRET": "segredo-de-sessao-isolado-para-testes",
                },
                clear=False,
            ),
            patch.object(main, "INVESTMENT_DATA_DIR", data_directory),
            patch.object(main, "INVESTMENT_DB_PATH", data_directory / "api-auth.db"),
            patch.object(main, "prepare_budget_storage_after_login"),
            patch.object(web_app.day_trade_store, "ensure_day_trade_db"),
            patch.object(web_app, "investments_dashboard_payload", return_value={}),
        ]
        for item in self.patches:
            item.start()
        with web_app._LOGIN_RATE_LIMIT_LOCK:
            web_app._LOGIN_RATE_LIMITS.clear()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()
        self.temporary_directory.cleanup()

    def test_legacy_login_migrates_admin_and_exposes_management(self):
        status, body = asyncio.run(
            _request(
                "/api/investments/login",
                "POST",
                {"login": "adm", "password": "senha-legada-segura"},
            )
        )
        self.assertEqual(200, status)
        self.assertEqual("admin", body["user"]["role"])
        status, users = asyncio.run(
            _request("/api/admin/users", "GET", token=body["session_token"])
        )
        self.assertEqual(200, status)
        self.assertEqual(1, len(users["users"]))

    def test_viewer_cannot_mutate_financial_data(self):
        admin = auth_store.bootstrap_legacy_admin("adm", "senha-legada-segura")
        viewer = auth_store.create_user(
            "consulta", "Somente Consulta", "senha-de-consulta-forte", "viewer"
        )
        token = web_app.create_budget_api_session(viewer["login"], viewer)
        status, body = asyncio.run(
            _request("/api/budget", "POST", {"description": "teste"}, token)
        )
        self.assertEqual(403, status)
        self.assertIn("somente consultas", body["message"])
        self.assertEqual("admin", admin["role"])

    def test_all_profiles_use_the_original_company_owner_key(self):
        scope = {"headers": [(b"authorization", b"Bearer token-de-teste")]}
        with patch.dict(
            web_app.os.environ,
            {"INVESTMENTS_USER": "AdministradorOriginal"},
            clear=False,
        ), patch.object(
            web_app,
            "_session_claims_from_token",
            return_value={"user": "novo-operador", "role": "operator"},
        ):
            self.assertEqual(
                "AdministradorOriginal", web_app.authenticated_owner_key(scope)
            )


if __name__ == "__main__":
    unittest.main()
