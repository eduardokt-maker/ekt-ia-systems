from __future__ import annotations

import hashlib
import sqlite3
from contextlib import contextmanager
from datetime import datetime
from decimal import Decimal, InvalidOperation
from typing import Any
from zoneinfo import ZoneInfo

import main as main_module
import statement_outflows


STRUCTURE_CODE = "SANTANDER_CONSOLIDADO_V1"


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


def _now() -> str:
    return datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds")


def _db_decimal(value: Decimal) -> Decimal | float:
    return value if _postgres() else float(value)


def ensure_db() -> None:
    serial = "BIGSERIAL" if _postgres() else "INTEGER"
    tail = "" if _postgres() else " AUTOINCREMENT"
    timestamp = "TIMESTAMPTZ" if _postgres() else "TEXT"
    boolean = "BOOLEAN" if _postgres() else "INTEGER"
    false_default = "FALSE" if _postgres() else "0"
    true_default = "TRUE" if _postgres() else "1"
    with _connection() as connection:
        connection.execute(f"""
            CREATE TABLE IF NOT EXISTS bank_expense_categories (
                id {serial} PRIMARY KEY{tail}, owner_key TEXT NOT NULL,
                name TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
                active {boolean} NOT NULL DEFAULT {true_default},
                created_at {timestamp} NOT NULL, updated_at {timestamp} NOT NULL,
                UNIQUE(owner_key, name)
            )
        """)
        connection.execute(f"""
            CREATE TABLE IF NOT EXISTS bank_santander_outflows (
                id {serial} PRIMARY KEY{tail}, owner_key TEXT NOT NULL,
                source_file_id BIGINT, source_row_key TEXT,
                structure_code TEXT NOT NULL DEFAULT '{STRUCTURE_CODE}',
                posting_date TEXT NOT NULL, transaction_date TEXT NOT NULL,
                transaction_type TEXT NOT NULL, destination TEXT NOT NULL,
                description TEXT NOT NULL DEFAULT '', document TEXT NOT NULL DEFAULT '',
                amount NUMERIC(14,2) NOT NULL, source_page INTEGER,
                source_filename TEXT NOT NULL DEFAULT '', category_id BIGINT,
                is_manual {boolean} NOT NULL DEFAULT {false_default},
                created_at {timestamp} NOT NULL, updated_at {timestamp} NOT NULL,
                UNIQUE(owner_key, source_file_id, source_row_key)
            )
        """)
        connection.execute(f"""
            CREATE TABLE IF NOT EXISTS bank_santander_imports (
                id {serial} PRIMARY KEY{tail}, owner_key TEXT NOT NULL,
                source_file_id BIGINT NOT NULL, structure_code TEXT NOT NULL,
                source_filename TEXT NOT NULL, row_count INTEGER NOT NULL,
                imported_at {timestamp} NOT NULL,
                UNIQUE(owner_key, source_file_id, structure_code)
            )
        """)
        connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_santander_outflows_owner_date "
            "ON bank_santander_outflows(owner_key, transaction_date, id)"
        )
        connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_santander_outflows_owner_category "
            "ON bank_santander_outflows(owner_key, category_id)"
        )


def _row_dict(cursor, row) -> dict[str, Any]:
    return dict(zip([item[0] for item in cursor.description], row))


def list_categories(owner_key: str, include_inactive: bool = True) -> list[dict[str, Any]]:
    ensure_db()
    condition = "" if include_inactive else f" AND active={('TRUE' if _postgres() else '1')}"
    with _connection() as connection:
        cursor = connection.execute(
            f"SELECT id,name,description,active,created_at,updated_at FROM bank_expense_categories "
            f"WHERE owner_key={_p()}{condition} ORDER BY active DESC,name",
            (owner_key,),
        )
        return [_row_dict(cursor, row) for row in cursor.fetchall()]


def save_category(owner_key: str, payload: dict[str, Any], category_id: int | None = None) -> dict[str, Any]:
    ensure_db()
    name = str(payload.get("name", "")).strip()[:80]
    if not name:
        raise ValueError("Informe o nome da categoria.")
    description = str(payload.get("description", "")).strip()[:240]
    active = bool(payload.get("active", True))
    now = _now()
    with _connection() as connection:
        try:
            if category_id is None:
                cursor = connection.execute(
                    f"INSERT INTO bank_expense_categories(owner_key,name,description,active,created_at,updated_at) "
                    f"VALUES({_p()},{_p()},{_p()},{_p()},{_p()},{_p()}) RETURNING id",
                    (owner_key, name, description, active, now, now),
                )
                row = cursor.fetchone()
                new_id = int(row[0]) if row else int(cursor.lastrowid)
            else:
                changed = connection.execute(
                    f"UPDATE bank_expense_categories SET name={_p()},description={_p()},active={_p()},updated_at={_p()} "
                    f"WHERE id={_p()} AND owner_key={_p()}",
                    (name, description, active, now, category_id, owner_key),
                ).rowcount
                if not changed:
                    raise LookupError("Categoria não encontrada.")
                new_id = category_id
        except Exception as exc:
            if "unique" in str(exc).lower() or "duplicate" in str(exc).lower():
                raise ValueError("Já existe uma categoria com este nome.") from exc
            raise
    return {"id": new_id, "name": name, "description": description, "active": active}


