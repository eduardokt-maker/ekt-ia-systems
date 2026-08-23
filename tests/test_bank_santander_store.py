from pathlib import Path
from unittest.mock import patch

import bank_santander_store
import main


def _entry(destination="Cemopel Casa Forte", amount=24.99):
    return {
        "posting_date": "01/07",
        "transaction_date": "01/07",
        "type": "Cartão de débito",
        "destination": destination,
        "description": "Debito Visa Electron Brasil",
        "document": "123456",
        "amount": amount,
        "page": 2,
    }


def test_import_is_persistent_idempotent_and_applies_cemopel_rule(tmp_path: Path):
    database = tmp_path / "banking.sqlite3"
    parsed = [_entry(amount=49.99), _entry(amount=50.00), _entry("Mercado", 12.0)]
    with (
        patch.object(main, "INVESTMENT_DATA_DIR", tmp_path),
        patch.object(main, "INVESTMENT_DB_PATH", database),
        patch.dict(main.os.environ, {"EKT_DISABLE_POSTGRES": "1"}),
        patch.object(bank_santander_store.statement_outflows, "parse_santander_outflows", return_value=parsed) as parser,
    ):
        first = bank_santander_store.import_santander_file("owner", 7, "santander.pdf", b"%PDF")
        second = bank_santander_store.import_santander_file("owner", 7, "santander.pdf", b"%PDF")
        payload = bank_santander_store.payload("owner")

    assert first["inserted"] == 3
    assert second["inserted"] == 0
    assert parser.call_count == 1
    assert payload["summary"]["total"] == 111.99
    assert [item["category_name"] for item in payload["outflows"]] == [
        "Conveniência", "Abastecimento", None
    ]


def test_manual_crud_and_categories_are_scoped_by_owner(tmp_path: Path):
    database = tmp_path / "banking.sqlite3"
    with (
        patch.object(main, "INVESTMENT_DATA_DIR", tmp_path),
        patch.object(main, "INVESTMENT_DB_PATH", database),
        patch.dict(main.os.environ, {"EKT_DISABLE_POSTGRES": "1"}),
    ):
        category = bank_santander_store.save_category("owner", {"name": "Saúde"})
        saved = bank_santander_store.save_outflow("owner", {
            "transaction_date": "2026-08-23", "destination": "Farmácia",
            "amount": "25,90", "transaction_type": "Cartão de débito",
            "category_id": category["id"],
        })
        bank_santander_store.save_outflow("owner", {
            "transaction_date": "2026-08-23", "destination": "Drogaria",
            "amount": "30,00", "transaction_type": "Pix enviado",
            "category_id": category["id"],
        }, saved["id"])
        items = bank_santander_store.list_outflows("owner")
        assert items[0]["destination"] == "Drogaria"
        assert items[0]["category_name"] == "Saúde"
        assert bank_santander_store.list_outflows("other") == []
        assert bank_santander_store.delete_outflow("owner", saved["id"])
        assert bank_santander_store.delete_category("owner", category["id"])
