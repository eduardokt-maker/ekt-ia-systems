import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import auth_store
import main


class AuthStoreTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.data_directory = Path(self.temporary_directory.name)
        self.database_path = self.data_directory / "auth-test.db"
        self.environment = patch.dict(
            auth_store.os.environ,
            {
                "EKT_DISABLE_POSTGRES": "true",
                "INVESTMENTS_USER": "administrador",
                "INVESTMENTS_PASSWORD": "senha-legada-segura",
            },
            clear=False,
        )
        self.data_patch = patch.object(
            main, "INVESTMENT_DATA_DIR", self.data_directory
        )
        self.path_patch = patch.object(main, "INVESTMENT_DB_PATH", self.database_path)
        self.environment.start()
        self.data_patch.start()
        self.path_patch.start()

    def tearDown(self):
        self.path_patch.stop()
        self.data_patch.stop()
        self.environment.stop()
        self.temporary_directory.cleanup()

    def test_bootstraps_legacy_credential_as_first_admin(self):
        user = auth_store.bootstrap_legacy_admin(
            "administrador", "senha-legada-segura"
        )
        self.assertEqual("admin", user["role"])
        authenticated = auth_store.authenticate(
            "ADMINISTRADOR", "senha-legada-segura"
        )
        self.assertIsNotNone(authenticated)
        self.assertNotIn("password_hash", authenticated)
        self.assertIsNone(
            auth_store.bootstrap_legacy_admin(
                "administrador", "senha-legada-segura"
            )
        )

    def test_creates_roles_and_invalidates_sessions_after_password_change(self):
        auth_store.bootstrap_legacy_admin("administrador", "senha-legada-segura")
        operator = auth_store.create_user(
            "operador", "Operador Financeiro", "Senha1234", "operator"
        )
        old_version = operator["token_version"]
        updated = auth_store.change_password(
            operator["id"], "Senha1234", "OutraSenha5678"
        )
        self.assertGreater(updated["token_version"], old_version)
        self.assertIsNone(auth_store.authenticate("operador", "Senha1234"))
        self.assertIsNotNone(
            auth_store.authenticate("operador", "OutraSenha5678")
        )

    def test_rejects_short_passwords_and_duplicate_logins(self):
        auth_store.bootstrap_legacy_admin("administrador", "senha-legada-segura")
        with self.assertRaises(ValueError):
            auth_store.create_user("consulta", "Consulta", "curta", "viewer")
        auth_store.create_user(
            "consulta", "Consulta", "Consulta99", "viewer"
        )
        with self.assertRaises(ValueError):
            auth_store.create_user(
                "CONSULTA", "Duplicado", "OutraSenha123", "viewer"
            )

    def test_accepts_letters_numbers_or_both_and_rejects_symbols(self):
        auth_store.bootstrap_legacy_admin("administrador", "senha-legada-segura")
        self.assertEqual(
            "viewer",
            auth_store.create_user("letras", "Letras", "noveletras", "viewer")[
                "role"
            ],
        )
        self.assertEqual(
            "viewer",
            auth_store.create_user("numeros", "Números", "123456789", "viewer")[
                "role"
            ],
        )
        with self.assertRaises(ValueError):
            auth_store.create_user(
                "simbolos", "Símbolos", "Senha123!", "viewer"
            )


if __name__ == "__main__":
    unittest.main()
