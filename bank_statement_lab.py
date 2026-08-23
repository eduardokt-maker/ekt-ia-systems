from __future__ import annotations

import base64
import hashlib
import sqlite3
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import main as main_module
import bank_directory


MAX_FILE_BYTES = 15 * 1024 * 1024
ALLOWED_EXTENSIONS = {".pdf", ".csv", ".ofx", ".xlsx"}
ALLOWED_MIME_TYPES = {
    ".pdf": "application/pdf",
    ".csv": "text/csv",
    ".ofx": "application/x-ofx",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
}


def _now() -> str:
    return datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds")


@contextmanager
def _connection():
    if main_module.use_postgres_investment_db():
        with main_module.investment_db_connection() as connection:
            yield connection
        return
    main_module.INVESTMENT_DATA_DIR.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(main_module.INVESTMENT_DB_PATH)
    connection.row_factory = sqlite3.Row
    try:
        with connection:
            yield connection
    finally:
        connection.close()


def _postgres() -> bool:
    return main_module.use_postgres_investment_db()


def _params(count: int) -> str:
    token = "%s" if _postgres() else "?"
    return ",".join([token] * count)


def ensure_lab_db() -> None:
    serial = "BIGSERIAL" if _postgres() else "INTEGER"
    id_tail = "" if _postgres() else " AUTOINCREMENT"
    timestamp = "TIMESTAMPTZ NOT NULL DEFAULT NOW()" if _postgres() else "TEXT NOT NULL"
    blob = "BYTEA" if _postgres() else "BLOB"
    with _connection() as connection:
        connection.execute(f"""
            CREATE TABLE IF NOT EXISTS bank_statement_test_files (
                id {serial} PRIMARY KEY{id_tail}, owner_key TEXT NOT NULL,
                bank_name TEXT NOT NULL, account_label TEXT NOT NULL,
                filename TEXT NOT NULL, extension TEXT NOT NULL,
                mime_type TEXT NOT NULL, size_bytes BIGINT NOT NULL,
                sha256 TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'RECEIVED',
                file_content {blob} NOT NULL, uploaded_at {timestamp},
                UNIQUE(owner_key, sha256)
            )
        """)
        connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_statement_lab_owner_uploaded "
            "ON bank_statement_test_files(owner_key, uploaded_at, id)"
        )
        columns = {
            row[1] for row in connection.execute(
                "PRAGMA table_info(bank_statement_test_files)"
            ).fetchall()
        } if not _postgres() else {
            row[0] for row in connection.execute(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_name='bank_statement_test_files'"
            ).fetchall()
        }
        if "bank_code" not in columns:
            connection.execute(
                "ALTER TABLE bank_statement_test_files ADD COLUMN bank_code TEXT"
            )
        if "bank_ispb" not in columns:
            connection.execute(
                "ALTER TABLE bank_statement_test_files ADD COLUMN bank_ispb TEXT"
            )


def _required(payload: dict[str, Any], key: str, label: str, limit: int = 120) -> str:
    value = str(payload.get(key, "")).strip()[:limit]
    if not value:
        raise ValueError(f"Informe {label}.")
    return value


def _decode_file(payload: dict[str, Any]) -> tuple[str, str, str, bytes]:
    filename = Path(_required(payload, "filename", "o nome do arquivo", 180)).name
    extension = Path(filename).suffix.lower()
    if extension not in ALLOWED_EXTENSIONS:
        raise ValueError("Formato não permitido. Use PDF, CSV, OFX ou XLSX.")
    try:
        content = base64.b64decode(str(payload.get("content_base64", "")), validate=True)
    except Exception as exc:
        raise ValueError("O arquivo enviado é inválido.") from exc
    if not content or len(content) > MAX_FILE_BYTES:
        raise ValueError("O arquivo deve possuir conteúdo e ter no máximo 15 MB.")
    if extension == ".pdf" and not content.startswith(b"%PDF"):
        raise ValueError("O conteúdo não corresponde a um arquivo PDF válido.")
    if extension == ".xlsx" and not content.startswith(b"PK"):
        raise ValueError("O conteúdo não corresponde a uma planilha XLSX válida.")
    mime_type = ALLOWED_MIME_TYPES[extension]
    return filename, extension, mime_type, content


