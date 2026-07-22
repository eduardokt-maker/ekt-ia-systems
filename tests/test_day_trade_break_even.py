import os
import shutil
import sqlite3
import tempfile
import unittest
from pathlib import Path

import day_trade_store
import main
import web_app


class DayTradeBreakEvenRulesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = Path(tempfile.mkdtemp())
        self.original_paths = (
            main.INVESTMENT_DATA_DIR,
            main.INVESTMENT_DB_PATH,
            main.LEGACY_INVESTMENT_DB_PATH,
        )
        self.original_database_url = os.environ.pop("DATABASE_URL", None)
        self.original_investment_url = os.environ.pop(
            "INVESTMENT_DATABASE_URL", None
        )
        main.INVESTMENT_DATA_DIR = self.temp_dir
        main.INVESTMENT_DB_PATH = self.temp_dir / "day-trade-test.db"
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

    def payload(self, **changes):
        source = {
            "trade_date": "2026-07-21",
            "entry_time": "10:30",
            "asset": "WINQ26",
            "market": "Mini índice",
            "direction": "Compra",
            "quantity": 2,
            "entry_price_text": "135000",
            "strategy": "Rompimento",
            "operation_result": "BREAK_EVEN",
            "costs_text": "4,50",
            "notes": "Proteção de capital",
        }
        source.update(changes)
        return web_app.validated_day_trade_payload(source)

    def test_buy_break_even_with_entry_forces_equal_exit_and_zero_gross(self):
        item = self.payload()
        day_trade_store.create_operation(item)

        saved = day_trade_store.list_operations("2026-07-21")[0]
        self.assertEqual(saved["direction"], "Compra")
        self.assertEqual(saved["operation_result"], "BREAK_EVEN")
        self.assertEqual(saved["result_type"], "BREAK_EVEN")
        self.assertEqual(saved["entry_price_text"], saved["exit_price_text"])
        self.assertEqual(saved["points_result"], 0)
        self.assertEqual(saved["gross_result"], 0)
        self.assertEqual(saved["net_result"], -4.5)

    def test_sell_break_even_without_prices_is_supported(self):
        item = self.payload(
            direction="Venda", entry_price_text="", costs_text="0"
        )
        day_trade_store.create_operation(item)

        saved = day_trade_store.list_operations("2026-07-21")[0]
        self.assertEqual(saved["direction"], "Venda")
        self.assertEqual(saved["entry_price_text"], "")
        self.assertEqual(saved["exit_price_text"], "")
        self.assertEqual(saved["gross_result"], 0)
        self.assertEqual(saved["net_result"], 0)

    def test_backend_rejects_nonzero_break_even_result(self):
        with self.assertRaisesRegex(ValueError, "resultado operacional igual a zero"):
            self.payload(gross_result="1,00")

    def test_break_even_is_neither_win_nor_loss_and_is_outside_win_rate(self):
        day_trade_store.create_operation(self.payload())
        day_trade_store.create_operation(
            web_app.validated_day_trade_payload(
                {
                    "trade_date": "2026-07-21",
                    "entry_time": "11:00",
                    "asset": "WINQ26",
                    "market": "Mini índice",
                    "direction": "Compra",
                    "quantity": 1,
                    "entry_price_text": "135000",
                    "stop_price_text": "134900",
                    "target_price_text": "135200",
                    "strategy": "Rompimento",
                    "operation_result": "Gain",
                }
            )
        )
        day_trade_store.create_operation(
            web_app.validated_day_trade_payload(
                {
                    "trade_date": "2026-07-21",
                    "entry_time": "12:00",
                    "asset": "WINQ26",
                    "market": "Mini índice",
                    "direction": "Venda",
                    "quantity": 1,
                    "entry_price_text": "135000",
                    "stop_price_text": "135100",
                    "target_price_text": "134800",
                    "strategy": "Reversão",
                    "operation_result": "stop loss",
                }
            )
        )

        summary = day_trade_store.build_payload("2026-07-21")["summary"]
        self.assertEqual(summary["gains"], 1)
        self.assertEqual(summary["losses"], 1)
        self.assertEqual(summary["break_evens"], 1)
        self.assertAlmostEqual(summary["win_rate"], 50)
        self.assertAlmostEqual(summary["break_even_percent"], 100 / 3)
        self.assertEqual(summary["break_even_gross_result"], 0)
        self.assertEqual(summary["break_even_net_result"], -4.5)
        self.assertEqual(summary["break_even_costs"], 4.5)

    def test_editing_legacy_operation_to_break_even_preserves_record(self):
        day_trade_store.ensure_day_trade_db()
        legacy = self.payload(
            operation_result="Gain",
            stop_price_text="134900",
            target_price_text="135200",
        )
        item_id = day_trade_store.create_operation(legacy)
        self.assertTrue(day_trade_store.update_operation(str(item_id), self.payload()))

        saved = day_trade_store.list_operations("2026-07-21")[0]
        self.assertEqual(saved["id"], item_id)
        self.assertEqual(saved["result_type"], "BREAK_EVEN")
        self.assertEqual(saved["gross_result"], 0)

        normal = web_app.validated_day_trade_payload(
            {
                "trade_date": "2026-07-21",
                "entry_time": "10:30",
                "asset": "WINQ26",
                "market": "Mini índice",
                "direction": "Compra",
                "quantity": 2,
                "entry_price_text": "135000",
                "stop_price_text": "134900",
                "target_price_text": "135200",
                "strategy": "Rompimento",
                "operation_result": "Gain",
            }
        )
        self.assertTrue(day_trade_store.update_operation(str(item_id), normal))
        restored = day_trade_store.list_operations("2026-07-21")[0]
        self.assertEqual(restored["result_type"], "WIN")
        self.assertGreater(restored["gross_result"], 0)

    def test_existing_zero_record_is_classified_as_break_even_for_bi(self):
        day_trade_store.ensure_day_trade_db()
        with sqlite3.connect(main.INVESTMENT_DB_PATH) as connection:
            connection.execute(
                """
                INSERT INTO day_trade_operations (
                    owner_key, trade_date, trade_weekday, entry_time, exit_time,
                    asset, market, direction, quantity, entry_price_text,
                    exit_price_text, point_value_text, stop_price_text,
                    target_price_text, costs_text, strategy, exit_reason,
                    operation_status, notes, status, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "adm", "2026-07-21", "terça-feira", "13:00", "13:05",
                    "WINQ26", "Mini índice", "Compra", 1, "135000", "135000",
                    "0.20", "134900", "135100", "0", "Legado", "Manual",
                    "", "", "ENCERRADA", "2026-07-21T13:05:00",
                ),
            )

        saved = day_trade_store.list_operations("2026-07-21")[0]
        self.assertEqual(saved["operation_result"], "")
        self.assertEqual(saved["result_type"], "BREAK_EVEN")

    def test_financial_tolerance_classifies_residual_as_break_even(self):
        self.assertEqual(
            day_trade_store.operation_outcome({"net_result": "0.009"}),
            "BREAK_EVEN",
        )
        self.assertEqual(
            day_trade_store.operation_outcome({"net_result": "-0.009"}),
            "BREAK_EVEN",
        )


if __name__ == "__main__":
    unittest.main()
