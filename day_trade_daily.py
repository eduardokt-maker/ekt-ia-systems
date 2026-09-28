"""Durable daily net results, kept separate from individual operations."""
from contextlib import contextmanager
from datetime import date, datetime, timezone
from decimal import Decimal
import sqlite3

import main


@contextmanager
def connection():
    pg = main.use_postgres_investment_db()
    manager = main.investment_db_connection() if pg else sqlite3.connect(main.INVESTMENT_DB_PATH)
    try:
        with manager as db:
            yield db, "%s" if pg else "?"
    finally:
        if not pg:
            manager.close()


def ensure_schema():
    with connection() as (db, _):
        db.execute("""CREATE TABLE IF NOT EXISTS day_trade_daily_results (
            owner_key TEXT NOT NULL, trade_date DATE NOT NULL,
            net_result_text TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
            revision INTEGER NOT NULL, updated_at TEXT NOT NULL,
            PRIMARY KEY (owner_key, trade_date))""")
        db.execute("""CREATE TABLE IF NOT EXISTS day_trade_daily_history (
            owner_key TEXT NOT NULL, trade_date DATE NOT NULL,
            net_result_text TEXT NOT NULL, notes TEXT NOT NULL,
            revision INTEGER NOT NULL, updated_at TEXT NOT NULL,
            PRIMARY KEY (owner_key, trade_date, revision))""")


def lock_owner(db, owner_key, pg):
    # Both entry paths take the same transaction lock before checking the mode.
    if pg:
        db.execute("SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))", ("day-trade:" + owner_key,))
    else:
        db.execute("BEGIN IMMEDIATE")


def require_detailed_day(db, owner_key, trade_date, pg):
    lock_owner(db, owner_key, pg)
    p = "%s" if pg else "?"
    if db.execute(f"SELECT 1 FROM day_trade_daily_results WHERE owner_key = {p} AND trade_date = {p}", (owner_key, trade_date)).fetchone():
        raise ValueError("Este dia já tem um resultado líquido consolidado. Edite esse resultado; operações individuais duplicariam o valor.")


def list_results(owner_key, date_from="0001-01-01", date_to="9999-12-31"):
    with connection() as (db, p):
        rows = db.execute(f"""SELECT trade_date, net_result_text, notes, revision, updated_at
            FROM day_trade_daily_results WHERE owner_key = {p} AND trade_date BETWEEN {p} AND {p}
            ORDER BY trade_date""", (owner_key, date_from, date_to)).fetchall()
    return [dict(trade_date=str(r[0])[:10], net_result_text=r[1], net_result=float(Decimal(r[1])),
                 notes=r[2], revision=r[3], updated_at=r[4], entry_mode="daily_net") for r in rows]


def save(owner_key, trade_date, net_result_text, notes, expected_revision):
    from day_trade_store import decimal_value, ensure_day_trade_db
    ensure_day_trade_db()
    if date.fromisoformat(trade_date).isoformat() != trade_date:
        raise ValueError("Informe uma data válida.")
    if net_result_text is None or not str(net_result_text).strip():
        raise ValueError("Informe o resultado líquido do dia, inclusive quando for zero.")
    value = decimal_value(net_result_text)
    if not value.is_finite() or abs(value) > Decimal("999999999999.99"):
        raise ValueError("Informe um resultado líquido válido.")
    if value != value.quantize(Decimal("0.01")):
        raise ValueError("Use no máximo duas casas decimais.")
    value_text = format(value.quantize(Decimal("0.01")), "f")
    notes = str(notes or "").strip()
    if len(notes) > 2000:
        raise ValueError("Use no máximo 2000 caracteres nas observações.")
    if type(expected_revision) is not int or expected_revision < 0:
        raise ValueError("Atualize a tela antes de salvar o resultado.")
    with connection() as (db, p):
        lock_owner(db, owner_key, main.use_postgres_investment_db())
        if db.execute(f"SELECT 1 FROM day_trade_operations WHERE owner_key = {p} AND trade_date = {p} LIMIT 1", (owner_key, trade_date)).fetchone():
            raise ValueError("Este dia já possui operações individuais. O resultado é calculado por elas; não é possível somar outro resultado para a mesma data.")
        current = db.execute(f"SELECT revision, net_result_text, notes FROM day_trade_daily_results WHERE owner_key = {p} AND trade_date = {p}", (owner_key, trade_date)).fetchone()
        revision = current[0] if current else 0
        if current and current[1:] == (value_text, notes):
            return  # Safe retry: never add the amount a second time.
        if expected_revision != revision:
            raise ValueError("Este resultado foi alterado em outra sessão. Atualize a tela antes de editar.")
        values = (owner_key, trade_date, value_text, notes, revision + 1, datetime.now(timezone.utc).isoformat())
        db.execute(f"""INSERT INTO day_trade_daily_results
            (owner_key, trade_date, net_result_text, notes, revision, updated_at)
            VALUES ({', '.join([p] * 6)}) ON CONFLICT (owner_key, trade_date) DO UPDATE SET
            net_result_text = excluded.net_result_text, notes = excluded.notes,
            revision = excluded.revision, updated_at = excluded.updated_at""", values)
        db.execute(f"INSERT INTO day_trade_daily_history (owner_key, trade_date, net_result_text, notes, revision, updated_at) VALUES ({', '.join([p] * 6)})", values)
