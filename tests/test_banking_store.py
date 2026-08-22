import tempfile
import unittest
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from unittest.mock import patch

import banking_store
import main


class BankingStoreTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name)
        self.patches = (
            patch.object(main, "INVESTMENT_DATA_DIR", root),
            patch.object(main, "INVESTMENT_DB_PATH", root / "investments.db"),
            patch.object(main, "LEGACY_INVESTMENT_DB_PATH", root / "legacy.db"),
            patch.dict(main.os.environ, {"EKT_DISABLE_POSTGRES": "1"}),
        )
        for item in self.patches:
            item.start()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()
        self.temp.cleanup()

    def test_foundation_persists_and_transfer_does_not_distort_result(self):
        owner = "usuario-teste"
        account_a = banking_store.save_account(owner, {
            "bank_name": "Banco A", "description": "Conta principal",
            "account_type": "Corrente", "holder": "Eduardo",
            "opening_balance": "500,00", "opening_date": "2026-08-01",
        })
        account_b = banking_store.save_account(owner, {
            "bank_name": "Banco B", "description": "Reserva",
            "account_type": "Poupança", "holder": "Eduardo",
            "opening_balance": "0", "opening_date": "2026-08-01",
        })
        category = banking_store.save_category(owner, {
            "category_type": "INCOME", "name": "Receita teste",
        })
        banking_store.save_transaction(owner, {
            "transaction_date": "2026-08-10", "transaction_type": "INCOME",
            "description": "Crédito", "category_id": category,
            "amount": "1.000,00", "account_id": account_a,
            "reference_month": "2026-08",
        })
        banking_store.save_transaction(owner, {
            "transaction_date": "2026-08-11", "transaction_type": "TRANSFER",
            "description": "Reserva própria", "amount": "200,00",
            "account_id": account_a, "destination_account_id": account_b,
            "reference_month": "2026-08",
        })

        payload = banking_store.banking_payload(owner, "2026-08")
        self.assertEqual(payload["summary"]["income_text"], "1.000,00")
        self.assertEqual(payload["summary"]["expenses_text"], "0,00")
        self.assertEqual(payload["summary"]["result_text"], "1.000,00")
        self.assertEqual(payload["summary"]["available_balance_text"], "1.500,00")
        self.assertEqual(len(payload["transactions"]), 2)
        self.assertEqual(payload["transactions"][0]["transfer_identifier"], "TRANSFER-2")
        individual_a = banking_store.banking_payload(owner, "2026-08", account_id=account_a)
        individual_b = banking_store.banking_payload(owner, "2026-08", account_id=account_b)
        self.assertEqual(individual_a["view_mode"], "individual")
        self.assertEqual(individual_a["summary"]["available_balance_text"], "1.300,00")
        self.assertEqual(individual_b["summary"]["available_balance_text"], "200,00")
        self.assertEqual(individual_b["summary"]["income_text"], "0,00")
        self.assertEqual(individual_b["transactions"][0]["transfer_direction"], "IN")
        self.assertEqual(
            banking_store.banking_payload("outro-usuario", "2026-08")["transactions"],
            [],
        )

    def test_every_transaction_requires_an_owned_bank_account(self):
        with self.assertRaisesRegex(ValueError, "vinculada a uma conta"):
            banking_store.save_transaction("adm", {
                "transaction_date": "2026-08-10",
                "transaction_type": "EXPENSE",
                "description": "Sem conta",
                "amount": "10,00",
                "reference_month": "2026-08",
            })

        with self.assertRaisesRegex(ValueError, "não pertence"):
            banking_store.banking_payload("adm", "2026-08", account_id=999)

    def test_card_rejects_sensitive_full_number(self):
        with self.assertRaisesRegex(ValueError, "quatro últimos"):
            banking_store.save_card("adm", {
                "issuer": "Banco", "card_name": "Cartão", "brand": "Visa",
                "last_four": "1234567890123456", "holder": "Eduardo",
                "credit_limit": "1000", "closing_day": 10, "due_day": 17,
            })

    def test_postgres_native_values_are_json_safe(self):
        self.assertEqual(banking_store._json_safe(date(2026, 8, 22)), "2026-08-22")
        self.assertEqual(
            banking_store._json_safe(datetime(2026, 8, 22, 10, 30)),
            "2026-08-22T10:30:00",
        )
        self.assertEqual(banking_store._json_safe(Decimal("12.50")), 12.5)


if __name__ == "__main__":
    unittest.main()
