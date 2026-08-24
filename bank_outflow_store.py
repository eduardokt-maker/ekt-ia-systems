from __future__ import annotations

import hashlib
import sqlite3
from contextlib import contextmanager
from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo

import main as main_module


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


def _p() -> str:
    return "%s" if _postgres() else "?"


def ensure_db() -> None:
    serial = "BIGSERIAL" if _postgres() else "INTEGER"
    id_tail = "" if _postgres() else " AUTOINCREMENT"
    timestamp = "TIMESTAMPTZ" if _postgres() else "TEXT"
    with _connection() as connection:
        connection.execute(f"""
            CREATE TABLE IF NOT EXISTS bank_outflow_movements (
                id {serial} PRIMARY KEY{id_tail},
                owner_key TEXT NOT NULL,
                sequence_number INTEGER NOT NULL,
                source_file_id BIGINT,
                source_filename TEXT NOT NULL,
                source_page INTEGER,
                source_index INTEGER,
                source_fingerprint TEXT NOT NULL,
                posting_date TEXT NOT NULL,
                transaction_date TEXT NOT NULL,
                payment_type TEXT NOT NULL,
                description TEXT NOT NULL,
                destination TEXT NOT NULL,
                document_number TEXT NOT NULL DEFAULT '',
                expense_nature_id BIGINT,
                expense_nature_code INTEGER,
                expense_nature_name TEXT NOT NULL DEFAULT '',
                amount NUMERIC NOT NULL,
                notes TEXT NOT NULL DEFAULT '',
                created_at {timestamp} NOT NULL,
                updated_at {timestamp} NOT NULL,
                deleted_at {timestamp},
                UNIQUE(owner_key, source_fingerprint)
            )
        """)
        if _postgres():
            connection.execute("ALTER TABLE bank_outflow_movements ADD COLUMN IF NOT EXISTS expense_nature_id BIGINT")
            connection.execute("ALTER TABLE bank_outflow_movements ADD COLUMN IF NOT EXISTS expense_nature_code INTEGER")
            connection.execute("ALTER TABLE bank_outflow_movements ADD COLUMN IF NOT EXISTS expense_nature_name TEXT NOT NULL DEFAULT ''")
        else:
            columns = {row[1] for row in connection.execute("PRAGMA table_info(bank_outflow_movements)").fetchall()}
            for name, definition in (
                ("expense_nature_id", "INTEGER"),
                ("expense_nature_code", "INTEGER"),
                ("expense_nature_name", "TEXT NOT NULL DEFAULT ''"),
            ):
                if name not in columns:
                    connection.execute(f"ALTER TABLE bank_outflow_movements ADD COLUMN {name} {definition}")
        connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_bank_outflows_owner_sequence "
            "ON bank_outflow_movements(owner_key, sequence_number)"
        )
        connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_bank_outflows_owner_date "
            "ON bank_outflow_movements(owner_key, transaction_date)"
        )


def _fingerprint(item: dict[str, Any], source_index: int) -> str:
    raw = "|".join([
        str(item.get("file_id", "")), str(source_index),
        str(item.get("transaction_date", "")), str(item.get("type", "")),
        str(item.get("destination", "")), str(item.get("amount", "")),
        str(item.get("document", "")),
    ])
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _source_index(item: dict[str, Any], fallback: int) -> int:
    try:
        return int(str(item.get("id", "")).rsplit("-", 1)[-1])
    except (TypeError, ValueError):
        return fallback


