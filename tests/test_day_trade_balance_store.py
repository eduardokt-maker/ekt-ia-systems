import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import main
import day_trade_balance_store as ledger


class BalanceStoreTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        directory = Path(self.temp.name)
        self.patches = [patch.dict(main.os.environ, {"EKT_DISABLE_POSTGRES": "true"}), patch.object(main, "INVESTMENT_DATA_DIR", directory), patch.object(main, "INVESTMENT_DB_PATH", directory / "balance.db")]
        for item in self.patches:
            item.start()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()
        self.temp.cleanup()

    def entry(self, amount, direction="Entrada", date="2026-10-02"):
        return dict(amount=amount, direction=direction, date=date, description="Manual")

    def test_starts_zero_persists_exact_cents_and_isolates_owners(self):
        self.assertEqual(0, ledger.summary("company")["balance_cents"])
        ledger.add_entry("company", self.entry("0,10"))
        ledger.add_entry("company", self.entry("0,20"))
        ledger.add_entry("company", self.entry("0,05", "Saída"))
        result = ledger.summary("company")
        self.assertEqual((30, 5, 25), (result["incoming_cents"], result["outgoing_cents"], result["balance_cents"]))
        self.assertEqual(0, ledger.summary("other")["balance_cents"])

    def test_recomputes_running_balance_for_backdated_entry(self):
        ledger.add_entry("company", self.entry("20", "Saída"))
        ledger.add_entry("company", self.entry("100", date="2026-10-01"))
        entries = ledger.summary("company")["entries"]
        self.assertEqual([8000, 10000], [item["balance_cents"] for item in entries])

    def test_rejects_invalid_amount_without_changing_balance(self):
        for amount in ["NaN", "Infinity", "-1", "0", "0.001", "9999999999999"]:
            with self.subTest(amount=amount), self.assertRaises(ValueError):
                ledger.add_entry("company", self.entry(amount))
        self.assertEqual([], ledger.summary("company")["entries"])
