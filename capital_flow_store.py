from __future__ import annotations

import sqlite3
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from typing import Any
from zoneinfo import ZoneInfo

import main as main_module


INVESTOR_FOREIGN = "Estrangeiro"
INVESTOR_INSTITUTIONAL = "Institucional brasileiro"
INVESTOR_INDIVIDUAL = "Pessoa física"
INVESTOR_FINANCIAL = "Instituição financeira"
INVESTOR_OTHER = "Outros investidores"
INVESTOR_TYPES = {
    INVESTOR_FOREIGN,
    INVESTOR_INSTITUTIONAL,
    INVESTOR_INDIVIDUAL,
    INVESTOR_FINANCIAL,
    INVESTOR_OTHER,
}
SOURCE_DEFAULT = "Cadastro manual - fonte informada pelo usuário"
OFFICIAL_SOURCE_PREFIX = "B3 — Boletim Diário do Mercado"


def is_official_source(source: object) -> bool:
    return str(source or "").strip().startswith(OFFICIAL_SOURCE_PREFIX)


def _decimal(value: object) -> Decimal:
    text = str(value if value is not None else "").strip().replace("R$", "").replace(" ", "")
    if not text:
        raise ValueError("Informe os valores de entrada e saída.")
    if "," in text:
        text = text.replace(".", "").replace(",", ".")
    try:
        number = Decimal(text)
    except InvalidOperation as exc:
        raise ValueError("Informe um valor monetário válido.") from exc
    if number < 0:
        raise ValueError("Entrada e saída não podem ser negativas.")
    return number.quantize(Decimal("0.01"))


def _iso_date(value: object) -> str:
    try:
        parsed = date.fromisoformat(str(value or "").strip())
    except ValueError as exc:
        raise ValueError("Informe uma data válida.") from exc
    if parsed.weekday() >= 5:
        raise ValueError("Sábado e domingo não são pregões.")
    return parsed.isoformat()


def _range_date(value: object) -> str:
    try:
        return date.fromisoformat(str(value or "").strip()).isoformat()
    except ValueError as exc:
        raise ValueError("Informe um período válido.") from exc


def _now() -> str:
    return datetime.now(ZoneInfo("America/Fortaleza")).isoformat(timespec="seconds")