def import_extracted(
    owner_key: str, entries: list[dict[str, Any]], limit: int | None = None
) -> int:
    """Persist extracted rows once, without changing user edits."""
    ensure_db()
    p = _p()
    now = _now()
    inserted = 0
    with _connection() as connection:
        row = connection.execute(
            f"SELECT COALESCE(MAX(sequence_number),0) FROM bank_outflow_movements WHERE owner_key={p}",
            (owner_key,),
        ).fetchone()
        sequence = int(row[0])
        selected_entries = entries if limit is None else entries[:limit]
        for fallback_index, item in enumerate(selected_entries, start=1):
            source_index = _source_index(item, fallback_index)
            fingerprint = _fingerprint(item, source_index)
            exists = connection.execute(
                f"SELECT 1 FROM bank_outflow_movements WHERE owner_key={p} AND "
                f"((source_file_id={p} AND source_index={p}) OR source_fingerprint={p})",
                (owner_key, item.get("file_id"), source_index, fingerprint),
            ).fetchone()
            if exists:
                continue
            sequence += 1
            connection.execute(
                f"INSERT INTO bank_outflow_movements("
                "owner_key,sequence_number,source_file_id,source_filename,source_page,source_index,"
                "source_fingerprint,posting_date,transaction_date,payment_type,description,destination,"
                f"document_number,amount,notes,created_at,updated_at) VALUES({','.join([p] * 17)})",
                (owner_key, sequence, item.get("file_id"), item.get("filename", "Extrato"),
                 item.get("page"), source_index, fingerprint, item.get("posting_date", ""),
                 item.get("transaction_date", ""), item.get("type", "Outra saída"),
                 item.get("description", ""), item.get("destination", "Não identificado"),
                 item.get("document", ""), float(item.get("amount", 0)), "", now, now),
            )
            inserted += 1
    return inserted


def backfill_documents(owner_key: str, entries: list[dict[str, Any]]) -> int:
    """Fill only missing document numbers in already imported source rows."""
    ensure_db()
    p = _p()
    updated = 0
    with _connection() as connection:
        for fallback_index, item in enumerate(entries, start=1):
            document = str(item.get("document", "")).strip()[:80]
            if not document or item.get("file_id") is None:
                continue
            source_index = _source_index(item, fallback_index)
            result = connection.execute(
                f"UPDATE bank_outflow_movements SET document_number={p},updated_at={p} "
                f"WHERE owner_key={p} AND source_file_id={p} AND source_index={p} "
                "AND deleted_at IS NULL AND (document_number IS NULL OR TRIM(document_number)='')",
                (document, _now(), owner_key, item.get("file_id"), source_index),
            )
            updated += result.rowcount
    return updated


def _row_dict(cursor, row) -> dict[str, Any]:
    item = dict(zip([column[0] for column in cursor.description], row))
    item["amount"] = float(item["amount"])
    for key in ("created_at", "updated_at"):
        if isinstance(item.get(key), datetime):
            item[key] = item[key].isoformat()
    return item


def list_movements(owner_key: str, search: str = "") -> list[dict[str, Any]]:
    ensure_db()
    p = _p()
    query = (
        "SELECT id,sequence_number,source_file_id,source_filename,source_page,posting_date,"
        "transaction_date,payment_type,description,destination,document_number,"
        "expense_nature_id,expense_nature_code,expense_nature_name,amount,notes,"
        "created_at,updated_at FROM bank_outflow_movements "
        f"WHERE owner_key={p} AND deleted_at IS NULL"
    )
    params: list[Any] = [owner_key]
    if search.strip():
        query += f" AND (LOWER(destination) LIKE {p} OR LOWER(description) LIKE {p} OR LOWER(payment_type) LIKE {p})"
        term = f"%{search.strip().lower()}%"
        params.extend([term, term, term])
    query += " ORDER BY sequence_number,id"
    with _connection() as connection:
        cursor = connection.execute(query, tuple(params))
        return [_row_dict(cursor, row) for row in cursor.fetchall()]


def _clean_payload(payload: dict[str, Any]) -> dict[str, Any]:
    destination = str(payload.get("destination", "")).strip()[:180]
    transaction_date = str(payload.get("transaction_date", "")).strip()[:20]
    payment_type = str(payload.get("payment_type", "")).strip()[:80]
    description = str(payload.get("description", "")).strip()[:240]
    if not destination or not transaction_date or not payment_type:
        raise ValueError("Informe a data, o tipo de débito e quem recebeu.")
    try:
        amount = round(float(payload.get("amount", 0)), 2)
    except (TypeError, ValueError) as exc:
        raise ValueError("Informe um valor válido.") from exc
    if amount <= 0:
        raise ValueError("O valor da despesa deve ser maior que zero.")
    return {
        "posting_date": str(payload.get("posting_date", transaction_date)).strip()[:20] or transaction_date,
        "transaction_date": transaction_date,
        "payment_type": payment_type,
        "description": description or payment_type,
        "destination": destination,
        "document_number": str(payload.get("document_number", "")).strip()[:80],
        "amount": amount,
        "notes": str(payload.get("notes", "")).strip()[:500],
        "expense_nature_id": payload.get("expense_nature_id"),
    }


