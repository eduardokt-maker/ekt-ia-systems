import bank_outflow_store


def _local_db(monkeypatch, tmp_path):
    monkeypatch.setattr(bank_outflow_store.main_module, "INVESTMENT_DB_PATH", tmp_path / "outflows.db")
    monkeypatch.setattr(bank_outflow_store.main_module, "INVESTMENT_DATA_DIR", tmp_path)
    monkeypatch.setattr(bank_outflow_store.main_module, "use_postgres_investment_db", lambda: False)


def _entry(number=1):
    return {
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
    assert bank_outflow_store.import_extracted("owner", entries) == 50
    assert bank_outflow_store.import_extracted("owner", entries) == 0
    items = bank_outflow_store.list_movements("owner")
    assert len(items) == 50
    assert [item["sequence_number"] for item in items] == list(range(1, 51))


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