def delete_category(owner_key: str, category_id: int) -> bool:
    ensure_db()
    with _connection() as connection:
        connection.execute(
            f"UPDATE bank_santander_outflows SET category_id=NULL,updated_at={_p()} "
            f"WHERE owner_key={_p()} AND category_id={_p()}",
            (_now(), owner_key, category_id),
        )
        return connection.execute(
            f"DELETE FROM bank_expense_categories WHERE id={_p()} AND owner_key={_p()}",
            (category_id, owner_key),
        ).rowcount > 0


def _category_id(connection, owner_key: str, name: str) -> int:
    row = connection.execute(
        f"SELECT id FROM bank_expense_categories WHERE owner_key={_p()} AND LOWER(name)=LOWER({_p()})",
        (owner_key, name),
    ).fetchone()
    if row:
        return int(row[0])
    now = _now()
    cursor = connection.execute(
        f"INSERT INTO bank_expense_categories(owner_key,name,description,active,created_at,updated_at) "
        f"VALUES({_p()},{_p()},{_p()},{_p()},{_p()},{_p()}) RETURNING id",
        (owner_key, name, "Categoria inicial da regra Cemopel Casa Forte.", True, now, now),
    )
    row = cursor.fetchone()
    return int(row[0]) if row else int(cursor.lastrowid)


def import_santander_file(owner_key: str, file_id: int, filename: str, content: bytes) -> dict[str, int]:
    ensure_db()
    with _connection() as connection:
        previous = connection.execute(
            f"SELECT row_count FROM bank_santander_imports WHERE owner_key={_p()} "
            f"AND source_file_id={_p()} AND structure_code={_p()}",
            (owner_key, file_id, STRUCTURE_CODE),
        ).fetchone()
        if previous:
            return {"found": int(previous[0]), "inserted": 0, "convenience": 0, "fuel": 0}
    parsed = statement_outflows.parse_santander_outflows(content, filename, file_id)
    inserted = 0
    convenience = 0
    fuel = 0
    with _connection() as connection:
        convenience_id = _category_id(connection, owner_key, "Conveniência")
        fuel_id = _category_id(connection, owner_key, "Abastecimento")
        batch = []
        for position, item in enumerate(parsed, 1):
            destination = str(item.get("destination") or "Não identificado").strip()
            amount = Decimal(str(item["amount"])).quantize(Decimal("0.01"))
            category_id = None
            if "cemopel casa forte" in destination.casefold():
                if amount < Decimal("50.00"):
                    category_id = convenience_id
                    convenience += 1
                else:
                    category_id = fuel_id
                    fuel += 1
            fingerprint = hashlib.sha256(
                f"{position}|{item.get('posting_date')}|{item.get('transaction_date')}|{destination}|{amount}".encode()
            ).hexdigest()[:32]
            values = (
                owner_key, file_id, fingerprint, STRUCTURE_CODE,
                str(item.get("posting_date") or ""), str(item.get("transaction_date") or ""),
                str(item.get("type") or "Outras saídas"), destination,
                str(item.get("description") or ""), str(item.get("document") or ""),
                _db_decimal(amount), item.get("page"), filename, category_id, False, _now(), _now(),
            )
            batch.append(values)
        if batch:
            connection.executemany(
                f"INSERT INTO bank_santander_outflows(owner_key,source_file_id,source_row_key,structure_code,posting_date,transaction_date,transaction_type,destination,description,document,amount,source_page,source_filename,category_id,is_manual,created_at,updated_at) "
                f"VALUES({','.join([_p()] * 17)})",
                batch,
            )
            inserted = len(batch)
        connection.execute(
            f"INSERT INTO bank_santander_imports(owner_key,source_file_id,structure_code,source_filename,row_count,imported_at) "
            f"VALUES({_p()},{_p()},{_p()},{_p()},{_p()},{_p()})",
            (owner_key, file_id, STRUCTURE_CODE, filename, len(parsed), _now()),
        )
    return {"found": len(parsed), "inserted": inserted, "convenience": convenience, "fuel": fuel}


def source_file_imported(owner_key: str, file_id: int) -> bool:
    ensure_db()
    with _connection() as connection:
        return connection.execute(
            f"SELECT 1 FROM bank_santander_imports WHERE owner_key={_p()} "
            f"AND source_file_id={_p()} AND structure_code={_p()}",
            (owner_key, file_id, STRUCTURE_CODE),
        ).fetchone() is not None