def _resolve_nature(connection, owner_key: str, raw_id: Any) -> tuple[int | None, int | None, str]:
    if raw_id in (None, "", 0, "0"):
        return None, None, ""
    try:
        nature_id = int(raw_id)
    except (TypeError, ValueError) as exc:
        raise ValueError("Selecione uma natureza de despesa válida.") from exc
    p = _p()
    row = connection.execute(
        f"SELECT id,code,name FROM bank_expense_natures "
        f"WHERE id={p} AND owner_key={p} AND deleted_at IS NULL",
        (nature_id, owner_key),
    ).fetchone()
    if not row:
        raise ValueError("A natureza de despesa selecionada não está disponível.")
    return int(row[0]), int(row[1]), str(row[2])


def create_movement(owner_key: str, payload: dict[str, Any]) -> int:
    ensure_db()
    data = _clean_payload(payload)
    p = _p()
    now = _now()
    with _connection() as connection:
        nature_id, nature_code, nature_name = _resolve_nature(
            connection, owner_key, data["expense_nature_id"]
        )
        sequence = int(connection.execute(
            f"SELECT COALESCE(MAX(sequence_number),0)+1 FROM bank_outflow_movements WHERE owner_key={p}",
            (owner_key,),
        ).fetchone()[0])
        fingerprint = hashlib.sha256(f"manual|{owner_key}|{now}|{sequence}".encode()).hexdigest()
        values = (owner_key, sequence, None, "Lançamento manual", None, None, fingerprint,
                  data["posting_date"], data["transaction_date"], data["payment_type"],
                  data["description"], data["destination"], data["document_number"],
                  nature_id, nature_code, nature_name,
                  data["amount"], data["notes"], now, now)
        if _postgres():
            row = connection.execute(
                f"INSERT INTO bank_outflow_movements(owner_key,sequence_number,source_file_id,source_filename,source_page,source_index,source_fingerprint,posting_date,transaction_date,payment_type,description,destination,document_number,expense_nature_id,expense_nature_code,expense_nature_name,amount,notes,created_at,updated_at) VALUES({','.join([p] * 20)}) RETURNING id",
                values,
            ).fetchone()
            return int(row[0])
        cursor = connection.execute(
            f"INSERT INTO bank_outflow_movements(owner_key,sequence_number,source_file_id,source_filename,source_page,source_index,source_fingerprint,posting_date,transaction_date,payment_type,description,destination,document_number,expense_nature_id,expense_nature_code,expense_nature_name,amount,notes,created_at,updated_at) VALUES({','.join([p] * 20)})",
            values,
        )
        return int(cursor.lastrowid)


def update_movement(owner_key: str, movement_id: int, payload: dict[str, Any]) -> bool:
    ensure_db()
    data = _clean_payload(payload)
    p = _p()
    with _connection() as connection:
        nature_id, nature_code, nature_name = _resolve_nature(
            connection, owner_key, data["expense_nature_id"]
        )
        result = connection.execute(
            f"UPDATE bank_outflow_movements SET posting_date={p},transaction_date={p},payment_type={p},"
            f"description={p},destination={p},document_number={p},expense_nature_id={p},"
            f"expense_nature_code={p},expense_nature_name={p},amount={p},notes={p},updated_at={p} "
            f"WHERE id={p} AND owner_key={p} AND deleted_at IS NULL",
            (data["posting_date"], data["transaction_date"], data["payment_type"],
             data["description"], data["destination"], data["document_number"],
             nature_id, nature_code, nature_name,
             data["amount"], data["notes"], _now(), movement_id, owner_key),
        )
        return result.rowcount > 0


def delete_movement(owner_key: str, movement_id: int) -> bool:
    ensure_db()
    p = _p()
    with _connection() as connection:
        result = connection.execute(
            f"UPDATE bank_outflow_movements SET deleted_at={p},updated_at={p} "
            f"WHERE id={p} AND owner_key={p} AND deleted_at IS NULL",
            (_now(), _now(), movement_id, owner_key),
        )
        return result.rowcount > 0


def summary(items: list[dict[str, Any]]) -> dict[str, Any]:
    return {"count": len(items), "total": round(sum(float(item["amount"]) for item in items), 2)}
