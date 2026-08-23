import base64

import pytest

import bank_statement_lab


@pytest.fixture()
def lab(tmp_path, monkeypatch):
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.setattr(bank_statement_lab.main_module, "INVESTMENT_DATA_DIR", tmp_path)
    monkeypatch.setattr(
        bank_statement_lab.main_module, "INVESTMENT_DB_PATH", tmp_path / "lab.db"
    )
    bank_statement_lab.ensure_lab_db()
    return bank_statement_lab


def _payload(name="extrato.pdf", content=b"%PDF-1.4\n%%EOF"):
    return {
        "bank_name": "Banco Teste",
        "account_label": "Conta principal",
        "filename": name,
        "content_base64": base64.b64encode(content).decode("ascii"),
    }


def test_store_list_download_and_delete_are_owner_isolated(lab):
    saved = lab.save_test_file("owner-a", _payload())
    listed = lab.list_test_files("owner-a")
    assert listed[0]["id"] == saved["id"]
    assert "file_content" not in listed[0]
    assert lab.list_test_files("owner-b") == []

    downloaded = lab.get_test_file("owner-a", saved["id"])
    assert downloaded["content"] == b"%PDF-1.4\n%%EOF"
    assert lab.get_test_file("owner-b", saved["id"]) is None

    assert lab.delete_test_file("owner-b", saved["id"]) is False
    assert lab.delete_test_file("owner-a", saved["id"]) is True
    assert lab.list_test_files("owner-a") == []


def test_rejects_duplicate_and_invalid_content(lab):
    lab.save_test_file("owner-a", _payload())
    with pytest.raises(ValueError, match="já foi enviado"):
        lab.save_test_file("owner-a", _payload())
    with pytest.raises(ValueError, match="PDF válido"):
        lab.save_test_file("owner-a", _payload(content=b"not-a-pdf"))
    with pytest.raises(ValueError, match="Formato não permitido"):
        lab.save_test_file("owner-a", _payload(name="extrato.exe"))
