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

    def test_month_status_is_persistent_and_controls_future_imports(self) -> None:
        self.assertEqual(main.monthly_budget_period_status("2026-08"), "open")
        self.assertFalse(main.monthly_budget_period_allows_import("2026-08"))

        self.assertTrue(
            main.set_monthly_budget_period_status("2026-08", "closed")
        )
        self.assertEqual(main.monthly_budget_period_status("2026-08"), "closed")
        self.assertTrue(main.monthly_budget_period_allows_import("2026-08"))
        self.assertEqual(
            web_app.budget_payload("2026-08")["month_status"], "closed"
        )

        self.assertTrue(main.set_monthly_budget_period_status("2026-08", "open"))
        self.assertFalse(main.monthly_budget_period_allows_import("2026-08"))

    def test_month_status_rejects_invalid_values(self) -> None:
        with self.assertRaisesRegex(ValueError, "referência inválido"):
            main.set_monthly_budget_period_status("08/2026", "closed")
        with self.assertRaisesRegex(ValueError, "Status mensal inválido"):
            main.set_monthly_budget_period_status("2026-08", "archived")

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

    def test_expense_nature_crud_normalization_and_integrity(self) -> None:
        nature_id = main.save_expense_nature("  Alimentação  ")
        with self.assertRaisesRegex(ValueError, "Já existe"):
            main.save_expense_nature("alimentacao")
        self.assertTrue(main.update_expense_nature(nature_id, name="Mercado"))
        self.assertTrue(main.update_expense_nature(nature_id, active=False))
        self.assertFalse(main.list_expense_natures()[0]["active"])
        self.assertTrue(main.update_expense_nature(nature_id, active=True))

        item_id = main.save_monthly_budget_item(
            "2026-07", "Despesa", "COMPRAS", "100,00", "2026-07-10",
            None, False, expense_nature_id=nature_id,
        )
        item = main.load_monthly_budget_items()[0]
        self.assertEqual(item["expense_nature_id"], nature_id)
        self.assertEqual(item["expense_nature_name"], "Mercado")
        with self.assertRaisesRegex(ValueError, "vinculada"):
            main.delete_expense_nature(nature_id)
        self.assertEqual(item_id, item["id"])

    def test_legacy_expense_remains_visible_without_category(self) -> None:
        main.ensure_monthly_budget_db()
        with sqlite3.connect(main.INVESTMENT_DB_PATH) as connection:
            connection.execute(
                """INSERT INTO monthly_budget_items
                   (owner_key,reference_month,item_type,description,amount_text,due_date,settled,created_at)
                   VALUES (?,?,?,?,?,?,?,?)""",
                (main.DEFAULT_BUDGET_OWNER_KEY, "2026-07-01", "Despesa",
                 "LEGADO", "25,00", "2026-07-10", 0, "2026-07-01"),
            )
        item = main.load_monthly_budget_items()[0]
        self.assertIsNone(item["expense_nature_id"])
        self.assertIsNone(item["expense_nature_name"])

    def test_batch_categorization_only_updates_owned_expenses(self) -> None:
        nature_id = main.save_expense_nature("Moradia")
        first = main.save_monthly_budget_item(
            "2026-07", "Despesa", "ALUGUEL", "900,00", "2026-07-10", None, False)
        second = main.save_monthly_budget_item(
            "2026-07", "Despesa", "LUZ", "90,00", "2026-07-11", None, False)
        revenue = main.save_monthly_budget_item(
            "2026-07", "Receita", "SALARIO", "1000,00", "2026-07-05", None,
            False, tipo_receita="OUTROS", tipo_receita_outros="Salário")
        self.assertEqual(main.categorize_expenses([first, second, revenue], nature_id), 2)
        by_id = {item["id"]: item for item in main.load_monthly_budget_items()}
        self.assertEqual(by_id[first]["expense_nature_id"], nature_id)
        self.assertEqual(by_id[second]["expense_nature_id"], nature_id)
        self.assertIsNone(by_id[revenue]["expense_nature_id"])

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

    def test_database_preserves_long_multiline_observation(self) -> None:
        observation = "Pagamento no cartão.\n" + ("Detalhes da despesa. " * 20)
        main.save_monthly_budget_item(
            "2026-07",
            "Despesa",
            "REFORMA",
            "500,00",
            "2026-07-25",
            None,
            False,
            observation=observation,
        )

        items = main.load_monthly_budget_items("2026-07")
        self.assertEqual(items[0]["observation"], observation)
        self.assertGreater(len(items[0]["observation"]), 20)

    def test_partial_receipt_reduces_balance_and_enters_caixa(self) -> None:
        payload = web_app.validated_budget_payload(
            {
                "reference_month": "2026-07",
                "item_type": "Receita",
                "tipo_receita": "ALUGUEL",
                "description": "Casiotone",
                "amount_text": "5.100,00",
                "received_amount_text": "1.100,00",
                "due_date": "2026-07-22",
                "settled": False,
            }
        )
        item_id = main.save_monthly_budget_item(**payload)

        item = main.load_monthly_budget_items("2026-07")[0]
        self.assertEqual(item["amount_text"], "5.100,00")
        self.assertEqual(item["received_amount_text"], "1.100,00")
        self.assertFalse(item["settled"])
        caixa = main.load_caixa_entries()
        self.assertEqual(len(caixa), 1)
        self.assertEqual(caixa[0]["source_budget_item_id"], item_id)
        self.assertEqual(caixa[0]["amount_text"], "1.100,00")

        full = web_app.validated_budget_payload(
            {
                "reference_month": "2026-07",
                "item_type": "Receita",
                "tipo_receita": "ALUGUEL",
                "description": "Casiotone",
                "amount_text": "5.100,00",
                "received_amount_text": "5.100,00",
                "due_date": "2026-07-22",
                "settled": False,
            }
        )
        self.assertTrue(full["settled"])
        self.assertTrue(main.update_monthly_budget_item(str(item_id), **full))
        self.assertEqual(main.load_caixa_entries()[0]["amount_text"], "5.100,00")

    def test_blank_partial_receipt_is_zero(self) -> None:
        payload = web_app.validated_budget_payload(
            {
                "reference_month": "2026-07",
                "item_type": "Receita",
                "tipo_receita": "DAY_TRADE",
                "description": "Eduardok",
                "amount_text": "700,00",
                "received_amount_text": "",
                "due_date": "2026-07-22",
                "settled": False,
            }
        )
        self.assertEqual(payload["received_amount_text"], "0,00")
        self.assertFalse(payload["settled"])
        self.assertIsNone(payload["payment_date"])

    def test_api_assigns_receipt_date_and_clears_it_when_reopened(self) -> None:
        received = web_app.validated_budget_payload(
            {
                "reference_month": "2026-07",
                "item_type": "Receita",
                "tipo_receita": "ALUGUEL",
                "description": "Cliente",
                "observation": "Observacao com mais de vinte caracteres",
                "amount_text": "100,00",
                "due_date": "2026-07-20",
                "settled": True,
            }
        )
        self.assertTrue(received["payment_date"])
        self.assertEqual(
            received["observation"],
            "Observacao com mais de vinte caracteres",
        )

        reopened = web_app.validated_budget_payload(
            {
                "reference_month": "2026-07",
                "item_type": "Receita",
                "tipo_receita": "ALUGUEL",
                "description": "Cliente",
                "amount_text": "100,00",
                "due_date": "2026-07-20",
                "payment_date": "2026-07-19",
                "settled": False,
            }
        )
        self.assertIsNone(reopened["payment_date"])

    def test_api_preserves_multiline_observation_up_to_500_characters(self) -> None:
        observation = "Primeira linha\n  Segunda linha preservada. " + ("x" * 430)
        payload = web_app.validated_budget_payload(
            {
                "reference_month": "2026-07",
                "item_type": "Despesa",
                "description": "Escola",
                "observation": observation,
                "amount_text": "100,00",
                "due_date": "2026-07-20",
                "settled": False,
            }
        )
        self.assertEqual(payload["observation"], observation)

    def test_revenue_types_are_validated_normalized_and_persisted(self) -> None:
        aluguel = web_app.validated_budget_payload(
            {
                "reference_month": "2026-07",
                "item_type": "Receita",
                "tipo_receita": "aluguel",
                "description": "Imovel",
                "amount_text": "1.000,00",
                "due_date": "2026-07-20",
                "settled": False,
            }
        )
        aluguel_id = main.save_monthly_budget_item(**aluguel)
        outros = web_app.validated_budget_payload(
            {
                "reference_month": "2026-07",
                "item_type": "Receita",
                "tipo_receita": "OUTROS",
                "tipo_receita_outros": "  Dividendos  ",
                "description": "Carteira",
                "amount_text": "500,00",
                "due_date": "2026-07-21",
                "settled": False,
            }
        )
        outros_id = main.save_monthly_budget_item(**outros)

        items = {
            item["id"]: item for item in main.load_monthly_budget_items("2026-07")
        }
        self.assertEqual(items[aluguel_id]["tipo_receita"], "ALUGUEL")
        self.assertIsNone(items[aluguel_id]["tipo_receita_outros"])
        self.assertEqual(items[outros_id]["tipo_receita"], "OUTROS")
        self.assertEqual(items[outros_id]["tipo_receita_outros"], "Dividendos")

    def test_revenue_type_rejects_missing_invalid_and_blank_other(self) -> None:
        base = {
            "reference_month": "2026-07",
            "item_type": "Receita",
            "description": "Cliente",
            "amount_text": "100,00",
            "due_date": "2026-07-20",
            "settled": False,
        }
        with self.assertRaisesRegex(ValueError, "Selecione o tipo de receita"):
            web_app.validated_budget_payload(base)
        with self.assertRaisesRegex(ValueError, "Tipo de receita inválido"):
            web_app.validated_budget_payload(
                {**base, "tipo_receita": "DIVIDENDOS"}
            )
        with self.assertRaisesRegex(ValueError, "Especifique o tipo de receita"):
            web_app.validated_budget_payload(
                {
                    **base,
                    "tipo_receita": "OUTROS",
                    "tipo_receita_outros": "   ",
                }
            )

    def test_changing_other_to_fixed_type_clears_other_description(self) -> None:
        payload = web_app.validated_budget_payload(
            {
                "reference_month": "2026-07",
                "item_type": "Receita",
                "tipo_receita": "OUTROS",
                "tipo_receita_outros": "Juros sobre capital próprio",
                "description": "Proventos",
                "amount_text": "100,00",
                "due_date": "2026-07-20",
                "settled": False,
            }
        )
        item_id = main.save_monthly_budget_item(**payload)
        changed = web_app.validated_budget_payload(
            {
                **payload,
                "tipo_receita": "DAY_TRADE",
                "tipo_receita_outros": "não deve permanecer",
            }
        )
        self.assertTrue(main.update_monthly_budget_item(str(item_id), **changed))
        item = main.load_monthly_budget_items("2026-07")[0]
        self.assertEqual(item["tipo_receita"], "DAY_TRADE")
        self.assertIsNone(item["tipo_receita_outros"])

    def test_legacy_revenue_remains_uncategorized_after_migration(self) -> None:
        item_id = main.save_monthly_budget_item(
            "2026-07",
            "Receita",
            "LEGADO",
            "100,00",
            "2026-07-20",
            None,
            False,
        )
        item = main.load_monthly_budget_items("2026-07")[0]
        self.assertEqual(item["id"], item_id)
        self.assertIsNone(item["tipo_receita"])
        self.assertIsNone(item["tipo_receita_outros"])

    def test_expense_reference_due_and_payment_months_are_independent(self) -> None:
        payload = web_app.validated_budget_payload(
            {
                "reference_month": "2026-07",
                "item_type": "Despesa",
                "description": "Energia",
                "amount_text": "350,00",
                "due_date": "2026-08-10",
                "payment_date": "2026-09-02",
                "settled": True,
            }
        )
        item_id = main.save_monthly_budget_item(**payload)
        item = main.load_monthly_budget_items("2026-07")[0]

        self.assertEqual(item["id"], item_id)
        self.assertEqual(item["reference_month"], "2026-07")
        self.assertEqual(item["due_date"], "2026-08-10")
        self.assertEqual(item["payment_date"], "2026-09-02")

    def test_editing_reference_month_preserves_due_and_payment_dates(self) -> None:
        item_id = main.save_monthly_budget_item(
            "2026-07",
            "Despesa",
            "CONDOMINIO",
            "800,00",
            "2026-08-05",
            "2026-08-06",
            True,
        )
        self.assertTrue(
            main.update_monthly_budget_item(
                str(item_id),
                "2026-06",
                "Despesa",
                "CONDOMINIO",
                "800,00",
                "2026-08-05",
                "2026-08-06",
                True,
            )
        )
        item = main.load_monthly_budget_items("2026-06")[0]
        self.assertEqual(item["reference_month"], "2026-06")
        self.assertEqual(item["due_date"], "2026-08-05")
        self.assertEqual(item["payment_date"], "2026-08-06")

    def test_expense_reference_month_is_required_and_validated_by_api(self) -> None:
        base = {
            "item_type": "Despesa",
            "description": "Escola",
            "amount_text": "100,00",
            "due_date": "2026-08-10",
            "settled": False,
        }
        for invalid in ("", "julho/2026", "2026-13", "1900-01"):
            with self.subTest(invalid=invalid):
                with self.assertRaisesRegex(
                    ValueError, "Informe o mês de referência da despesa"
                ):
                    web_app.validated_budget_payload(
                        {**base, "reference_month": invalid}
                    )

    def test_budget_date_indexes_are_created(self) -> None:
        main.ensure_monthly_budget_db()
        with sqlite3.connect(main.INVESTMENT_DB_PATH) as connection:
            indexes = {
                row[1]
                for row in connection.execute(
                    "PRAGMA index_list(monthly_budget_items)"
                ).fetchall()
            }
        self.assertIn("idx_monthly_budget_owner_month", indexes)
        self.assertIn("idx_monthly_budget_owner_due_date", indexes)
        self.assertIn("idx_monthly_budget_owner_payment_date", indexes)

    def test_general_listing_includes_legacy_item_without_reference(self) -> None:
        main.ensure_monthly_budget_db()
        with sqlite3.connect(main.INVESTMENT_DB_PATH) as connection:
            connection.execute(
                """
                INSERT INTO monthly_budget_items (
                    owner_key, reference_month, item_type, description,
                    observation, amount_text, received_amount_text,
                    due_date, payment_date, settled, created_at
                ) VALUES (?, NULL, 'Despesa', 'REGISTRO LEGADO', '',
                          '75,00', '0,00', '2026-06-10', NULL, 0,
                          '2026-06-01T00:00:00')
                """,
                (main.DEFAULT_BUDGET_OWNER_KEY,),
            )
        new_id = main.save_monthly_budget_item(
            "2026-07", "Despesa", "REGISTRO NOVO", "100,00",
            "2026-07-10", None, False,
        )

        payload = web_app.budget_payload()

        self.assertTrue(payload["ok"])
        self.assertEqual(len(payload["items"]), 2)
        by_description = {item["description"]: item for item in payload["items"]}
        self.assertEqual(by_description["REGISTRO LEGADO"]["reference_month"], "")
        self.assertEqual(by_description["REGISTRO NOVO"]["id"], new_id)
        self.assertEqual(
            [item["description"] for item in main.load_monthly_budget_items("2026-07")],
            ["REGISTRO NOVO"],
        )

    def test_api_rejects_observation_over_500_characters_without_truncating(self) -> None:
        with self.assertRaisesRegex(ValueError, "500 caracteres"):
            web_app.validated_budget_payload(
                {
                    "reference_month": "2026-07",
                    "item_type": "Despesa",
                    "description": "Escola",
                    "observation": "x" * 501,
                    "amount_text": "100,00",
                    "due_date": "2026-07-20",
                    "settled": False,
                }
            )

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

    def test_expense_description_history_is_unique_and_cross_period(self) -> None:
        main.save_monthly_budget_item(
            "2026-01", "Despesa", "ENERGIA", "100,00", "2026-01-10",
            None, False,
        )
        main.save_monthly_budget_item(
            "2026-02", "Despesa", "ENERGIA", "110,00", "2026-02-10",
            None, False,
        )
        main.save_monthly_budget_item(
            "2026-03", "Despesa", "ÁGUA", "80,00", "2026-03-10",
            None, False,
        )
        main.save_monthly_budget_item(
            "2026-03", "Receita", "ENERGIA SOLAR", "500,00", "2026-03-10",
            None, False,
        )

        suggestions = main.list_budget_expense_descriptions()

        self.assertEqual(suggestions.count("ENERGIA"), 1)
        self.assertIn("ÁGUA", suggestions)
        self.assertNotIn("ENERGIA SOLAR", suggestions)


if __name__ == "__main__":
    unittest.main()
