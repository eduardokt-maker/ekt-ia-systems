from __future__ import annotations

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
            CREATE TABLE IF NOT EXISTS bank_expense_natures (
                id {serial} PRIMARY KEY{id_tail},
                owner_key TEXT NOT NULL,
                code INTEGER NOT NULL,
                name TEXT NOT NULL,
                created_at {timestamp} NOT NULL,
                updated_at {timestamp} NOT NULL,
                deleted_at {timestamp},
                UNIQUE(owner_key, code)
            )
        """)
        connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_bank_natures_owner_code "
            "ON bank_expense_natures(owner_key, code)"
        )


def _name(payload: dict[str, Any]) -> str:
    value = " ".join(str(payload.get("name", "")).strip().split())[:120]
    if not value:
        raise ValueError("Informe a natureza da despesa.")
    return value


def _assert_unique(connection, owner_key: str, name: str, ignore_id: int | None = None) -> None:
    p = _p()
    query = (
        f"SELECT 1 FROM bank_expense_natures WHERE owner_key={p} "
        f"AND LOWER(name)=LOWER({p}) AND deleted_at IS NULL"
    )
    params: list[Any] = [owner_key, name]
    if ignore_id is not None:
        query += f" AND id<>{p}"
        params.append(ignore_id)
    if connection.execute(query, tuple(params)).fetchone():
        raise ValueError("Esta natureza de despesa já está cadastrada.")


def list_natures(owner_key: str) -> list[dict[str, Any]]:
    ensure_db()
    p = _p()
    with _connection() as connection:
        cursor = connection.execute(
            f"SELECT id,code,name,created_at,updated_at FROM bank_expense_natures "
            f"WHERE owner_key={p} AND deleted_at IS NULL ORDER BY code,id",
            (owner_key,),
        )
        columns = [column[0] for column in cursor.description]
        result = []
        for row in cursor.fetchall():
            item = dict(zip(columns, row))
            for key in ("created_at", "updated_at"):
                if isinstance(item.get(key), datetime):
                    item[key] = item[key].isoformat()
            result.append(item)
        return result


def next_code(owner_key: str) -> int:
    ensure_db()
    p = _p()
    with _connection() as connection:
        return int(connection.execute(
            f"SELECT COALESCE(MAX(code),0)+1 FROM bank_expense_natures WHERE owner_key={p}",
            (owner_key,),
        ).fetchone()[0])


def create_nature(owner_key: str, payload: dict[str, Any]) -> dict[str, int]:
    ensure_db()
    name = _name(payload)
    p = _p()
    now = _now()
    with _connection() as connection:
        _assert_unique(connection, owner_key, name)
        code = int(connection.execute(
            f"SELECT COALESCE(MAX(code),0)+1 FROM bank_expense_natures WHERE owner_key={p}",
            (owner_key,),
        ).fetchone()[0])
        values = (owner_key, code, name, now, now)
        if _postgres():
            row = connection.execute(
                f"INSERT INTO bank_expense_natures(owner_key,code,name,created_at,updated_at) "
                f"VALUES({','.join([p] * 5)}) RETURNING id",
                values,
            ).fetchone()
            return {"id": int(row[0]), "code": code}
        cursor = connection.execute(
            f"INSERT INTO bank_expense_natures(owner_key,code,name,created_at,updated_at) "
            f"VALUES({','.join([p] * 5)})",
            values,
        )
        return {"id": int(cursor.lastrowid), "code": code}


def update_nature(owner_key: str, nature_id: int, payload: dict[str, Any]) -> bool:
    ensure_db()
    name = _name(payload)
    p = _p()
    with _connection() as connection:
        _assert_unique(connection, owner_key, name, nature_id)
        result = connection.execute(
            f"UPDATE bank_expense_natures SET name={p},updated_at={p} "
            f"WHERE id={p} AND owner_key={p} AND deleted_at IS NULL",
            (name, _now(), nature_id, owner_key),
        )
        return result.rowcount > 0


def delete_nature(owner_key: str, nature_id: int) -> bool:
    ensure_db()
    p = _p()
    now = _now()
    with _connection() as connection:
        result = connection.execute(
            f"UPDATE bank_expense_natures SET deleted_at={p},updated_at={p} "
            f"WHERE id={p} AND owner_key={p} AND deleted_at IS NULL",
            (now, now, nature_id, owner_key),
        )
        return result.rowcount > 0
