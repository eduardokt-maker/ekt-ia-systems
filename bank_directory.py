from __future__ import annotations

import csv
import io
import sqlite3
import urllib.request
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from typing import Any

import main as main_module


BCB_STR_CSV_URL = (
    "https://www.bcb.gov.br/content/estabilidadefinanceira/str1/ParticipantesSTR.csv"
)


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


def ensure_bank_directory_db() -> None:
    with _connection() as connection:
        connection.execute("""
            CREATE TABLE IF NOT EXISTS bank_directory (
                ispb TEXT PRIMARY KEY,
                bank_code TEXT,
                short_name TEXT NOT NULL,
                full_name TEXT NOT NULL,
                participates_compe TEXT,
                main_access TEXT,
                operation_started_at TEXT,
                source_url TEXT NOT NULL,
                source_updated_at TEXT NOT NULL,
                active INTEGER NOT NULL DEFAULT 1
            )
        """)
        connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_bank_directory_code "
            "ON bank_directory(bank_code)"
        )


def _download_official_csv(timeout: int = 20) -> bytes:
    request = urllib.request.Request(
        BCB_STR_CSV_URL,
        headers={"User-Agent": "EKT-IA-Systems/1.0 (bank-directory-sync)"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def parse_official_csv(content: bytes) -> list[dict[str, str | None]]:
    text = content.decode("utf-8-sig")
    rows: list[dict[str, str | None]] = []
    for row in csv.DictReader(io.StringIO(text)):
        ispb = str(row.get("ISPB", "")).strip().zfill(8)
        short_name = str(row.get("Nome_Reduzido", "")).strip()
        full_name = str(row.get("Nome_Extenso", "")).strip()
        raw_code = str(row.get("Número_Código", "")).strip()
        bank_code = raw_code.zfill(3) if raw_code.isdigit() else None
        if len(ispb) != 8 or not short_name or not full_name:
            continue
        rows.append({
            "ispb": ispb,
            "bank_code": bank_code,
            "short_name": short_name,
            "full_name": full_name,
            "participates_compe": str(row.get("Participa_da_Compe", "")).strip(),
            "main_access": str(row.get("Acesso_Principal", "")).strip(),
            "operation_started_at": str(row.get("Início_da_Operação", "")).strip(),
        })
    if len(rows) < 100:
        raise ValueError("A relação oficial recebida está incompleta.")
    return rows


def sync_bank_directory(*, force: bool = False) -> dict[str, Any]:
    ensure_bank_directory_db()
    if not force and not directory_needs_refresh():
        return {"updated": False, "count": count_banks()}
    rows = parse_official_csv(_download_official_csv())
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    p = _p()
    with _connection() as connection:
        connection.execute("UPDATE bank_directory SET active=0")
        for row in rows:
            values = (
                row["ispb"], row["bank_code"], row["short_name"], row["full_name"],
                row["participates_compe"], row["main_access"],
                row["operation_started_at"], BCB_STR_CSV_URL, now,
            )
            if _postgres():
                connection.execute(
                    f"""INSERT INTO bank_directory
                    (ispb,bank_code,short_name,full_name,participates_compe,main_access,
                     operation_started_at,source_url,source_updated_at,active)
                    VALUES({','.join([p] * 9)},1)
                    ON CONFLICT(ispb) DO UPDATE SET bank_code=EXCLUDED.bank_code,
                    short_name=EXCLUDED.short_name,full_name=EXCLUDED.full_name,
                    participates_compe=EXCLUDED.participates_compe,
                    main_access=EXCLUDED.main_access,
                    operation_started_at=EXCLUDED.operation_started_at,
                    source_url=EXCLUDED.source_url,
                    source_updated_at=EXCLUDED.source_updated_at,active=1""",
                    values,
                )
            else:
                connection.execute(
                    f"""INSERT INTO bank_directory
                    (ispb,bank_code,short_name,full_name,participates_compe,main_access,
                     operation_started_at,source_url,source_updated_at,active)
                    VALUES({','.join([p] * 9)},1)
                    ON CONFLICT(ispb) DO UPDATE SET bank_code=excluded.bank_code,
                    short_name=excluded.short_name,full_name=excluded.full_name,
                    participates_compe=excluded.participates_compe,
                    main_access=excluded.main_access,
                    operation_started_at=excluded.operation_started_at,
                    source_url=excluded.source_url,
                    source_updated_at=excluded.source_updated_at,active=1""",
                    values,
                )
    return {"updated": True, "count": len(rows), "updated_at": now}


def count_banks() -> int:
    ensure_bank_directory_db()
    with _connection() as connection:
        return int(connection.execute(
            "SELECT COUNT(*) FROM bank_directory WHERE active=1"
        ).fetchone()[0])


def directory_needs_refresh() -> bool:
    with _connection() as connection:
        row = connection.execute(
            "SELECT MAX(source_updated_at) FROM bank_directory WHERE active=1"
        ).fetchone()
    if not row or not row[0]:
        return True
    try:
        updated = datetime.fromisoformat(str(row[0]))
        if updated.tzinfo is None:
            updated = updated.replace(tzinfo=timezone.utc)
        return updated < datetime.now(timezone.utc) - timedelta(hours=24)
    except ValueError:
        return True


def list_banks() -> list[dict[str, Any]]:
    ensure_bank_directory_db()
    with _connection() as connection:
        cursor = connection.execute("""
            SELECT ispb,bank_code,short_name,full_name,participates_compe,
                   source_updated_at
            FROM bank_directory WHERE active=1
            ORDER BY CASE WHEN bank_code IS NULL THEN 1 ELSE 0 END,
                     bank_code,short_name
        """)
        columns = [column[0] for column in cursor.description]
        return [dict(zip(columns, row)) for row in cursor.fetchall()]


def find_bank(ispb: str) -> dict[str, Any] | None:
    ensure_bank_directory_db()
    with _connection() as connection:
        row = connection.execute(
            f"SELECT ispb,bank_code,short_name,full_name FROM bank_directory "
            f"WHERE ispb={_p()} AND active=1", (ispb,),
        ).fetchone()
        if row is None:
            return None
        return dict(zip(("ispb", "bank_code", "short_name", "full_name"), row))
