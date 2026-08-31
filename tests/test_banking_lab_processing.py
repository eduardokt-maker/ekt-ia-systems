import web_app


def test_process_banking_lab_image_imports_recognized_receipt(monkeypatch):
    monkeypatch.setattr(
        web_app.bank_statement_lab,
        "get_test_file",
        lambda owner_key, file_id: {
            "filename": "receipt.jpg",
            "content": b"jpeg",
            "extracted_text": "OCR",
        },
    )
    monkeypatch.setattr(
        web_app.statement_outflows,
        "parse_c6_pix_receipt_text",
        lambda text, filename, file_id: [{"file_id": file_id, "amount": 21.0}],
    )
    monkeypatch.setattr(
        web_app.bank_outflow_store,
        "import_extracted",
        lambda owner_key, entries: len(entries),
    )
    monkeypatch.setattr(
        web_app.bank_outflow_store,
        "backfill_documents",
        lambda owner_key, entries: 0,
    )

    result = web_app.process_banking_lab_file("owner", {"id": 81})

    assert result == {
        "recognized": 1,
        "imported": 1,
        "documents_completed": 0,
        "ignored": False,
    }


def test_process_banking_lab_image_reports_unrecognized_ocr(monkeypatch):
    monkeypatch.setattr(
        web_app.bank_statement_lab,
        "get_test_file",
        lambda owner_key, file_id: {
            "filename": "receipt.jpg",
            "content": b"jpeg",
            "extracted_text": "",
        },
    )
    monkeypatch.setattr(
        web_app.statement_outflows,
        "parse_c6_pix_receipt_text",
        lambda text, filename, file_id: [],
    )
    monkeypatch.setattr(
        web_app.bank_outflow_store,
        "import_extracted",
        lambda owner_key, entries: 0,
    )
    monkeypatch.setattr(
        web_app.bank_outflow_store,
        "backfill_documents",
        lambda owner_key, entries: 0,
    )

    result = web_app.process_banking_lab_file("owner", {"id": 82})

    assert result["recognized"] == 0
    assert result["imported"] == 0
    assert result["ignored"] is True