def save_test_file(owner_key: str, payload: dict[str, Any]) -> dict[str, Any]:
    ensure_lab_db()
    bank_ispb = _required(payload, "bank_ispb", "um banco da lista oficial", 8)
    bank = bank_directory.find_bank(bank_ispb)
    if bank is None:
        raise ValueError("Selecione um banco válido da lista oficial do Banco Central.")
    bank_name = str(bank["short_name"])
    bank_code = bank.get("bank_code")
    account_label = _required(payload, "account_label", "a identificação da conta")
    filename, extension, mime_type, content = _decode_file(payload)
    digest = hashlib.sha256(content).hexdigest()
    now = _now()
    with _connection() as connection:
        try:
            if _postgres():
                row = connection.execute(
                    f"INSERT INTO bank_statement_test_files(owner_key,bank_name,bank_code,bank_ispb,account_label,filename,extension,mime_type,size_bytes,sha256,status,file_content,uploaded_at) VALUES({_params(13)}) RETURNING id",
                    (owner_key, bank_name, bank_code, bank_ispb, account_label, filename, extension, mime_type, len(content), digest, "RECEIVED", content, now),
                ).fetchone()
                file_id = int(row[0])
            else:
                file_id = int(connection.execute(
                    f"INSERT INTO bank_statement_test_files(owner_key,bank_name,bank_code,bank_ispb,account_label,filename,extension,mime_type,size_bytes,sha256,status,file_content,uploaded_at) VALUES({_params(13)})",
                    (owner_key, bank_name, bank_code, bank_ispb, account_label, filename, extension, mime_type, len(content), digest, "RECEIVED", content, now),
                ).lastrowid)
        except Exception as exc:
            if "unique" in str(exc).lower() or "duplicate" in str(exc).lower():
                raise ValueError("Este mesmo arquivo já foi enviado para o laboratório.") from exc
            raise
    return {"ok": True, "id": file_id, "sha256": digest}


def list_test_files(owner_key: str) -> list[dict[str, Any]]:
    ensure_lab_db()
    p = "%s" if _postgres() else "?"
    with _connection() as connection:
        cursor = connection.execute(
            f"SELECT id,bank_name,bank_code,bank_ispb,account_label,filename,extension,mime_type,size_bytes,sha256,status,uploaded_at FROM bank_statement_test_files WHERE owner_key={p} ORDER BY uploaded_at DESC,id DESC",
            (owner_key,),
        )
        columns = [item[0] for item in cursor.description]
        items = []
        for row in cursor.fetchall():
            item = dict(zip(columns, row))
            uploaded = item.get("uploaded_at")
            if isinstance(uploaded, datetime):
                item["uploaded_at"] = uploaded.isoformat()
            items.append(item)
        return items


def get_test_file(owner_key: str, file_id: int) -> dict[str, Any] | None:
    ensure_lab_db()
    p = "%s" if _postgres() else "?"
    with _connection() as connection:
        row = connection.execute(
            f"SELECT filename,mime_type,file_content FROM bank_statement_test_files WHERE id={p} AND owner_key={p}",
            (file_id, owner_key),
        ).fetchone()
        if row is None:
            return None
        return {"filename": row[0], "mime_type": row[1], "content": bytes(row[2])}


def delete_test_file(owner_key: str, file_id: int) -> bool:
    ensure_lab_db()
    p = "%s" if _postgres() else "?"
    with _connection() as connection:
        return connection.execute(
            f"DELETE FROM bank_statement_test_files WHERE id={p} AND owner_key={p}",
            (file_id, owner_key),
        ).rowcount > 0
