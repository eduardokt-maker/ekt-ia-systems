import base64
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import banking_import
import banking_store
import main


class BankingImportTest(unittest.TestCase):
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

    def test_csv_preview_autofills_and_confirm_avoids_duplicates(self):
        content = "Data;Descrição;Valor\n01/08/2026;SALÁRIO EMPRESA X;5.000,00\n02/08/2026;PIX JOÃO SILVA;-350,00\n"
        preview = banking_import.preview({
            "filename": "extrato_itau.csv",
            "content_base64": base64.b64encode(content.encode()).decode(),
            "document_kind": "statement",
        })
        self.assertEqual(len(preview["items"]), 2)
        self.assertEqual(preview["items"][0]["transaction_type"], "INCOME")
        self.assertEqual(preview["items"][0]["category_hint"], "Salário")
        self.assertEqual(preview["items"][1]["transaction_type"], "EXPENSE")

        account_id = banking_store.save_account("adm", {
            "bank_name": "Itaú", "description": "Principal",
            "account_type": "Corrente", "holder": "Eduardo",
            "opening_balance": "0", "opening_date": "2026-08-01",
        })
        payload = {**preview, "account_id": account_id}
        first = banking_store.import_transactions("adm", payload)
        second = banking_store.import_transactions("adm", payload)
        self.assertEqual(first["saved"], 2)
        self.assertEqual(second["duplicates_skipped"], 2)
        history = banking_store.import_history("adm")
        self.assertEqual(len(history["batches"]), 2)
        detail = banking_store.import_history("adm", first["batch_id"])
        self.assertEqual(detail["batch"]["filename"], "extrato_itau.csv")
        self.assertEqual(len(detail["items"]), 2)
        self.assertEqual(detail["items"][0]["bank_name"], "Itaú")

        banking_store.delete_record(
            "adm", "transactions", detail["items"][0]["id"]
        )
        self.assertEqual(
            len(banking_store.import_history("adm", first["batch_id"])["items"]),
            1,
        )

    def test_receipt_autofills_single_expense(self):
        content = "Comprovante PIX enviado\nData 22/08/2026\nFavorecido João da Silva\nValor R$ 350,00\n"
        preview = banking_import.preview({
            "filename": "comprovante.txt",
            "content_base64": base64.b64encode(content.encode()).decode(),
            "document_kind": "receipt",
        })
        self.assertEqual(len(preview["items"]), 1)
        self.assertEqual(preview["items"][0]["transaction_type"], "EXPENSE")
        self.assertEqual(preview["items"][0]["amount"], "350,00")

    def test_rejects_scanned_pdf_without_text(self):
        with self.assertRaisesRegex(ValueError, "Não foi possível ler|texto pesquisável"):
            banking_import.preview({
                "filename": "digitalizado.pdf",
                "content_base64": base64.b64encode(b"%PDF-1.4 invalid").decode(),
                "document_kind": "receipt",
            })


if __name__ == "__main__":
    unittest.main()
