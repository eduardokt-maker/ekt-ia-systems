import os
import shutil
import sqlite3
import tempfile
import unittest
from pathlib import Path

import main
import web_app


class BudgetCashRulesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = Path(tempfile.mkdtemp())
        self.original_paths = (
            main.INVESTMENT_DATA_DIR,
            main.INVESTMENT_DB_PATH,
            main.LEGACY_INVESTMENT_DB_PATH,
        )
        self.original_database_url = os.environ.pop("DATABASE_URL", None)
        self.original_investment_url = os.environ.pop("INVESTMENT_DATABASE_URL", None)
        main.INVESTMENT_DATA_DIR = self.temp_dir
        main.INVESTMENT_DB_PATH = self.temp_dir / "budget-test.db"
        main.LEGACY_INVESTMENT_DB_PATH = self.temp_dir / "legacy.db"

    def tearDown(self) -> None:
        (
            main.INVESTMENT_DATA_DIR,
            main.INVESTMENT_DB_PATH,
            main.LEGACY_INVESTMENT_DB_PATH,
        ) = self.original_paths
        if self.original_database_url is not None:
            os.environ["DATABASE_URL"] = self.original_database_url
        if self.original_investment_url is not None:
            os.environ["INVESTMENT_DATABASE_URL"] = self.original_investment_url
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_received_revenue_is_synchronized_without_duplicates(self) -> None:
        item_id = main.save_monthly_budget_item(
            "2026-07", "Receita", "CLIENTE", "1.500,00", "2026-07-10", None, False,
            observation="CONTRATO INICIAL",
        )

        self.assertTrue(main.update_monthly_budget_item_status(str(item_id), True))
        entries = main.load_caixa_entries()
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["source_budget_item_id"], item_id)
        self.assertTrue(entries[0]["payment_date"])

        self.assertTrue(
            main.update_monthly_budget_item(
                str(item_id),
                "2026-07",
                "Receita",
                "CLIENTE VIP",
                "2.000,00",
                "2026-07-11",
                "2026-07-12",
                True,
                observation="PIX CONFIRMADO",
            )
        )
        entries = main.load_caixa_entries()
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["description"], "CLIENTE VIP")
        self.assertEqual(entries[0]["amount_text"], "2.000,00")
        self.assertEqual(entries[0]["payment_date"], "2026-07-12")
        self.assertEqual(entries[0]["observation"], "PIX CONFIRMADO")

    def test_reopening_revenue_removes_it_from_caixa(self) -> None:
        item_id = main.save_monthly_budget_item(
            "2026-07", "Receita", "CLIENTE", "500,00", "2026-07-10", None, True
        )
        self.assertEqual(len(main.load_caixa_entries()), 1)

        self.assertTrue(main.update_monthly_budget_item_status(str(item_id), False))
        self.assertEqual(main.load_caixa_entries(), [])
        with sqlite3.connect(main.INVESTMENT_DB_PATH) as connection:
            payment_date = connection.execute(
                "SELECT payment_date FROM monthly_budget_items WHERE id = ?", (item_id,)
            ).fetchone()[0]
        self.assertIsNone(payment_date)

    def test_api_assigns_receipt_date_and_clears_it_when_reopened(self) -> None:
        received = web_app.validated_budget_payload(
            {
                "reference_month": "2026-07",
                "item_type": "Receita",
                "description": "Cliente",
                "observation": "Observacao com mais de vinte caracteres",
                "amount_text": "100,00",
                "due_date": "2026-07-20",
                "settled": True,
            }
        )
        self.assertTrue(received["payment_date"])
        self.assertEqual(received["observation"], "Observacao com mais ")

        reopened = web_app.validated_budget_payload(
            {
                "reference_month": "2026-07",
                "item_type": "Receita",
                "description": "Cliente",
                "amount_text": "100,00",
                "due_date": "2026-07-20",
                "payment_date": "2026-07-19",
                "settled": False,
            }
        )
        self.assertIsNone(reopened["payment_date"])

    def test_yearly_bi_loads_only_selected_year_with_complete_records(self) -> None:
        main.save_monthly_budget_item(
            "2026-01", "Receita", "CLIENTE A", "800,00", "2026-01-10",
            "2026-01-10", True, observation="PIX RECEBIDO",
        )
        main.save_monthly_budget_item(
            "2026-12", "Despesa", "FORNECEDOR", "250,00", "2026-12-20",
            None, False, observation="A VENCER",
        )
        main.save_monthly_budget_item(
            "2027-01", "Receita", "CLIENTE B", "900,00", "2027-01-05",
            None, False,
        )

        items = main.load_yearly_budget_items(2026)

        self.assertEqual(len(items), 2)
        self.assertEqual(
            [item["reference_month"] for item in items],
            ["2026-01", "2026-12"],
        )
        self.assertEqual(items[0]["observation"], "PIX RECEBIDO")
        self.assertTrue(items[0]["settled"])
        self.assertEqual(items[1]["observation"], "A VENCER")
        self.assertFalse(items[1]["settled"])


if __name__ == "__main__":
    unittest.main()