def ensure_capital_flow_db() -> None:
    main_module.ensure_investment_db()
    if main_module.use_postgres_investment_db():
        with main_module.investment_db_connection() as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS capital_flow_records (
                    id BIGSERIAL PRIMARY KEY,
                    reference_date DATE NOT NULL,
                    investor_type TEXT NOT NULL,
                    inflow NUMERIC(20, 2) NOT NULL,
                    outflow NUMERIC(20, 2) NOT NULL,
                    source TEXT NOT NULL,
                    notes TEXT NOT NULL DEFAULT '',
                    source_lag TEXT NOT NULL DEFAULT 'Conforme divulgação',
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    UNIQUE(reference_date, investor_type)
                )
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS capital_flow_revisions (
                    id BIGSERIAL PRIMARY KEY,
                    record_id BIGINT NOT NULL REFERENCES capital_flow_records(id),
                    old_inflow NUMERIC(20, 2) NOT NULL,
                    old_outflow NUMERIC(20, 2) NOT NULL,
                    new_inflow NUMERIC(20, 2) NOT NULL,
                    new_outflow NUMERIC(20, 2) NOT NULL,
                    revision_reason TEXT NOT NULL,
                    detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS capital_flow_sync_months (
                    month_key TEXT PRIMARY KEY,
                    is_complete BOOLEAN NOT NULL DEFAULT FALSE,
                    checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
                """
            )
        return
    with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS capital_flow_records (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                reference_date TEXT NOT NULL,
                investor_type TEXT NOT NULL,
                inflow TEXT NOT NULL,
                outflow TEXT NOT NULL,
                source TEXT NOT NULL,
                notes TEXT NOT NULL DEFAULT '',
                source_lag TEXT NOT NULL DEFAULT 'Conforme divulgação',
                updated_at TEXT NOT NULL,
                UNIQUE(reference_date, investor_type)
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS capital_flow_revisions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                record_id INTEGER NOT NULL,
                old_inflow TEXT NOT NULL,
                old_outflow TEXT NOT NULL,
                new_inflow TEXT NOT NULL,
                new_outflow TEXT NOT NULL,
                revision_reason TEXT NOT NULL,
                detected_at TEXT NOT NULL
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS capital_flow_sync_months (
                month_key TEXT PRIMARY KEY,
                is_complete INTEGER NOT NULL DEFAULT 0,
                checked_at TEXT NOT NULL
            )
            """
        )


def month_sync_status(month_key: str) -> dict[str, Any] | None:
    ensure_capital_flow_db()
    sql = """
        SELECT month_key, is_complete, checked_at
        FROM capital_flow_sync_months WHERE month_key={p}
    """
    if main_module.use_postgres_investment_db():
        with main_module.investment_db_connection() as connection:
            row = connection.execute(sql.format(p="%s"), (month_key,)).fetchone()
    else:
        with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
            row = connection.execute(sql.format(p="?"), (month_key,)).fetchone()
    if not row:
        return None
    return {
        "month_key": str(row[0]),
        "is_complete": bool(row[1]),
        "checked_at": str(row[2]),
    }


def mark_month_synced(month_key: str, *, complete: bool) -> None:
    ensure_capital_flow_db()
    values = (month_key, complete, _now())
    if main_module.use_postgres_investment_db():
        with main_module.investment_db_connection() as connection:
            connection.execute(
                """
                INSERT INTO capital_flow_sync_months (month_key, is_complete, checked_at)
                VALUES (%s, %s, %s)
                ON CONFLICT (month_key) DO UPDATE SET
                    is_complete=EXCLUDED.is_complete,
                    checked_at=EXCLUDED.checked_at
                """,
                values,
            )
        return
    with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
        connection.execute(
            """
            INSERT INTO capital_flow_sync_months (month_key, is_complete, checked_at)
            VALUES (?, ?, ?)
            ON CONFLICT(month_key) DO UPDATE SET
                is_complete=excluded.is_complete,
                checked_at=excluded.checked_at
            """,
            (month_key, int(complete), values[2]),
        )


def validate_payload(payload: dict[str, Any]) -> dict[str, Any]:
    investor_type = str(payload.get("investor_type", "")).strip()
    if investor_type not in INVESTOR_TYPES:
        raise ValueError("Selecione um tipo de investidor válido.")
    source = str(payload.get("source", "")).strip()[:180]
    if not source:
        raise ValueError("Informe a fonte dos dados.")
    return {
        "reference_date": _iso_date(payload.get("reference_date")),
        "investor_type": investor_type,
        "inflow": _decimal(payload.get("inflow")),
        "outflow": _decimal(payload.get("outflow")),
        "source": source,
        "notes": str(payload.get("notes", "")).strip()[:500],
        "source_lag": str(payload.get("source_lag", "")).strip()[:60]
        or "Conforme divulgação",
    }


def _row_dict(row: tuple[Any, ...]) -> dict[str, Any]:
    inflow = Decimal(str(row[3]))
    outflow = Decimal(str(row[4]))
    net = inflow - outflow
    return {
        "id": int(row[0]),
        "reference_date": str(row[1]),
        "investor_type": str(row[2]),
        "inflow": float(inflow),
        "outflow": float(outflow),
        "net": float(net),
        "inflow_exact": format(inflow, ".2f"),
        "outflow_exact": format(outflow, ".2f"),
        "net_exact": format(net, ".2f"),
        "source": str(row[5]),
        "official": is_official_source(row[5]),
        "notes": str(row[6]),
        "source_lag": str(row[7]),
        "updated_at": str(row[8]),
    }


def list_records(date_from: str, date_to: str) -> list[dict[str, Any]]:
    start, end = _range_date(date_from), _range_date(date_to)
    if start > end:
        raise ValueError("Período de consulta inválido.")
    ensure_capital_flow_db()
    sql = """
        SELECT id, reference_date, investor_type, inflow, outflow,
               source, notes, source_lag, updated_at
        FROM capital_flow_records
        WHERE reference_date BETWEEN {p1} AND {p2}
        ORDER BY reference_date, investor_type
    """
    if main_module.use_postgres_investment_db():
        with main_module.investment_db_connection() as connection:
            rows = connection.execute(sql.format(p1="%s", p2="%s"), (start, end)).fetchall()
    else:
        with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
            rows = connection.execute(sql.format(p1="?", p2="?"), (start, end)).fetchall()
    return [_row_dict(tuple(row)) for row in rows]


def _record_source(item_id: int) -> str | None:
    ensure_capital_flow_db()
    if main_module.use_postgres_investment_db():
        with main_module.investment_db_connection() as connection:
            row = connection.execute(
                "SELECT source FROM capital_flow_records WHERE id=%s", (item_id,)
            ).fetchone()
    else:
        with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
            row = connection.execute(
                "SELECT source FROM capital_flow_records WHERE id=?", (item_id,)
            ).fetchone()
    return str(row[0]) if row else None


def _protect_official_record(item_id: int) -> None:
    source = _record_source(item_id)
    if source is None:
        raise LookupError("Registro não encontrado.")
    if is_official_source(source):
        raise ValueError(
            "Registros oficiais da B3 são somente leitura e não podem ser alterados."
        )


def save_record(payload: dict[str, Any], item_id: int | None = None) -> int:
    if item_id is not None:
        _protect_official_record(item_id)
    item = validate_payload(payload)
    ensure_capital_flow_db()
    values = (
        item["reference_date"],
        item["investor_type"],
        str(item["inflow"]),
        str(item["outflow"]),
        item["source"],
        item["notes"],
        item["source_lag"],
        _now(),
    )
    try:
        if main_module.use_postgres_investment_db():
            with main_module.investment_db_connection() as connection:
                if item_id is None:
                    return int(
                        connection.execute(
                            """
                            INSERT INTO capital_flow_records
                            (reference_date, investor_type, inflow, outflow, source, notes, source_lag, updated_at)
                            VALUES (%s, %s, %s, %s, %s, %s, %s, %s) RETURNING id
                            """,
                            values,
                        ).fetchone()[0]
                    )
                cursor = connection.execute(
                    """
                    UPDATE capital_flow_records SET reference_date=%s, investor_type=%s,
                    inflow=%s, outflow=%s, source=%s, notes=%s, source_lag=%s, updated_at=%s
                    WHERE id=%s
                    """,
                    (*values, item_id),
                )
                if cursor.rowcount == 0:
                    raise LookupError("Registro não encontrado.")
                return item_id
        with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
            if item_id is None:
                cursor = connection.execute(
                    """
                    INSERT INTO capital_flow_records
                    (reference_date, investor_type, inflow, outflow, source, notes, source_lag, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    values,
                )
                return int(cursor.lastrowid)
            cursor = connection.execute(
                """
                UPDATE capital_flow_records SET reference_date=?, investor_type=?,
                inflow=?, outflow=?, source=?, notes=?, source_lag=?, updated_at=?
                WHERE id=?
                """,
                (*values, item_id),
            )
            if cursor.rowcount == 0:
                raise LookupError("Registro não encontrado.")
            return item_id
    except Exception as exc:
        if "unique" in str(exc).lower() or "duplicate" in str(exc).lower():
            raise ValueError("Já existe um registro para essa data e tipo de investidor.") from exc
        raise


def delete_record(item_id: int) -> bool:
    _protect_official_record(item_id)
    ensure_capital_flow_db()
    if main_module.use_postgres_investment_db():
        with main_module.investment_db_connection() as connection:
            return connection.execute(
                "DELETE FROM capital_flow_records WHERE id=%s", (item_id,)
            ).rowcount > 0
    with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
        return connection.execute(
            "DELETE FROM capital_flow_records WHERE id=?", (item_id,)
        ).rowcount > 0


def upsert_official_records(records: list[dict[str, Any]]) -> int:
    """Idempotent upsert that audits official revisions instead of hiding them."""
    ensure_capital_flow_db()
    updated = 0
    for raw in records:
        item = validate_payload(raw)
        values = (
            item["reference_date"],
            item["investor_type"],
            str(item["inflow"]),
            str(item["outflow"]),
            item["source"],
            item["notes"],
            item["source_lag"],
            _now(),
        )
        if main_module.use_postgres_investment_db():
            with main_module.investment_db_connection() as connection:
                existing = connection.execute(
                    "SELECT id, inflow, outflow FROM capital_flow_records WHERE reference_date=%s AND investor_type=%s",
                    (item["reference_date"], item["investor_type"]),
                ).fetchone()
                if existing and (Decimal(str(existing[1])) != item["inflow"] or Decimal(str(existing[2])) != item["outflow"]):
                    connection.execute(
                        """INSERT INTO capital_flow_revisions
                        (record_id, old_inflow, old_outflow, new_inflow, new_outflow, revision_reason)
                        VALUES (%s, %s, %s, %s, %s, %s)""",
                        (existing[0], existing[1], existing[2], item["inflow"], item["outflow"], "Republicação ou correção identificada no BDI da B3"),
                    )
                cursor = connection.execute(
                    """
                    INSERT INTO capital_flow_records
                    (reference_date, investor_type, inflow, outflow, source, notes, source_lag, updated_at)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (reference_date, investor_type) DO UPDATE SET
                        inflow=EXCLUDED.inflow, outflow=EXCLUDED.outflow,
                        source=EXCLUDED.source, notes=EXCLUDED.notes,
                        source_lag=EXCLUDED.source_lag, updated_at=EXCLUDED.updated_at
                    WHERE capital_flow_records.inflow IS DISTINCT FROM EXCLUDED.inflow
                       OR capital_flow_records.outflow IS DISTINCT FROM EXCLUDED.outflow
                    """,
                    values,
                )
                updated += max(cursor.rowcount, 0)
        else:
            with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
                existing = connection.execute(
                    "SELECT id, inflow, outflow FROM capital_flow_records WHERE reference_date=? AND investor_type=?",
                    (item["reference_date"], item["investor_type"]),
                ).fetchone()
                if existing and (Decimal(str(existing[1])) != item["inflow"] or Decimal(str(existing[2])) != item["outflow"]):
                    connection.execute(
                        """INSERT INTO capital_flow_revisions
                        (record_id, old_inflow, old_outflow, new_inflow, new_outflow, revision_reason, detected_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?)""",
                        (existing[0], existing[1], existing[2], str(item["inflow"]), str(item["outflow"]), "Republicação ou correção identificada no BDI da B3", _now()),
                    )
                cursor = connection.execute(
                    """
                    INSERT INTO capital_flow_records
                    (reference_date, investor_type, inflow, outflow, source, notes, source_lag, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(reference_date, investor_type) DO UPDATE SET
                        inflow=excluded.inflow, outflow=excluded.outflow,
                        source=excluded.source, notes=excluded.notes,
                        source_lag=excluded.source_lag, updated_at=excluded.updated_at
                    WHERE capital_flow_records.inflow <> excluded.inflow
                       OR capital_flow_records.outflow <> excluded.outflow
                    """,
                    values,
                )
                updated += max(cursor.rowcount, 0)
    return updated


def build_payload(date_from: str, date_to: str) -> dict[str, Any]:
    items = list_records(date_from, date_to)
    totals_by_date: dict[str, tuple[Decimal, Decimal]] = {}
    for item in items:
        current_in, current_out = totals_by_date.get(
            item["reference_date"], (Decimal("0"), Decimal("0"))
        )
        totals_by_date[item["reference_date"]] = (
            current_in + Decimal(item["inflow_exact"]),
            current_out + Decimal(item["outflow_exact"]),
        )
    for item in items:
        total_in, total_out = totals_by_date[item["reference_date"]]
        inflow = Decimal(item["inflow_exact"])
        outflow = Decimal(item["outflow_exact"])
        item["buy_participation_pct"] = float(
            (inflow / total_in * 100).quantize(Decimal("0.01"))
        ) if total_in else None
        item["sell_participation_pct"] = float(
            (outflow / total_out * 100).quantize(Decimal("0.01"))
        ) if total_out else None
        item["total_participation_pct"] = float(
            ((inflow + outflow) / (total_in + total_out) * 100).quantize(Decimal("0.01"))
        ) if total_in + total_out else None
        item["market_scope"] = "B3_TOTAL"
        item["currency"] = "BRL"
        item["validation_status"] = "VALID"
    latest = max((item["updated_at"] for item in items), default=None)
    latest_trade_date = max((item["reference_date"] for item in items), default=None)
    sources = sorted({item["source"] for item in items})
    lags = sorted({item["source_lag"] for item in items})
    official = any(is_official_source(item["source"]) for item in items)
    return {
        "ok": True,
        "items": items,
        "last_updated": latest,
        "latest_trade_date": latest_trade_date,
        "market_scope": "B3_TOTAL",
        "currency": "BRL",
        "category_count": len(INVESTOR_TYPES),
        "sources": sources,
        "source_lags": lags,
        "official_data": official,
        "notice": (
            "Compras e vendas obtidas no Boletim Diário do Mercado da B3. "
            "Os valores diários são calculados pela diferença entre acumulados oficiais "
            "e respeitam a defasagem de dois pregões."
            if official
            else "Não há dados oficiais sincronizados neste período."
        ),
    }

