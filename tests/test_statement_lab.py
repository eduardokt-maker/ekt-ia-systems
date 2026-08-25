import base64

import pytest

import bank_statement_lab
import bank_directory


@pytest.fixture()
def lab(tmp_path, monkeypatch):
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.setattr(bank_statement_lab.main_module, "INVESTMENT_DATA_DIR", tmp_path)
    monkeypatch.setattr(
        bank_statement_lab.main_module, "INVESTMENT_DB_PATH", tmp_path / "lab.db"
    )
    bank_directory.ensure_bank_directory_db()
    with bank_directory._connection() as connection:
        connection.execute(
            """INSERT INTO bank_directory
            (ispb,bank_code,short_name,full_name,source_url,source_updated_at,active)
            VALUES(?,?,?,?,?,?,1)""",
            ("12345678", "999", "BANCO TESTE", "Banco Teste S.A.",
             bank_directory.BCB_STR_CSV_URL, "2026-08-23T00:00:00+00:00"),
        )
    bank_statement_lab.ensure_lab_db()
    return bank_statement_lab


def _payload(name="extrato.pdf", content=b"%PDF-1.4\n%%EOF"):
    return {
        "bank_ispb": "12345678",
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


@pytest.mark.parametrize(
    ("filename", "content", "mime_type"),
    [
        ("comprovante.jpg", b"\xff\xd8\xff\xe0imagem", "image/jpeg"),
        ("comprovante.png", b"\x89PNG\r\n\x1a\nimagem", "image/png"),
    ],
)
def test_accepts_receipt_images(lab, filename, content, mime_type):
    payload = _payload(filename, content)
    payload["extracted_text"] = "Pix realizado!\nValor\nR$ 21,00"
    saved = lab.save_test_file("owner-a", payload)
    stored = lab.list_test_files("owner-a")[0]

    assert stored["id"] == saved["id"]
    assert stored["mime_type"] == mime_type
    assert lab.get_test_file("owner-a", saved["id"])["content"] == content
    assert "Pix realizado" in lab.get_test_file("owner-a", saved["id"])["extracted_text"]


def test_rejects_image_with_incorrect_signature(lab):
    with pytest.raises(ValueError, match="JPEG válida"):
        lab.save_test_file(
            "owner-a", _payload("comprovante.jpg", b"not-a-jpeg")
        )
