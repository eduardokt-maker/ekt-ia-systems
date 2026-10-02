"""Independent day trade cash ledger, with amounts stored in integer cents."""
from datetime import date
from decimal import Decimal, InvalidOperation

import auth_store
import main


def ensure_db():
    primary = "BIGSERIAL PRIMARY KEY" if main.use_postgres_investment_db() else "INTEGER PRIMARY KEY AUTOINCREMENT"
    with auth_store._connection() as connection:
        connection.execute(f"""CREATE TABLE IF NOT EXISTS day_trade_balance_entries (
            id {primary}, owner_key TEXT NOT NULL, entry_date TEXT NOT NULL,
            direction TEXT NOT NULL, description TEXT NOT NULL, amount_cents BIGINT NOT NULL
        )""")


def summary(owner_key):
    ensure_db()
    placeholder = auth_store._placeholder()
    with auth_store._connection() as connection:
        rows = connection.execute(
            f"SELECT id, entry_date, direction, description, amount_cents FROM day_trade_balance_entries WHERE owner_key = {placeholder} ORDER BY entry_date, id",
            (owner_key,),
        ).fetchall()
    incoming = outgoing = balance = 0
    entries = []
    for row in rows:
        amount = int(row[4])
        if row[2] == "Entrada":
            incoming += amount
            balance += amount
        else:
            outgoing += amount
            balance -= amount
        entries.append(dict(id=row[0], date=row[1], direction=row[2], description=row[3], amount_cents=amount, balance_cents=balance))
    return dict(entries=list(reversed(entries)), incoming_cents=incoming, outgoing_cents=outgoing, balance_cents=balance)


def add_entry(owner_key, payload):
    direction = str(payload.get("direction", ""))
    if direction not in {"Entrada", "Saída"}:
        raise ValueError("Selecione Entrada ou Saída.")
    try:
        entry_date = date.fromisoformat(str(payload.get("date", ""))).isoformat()
    except ValueError:
        raise ValueError("Informe uma data válida.") from None
    description = str(payload.get("description", "")).strip()
    if not description or len(description) > 200:
        raise ValueError("Informe uma descrição de até 200 caracteres.")
    raw = str(payload.get("amount", "")).strip()
    if "," in raw:
        raw = raw.replace(".", "").replace(",", ".")
    try:
        amount = Decimal(raw)
        if not amount.is_finite() or amount <= 0 or amount > Decimal("999999999999.99") or amount != amount.quantize(Decimal("0.01")):
            raise ValueError()
        cents = int(amount * 100)
    except (ValueError, InvalidOperation):
        raise ValueError("Informe um valor positivo com até duas casas decimais.") from None
    ensure_db()
    placeholder = auth_store._placeholder()
    with auth_store._connection() as connection:
        connection.execute(
            f"INSERT INTO day_trade_balance_entries (owner_key, entry_date, direction, description, amount_cents) VALUES ({', '.join([placeholder] * 5)})",
            (owner_key, entry_date, direction, description, cents),
        )
    return summary(owner_key)
