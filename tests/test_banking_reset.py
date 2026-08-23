import sqlite3
import tempfile
import unittest
from contextlib import closing
from pathlib import Path
from unittest.mock import patch

import main
import web_app


class BankingResetTest(unittest.TestCase):
    def test_remove_santander_crud_preserves_uploaded_statement_repository(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database = root / "investments.db"
            with closing(sqlite3.connect(database)) as connection:
                with connection:
                    connection.execute("CREATE TABLE bank_statement_test_files(id INTEGER PRIMARY KEY)")
                    connection.execute("CREATE TABLE bank_santander_outflows(id INTEGER PRIMARY KEY)")
                    connection.execute("CREATE TABLE bank_santander_imports(id INTEGER PRIMARY KEY)")
                    connection.execute("CREATE TABLE bank_expense_categories(id INTEGER PRIMARY KEY)")

            with (
                patch.object(main, "INVESTMENT_DATA_DIR", root),
                patch.object(main, "INVESTMENT_DB_PATH", database),
                patch.dict(main.os.environ, {"EKT_DISABLE_POSTGRES": "1"}),
            ):
                web_app._remove_santander_crud_once()
                web_app._remove_santander_crud_once()

            with closing(sqlite3.connect(database)) as connection:
                tables = {
                    row[0]
                    for row in connection.execute(
                        "SELECT name FROM sqlite_master WHERE type='table'"
                    )
                }
            self.assertIn("bank_statement_test_files", tables)
            self.assertNotIn("bank_santander_outflows", tables)
            self.assertNotIn("bank_santander_imports", tables)
            self.assertNotIn("bank_expense_categories", tables)

    def test_reset_drops_only_retired_banking_tables_and_runs_once(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database = root / "investments.db"
            with closing(sqlite3.connect(database)) as connection:
                with connection:
                    connection.execute("CREATE TABLE investments(id INTEGER PRIMARY KEY)")
                    connection.execute("CREATE TABLE bank_accounts(id INTEGER PRIMARY KEY)")
                    connection.execute("CREATE TABLE bank_transactions(id INTEGER PRIMARY KEY)")
                    connection.execute("INSERT INTO bank_accounts(id) VALUES(1)")

            with (
                patch.object(main, "INVESTMENT_DATA_DIR", root),
                patch.object(main, "INVESTMENT_DB_PATH", database),
                patch.dict(main.os.environ, {"EKT_DISABLE_POSTGRES": "1"}),
            ):
                web_app._reset_legacy_banking_module_once()
                web_app._reset_legacy_banking_module_once()

            with closing(sqlite3.connect(database)) as connection:
                tables = {
                    row[0]
                    for row in connection.execute(
                        "SELECT name FROM sqlite_master WHERE type='table'"
                    )
                }
                marker_count = connection.execute(
                    "SELECT COUNT(*) FROM ekt_data_resets"
                ).fetchone()[0]
            self.assertIn("investments", tables)
            self.assertNotIn("bank_accounts", tables)
            self.assertNotIn("bank_transactions", tables)
            self.assertEqual(marker_count, 1)


if __name__ == "__main__":
    unittest.main()
