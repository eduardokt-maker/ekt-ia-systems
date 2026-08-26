import bank_outflow_store
import bank_expense_nature_store


def _local_db(monkeypatch, tmp_path):
    monkeypatch.setattr(bank_outflow_store.main_module, "INVESTMENT_DB_PATH", tmp_path / "outflows.db")
    monkeypatch.setattr(bank_outflow_store.main_module, "INVESTMENT_DATA_DIR", tmp_path)
    monkeypatch.setattr(bank_outflow_store.main_module, "use_postgres_investment_db", lambda: False)


def _entry(number=1):
    return {
        "id": f"9-{number}",
        "file_id": 9,
        "filename": "santander.pdf",
        "page": 2,
        "posting_date": "01/07",
        "transaction_date": "01/07",
        "type": "Pix enviado",
        "description": "Pix enviado",
        "destination": f"Favorecido {number}",
        "document": f"12345{number}",
        "amount": 10.0 + number,
    }


def test_import_is_numbered_and_idempotent(monkeypatch, tmp_path):
    _local_db(monkeypatch, tmp_path)
    entries = [_entry(number) for number in range(1, 56)]
    assert bank_outflow_store.import_extracted("owner", entries, limit=50) == 50
    assert bank_outflow_store.import_extracted("owner", entries, limit=50) == 0
    items = bank_outflow_store.list_movements("owner")
    assert len(items) == 50
    assert [item["sequence_number"] for item in items] == list(range(1, 51))

    assert bank_outflow_store.import_extracted("owner", entries) == 5
    items = bank_outflow_store.list_movements("owner")
    assert len(items) == 55
    assert [item["sequence_number"] for item in items] == list(range(1, 56))


def test_import_preserves_receipt_notes(monkeypatch, tmp_path):
    _local_db(monkeypatch, tmp_path)
    entry = _entry()
    entry["notes"] = "Ag 02968 Cc 2018924-1 | Autenticação TESTE"

    assert bank_outflow_store.import_extracted("owner", [entry]) == 1
    assert bank_outflow_store.list_movements("owner")[0]["notes"] == entry["notes"]


def test_file_summary_keeps_persisted_understanding_by_source(monkeypatch, tmp_path):
    _local_db(monkeypatch, tmp_path)
    entries = [_entry(1), _entry(2)]
    entries[1]["transaction_date"] = "03/07"
    assert bank_outflow_store.import_extracted("owner", entries) == 2

    summary = bank_outflow_store.file_summary("owner", 9)
    assert summary == {
        "count": 2,
        "total": 23.0,
        "first_transaction_date": "01/07",
        "last_transaction_date": "03/07",
    }
    assert bank_outflow_store.file_summary("other", 9)["count"] == 0


def test_crud_preserves_source_and_soft_delete_prevents_reimport(monkeypatch, tmp_path):
    _local_db(monkeypatch, tmp_path)
    bank_outflow_store.import_extracted("owner", [_entry()])
    item = bank_outflow_store.list_movements("owner")[0]
    assert bank_outflow_store.update_movement("owner", item["id"], {
        "transaction_date": "02/07", "posting_date": "02/07",
        "payment_type": "Débito", "description": "Compra corrigida",
        "destination": "Mercado", "document_number": "999",
        "amount": 42.5, "notes": "Conferido",
    })
    changed = bank_outflow_store.list_movements("owner")[0]
    assert changed["source_filename"] == "santander.pdf"
    assert changed["destination"] == "Mercado"
    assert bank_outflow_store.delete_movement("owner", item["id"])
    assert bank_outflow_store.list_movements("owner") == []
    assert bank_outflow_store.import_extracted("owner", [_entry()]) == 0


def test_manual_movement_and_search(monkeypatch, tmp_path):
    _local_db(monkeypatch, tmp_path)
    movement_id = bank_outflow_store.create_movement("owner", {
        "transaction_date": "03/07", "payment_type": "TED",
        "description": "Transferência", "destination": "Fornecedor",
        "amount": 75.25,
    })
    assert movement_id > 0
    assert bank_outflow_store.list_movements("owner", "fornecedor")[0]["sequence_number"] == 1
    assert bank_outflow_store.summary(bank_outflow_store.list_movements("owner"))["total"] == 75.25


def test_backfills_only_missing_document_without_duplicate(monkeypatch, tmp_path):
    _local_db(monkeypatch, tmp_path)
    original = _entry()
    original["document"] = ""
    assert bank_outflow_store.import_extracted("owner", [original]) == 1

    reread = _entry()
    reread["document"] = "171162"
    assert bank_outflow_store.import_extracted("owner", [reread]) == 0
    assert bank_outflow_store.backfill_documents("owner", [reread]) == 1
    items = bank_outflow_store.list_movements("owner")
    assert len(items) == 1
    assert items[0]["document_number"] == "171162"
    assert bank_outflow_store.backfill_documents("owner", [reread]) == 0


def test_expense_nature_is_validated_and_stored_on_movement(monkeypatch, tmp_path):
    _local_db(monkeypatch, tmp_path)
    nature = bank_expense_nature_store.create_nature("owner", {"name": "Saúde"})
    movement_id = bank_outflow_store.create_movement("owner", {
        "transaction_date": "04/07", "payment_type": "Pix",
        "description": "Consulta", "destination": "Clínica",
        "amount": 120, "expense_nature_id": nature["id"],
    })
    item = bank_outflow_store.list_movements("owner")[0]
    assert item["id"] == movement_id
    assert item["expense_nature_id"] == nature["id"]
    assert item["expense_nature_code"] == nature["code"]
    assert item["expense_nature_name"] == "Saúde"

    assert bank_outflow_store.update_movement("owner", movement_id, {
        "transaction_date": "04/07", "payment_type": "Pix",
        "description": "Consulta", "destination": "Clínica",
        "amount": 120, "expense_nature_id": None,
    })
    assert bank_outflow_store.list_movements("owner")[0]["expense_nature_name"] == ""


def test_rejects_nature_from_another_owner(monkeypatch, tmp_path):
    _local_db(monkeypatch, tmp_path)
    nature = bank_expense_nature_store.create_nature("other", {"name": "Educação"})
    payload = {
        "transaction_date": "05/07", "payment_type": "Débito",
        "description": "Curso", "destination": "Escola",
        "amount": 80, "expense_nature_id": nature["id"],
    }
    try:
        bank_outflow_store.create_movement("owner", payload)
        assert False, "A natureza de outro usuário não pode ser aceita"
    except ValueError as error:
        assert "não está disponível" in str(error)