def _amount(payload: dict[str, Any]) -> Decimal:
    raw = str(payload.get("amount", "")).strip().replace("R$", "").replace(" ", "")
    if "," in raw:
        raw = raw.replace(".", "").replace(",", ".")
    try:
        value = Decimal(raw).quantize(Decimal("0.01"))
    except InvalidOperation as exc:
        raise ValueError("Informe um valor válido.") from exc
    if value <= 0:
        raise ValueError("O valor deve ser maior que zero.")
    return value


def save_outflow(owner_key: str, payload: dict[str, Any], outflow_id: int | None = None) -> dict[str, Any]:
    ensure_db()
    destination = str(payload.get("destination", "")).strip()[:180]
    transaction_date = str(payload.get("transaction_date", "")).strip()[:10]
    if not destination:
        raise ValueError("Informe quem recebeu a despesa.")
    if not transaction_date:
        raise ValueError("Informe a data da despesa.")
    posting_date = str(payload.get("posting_date") or transaction_date).strip()[:10]
    transaction_type = str(payload.get("transaction_type") or "Outras saídas").strip()[:60]
    description = str(payload.get("description", "")).strip()[:240]
    document = str(payload.get("document", "")).strip()[:80]
    category_id = payload.get("category_id")
    category_id = int(category_id) if category_id not in (None, "") else None
    amount = _amount(payload)
    now = _now()
    with _connection() as connection:
        if category_id is not None and not connection.execute(
            f"SELECT 1 FROM bank_expense_categories WHERE id={_p()} AND owner_key={_p()} "
            f"AND active={('TRUE' if _postgres() else '1')}",
            (category_id, owner_key),
        ).fetchone():
            raise ValueError("Selecione uma categoria ativa.")
        if outflow_id is None:
            cursor = connection.execute(
                f"INSERT INTO bank_santander_outflows(owner_key,structure_code,posting_date,transaction_date,transaction_type,destination,description,document,amount,category_id,is_manual,created_at,updated_at) "
                f"VALUES({','.join([_p()] * 13)}) RETURNING id",
                (owner_key, STRUCTURE_CODE, posting_date, transaction_date, transaction_type,
                 destination, description, document, _db_decimal(amount), category_id, True, now, now),
            )
            row = cursor.fetchone()
            saved_id = int(row[0]) if row else int(cursor.lastrowid)
        else:
            changed = connection.execute(
                f"UPDATE bank_santander_outflows SET posting_date={_p()},transaction_date={_p()},transaction_type={_p()},destination={_p()},description={_p()},document={_p()},amount={_p()},category_id={_p()},updated_at={_p()} "
                f"WHERE id={_p()} AND owner_key={_p()}",
                (posting_date, transaction_date, transaction_type, destination, description,
                 document, _db_decimal(amount), category_id, now, outflow_id, owner_key),
            ).rowcount
            if not changed:
                raise LookupError("Lançamento não encontrado.")
            saved_id = outflow_id
    return {"id": saved_id}


def delete_outflow(owner_key: str, outflow_id: int) -> bool:
    ensure_db()
    with _connection() as connection:
        return connection.execute(
            f"DELETE FROM bank_santander_outflows WHERE id={_p()} AND owner_key={_p()}",
            (outflow_id, owner_key),
        ).rowcount > 0


def list_outflows(owner_key: str) -> list[dict[str, Any]]:
    ensure_db()
    with _connection() as connection:
        cursor = connection.execute(
            f"SELECT o.id,o.source_file_id,o.structure_code,o.posting_date,o.transaction_date,"
            "o.transaction_type AS type,o.destination,o.description,o.document,o.amount,"
            "o.source_page AS page,o.source_filename AS filename,o.category_id,c.name AS category_name,"
            "o.is_manual,o.created_at,o.updated_at "
            "FROM bank_santander_outflows o LEFT JOIN bank_expense_categories c "
            "ON c.id=o.category_id AND c.owner_key=o.owner_key "
            f"WHERE o.owner_key={_p()} ORDER BY o.transaction_date,o.id",
            (owner_key,),
        )
        items = []
        for row in cursor.fetchall():
            item = _row_dict(cursor, row)
            item["amount"] = float(item["amount"])
            item["is_manual"] = bool(item["is_manual"])
            for key in ("created_at", "updated_at"):
                if isinstance(item.get(key), datetime):
                    item[key] = item[key].isoformat()
            items.append(item)
        return items


def payload(owner_key: str) -> dict[str, Any]:
    items = list_outflows(owner_key)
    return {
        "ok": True,
        "structure": {
            "code": STRUCTURE_CODE,
            "bank": "Santander",
            "label": "Extrato Consolidado Inteligente Santander",
            "note": "Este CRUD interpreta exclusivamente a estrutura Santander estudada.",
        },
        "outflows": items,
        "categories": list_categories(owner_key),
        "summary": statement_outflows.summarize_outflows(items),
    }
