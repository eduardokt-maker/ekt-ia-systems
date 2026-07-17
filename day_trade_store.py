from __future__ import annotations

import sqlite3
from datetime import datetime
from decimal import Decimal, InvalidOperation
from typing import Any
from zoneinfo import ZoneInfo

import main as main_module


DEFAULT_OWNER_KEY = main_module.DEFAULT_BUDGET_OWNER_KEY


def decimal_value(value: object, *, default: str = "0") -> Decimal:
    text = str(value if value not in (None, "") else default).strip().replace("R$", "").replace(" ", "")
    if "," in text:
        text = text.replace(".", "").replace(",", ".")
    try:
        return Decimal(text)
    except InvalidOperation as exc:
        raise ValueError("Informe um valor numerico valido.") from exc


def decimal_text(value: object, *, default: str = "0") -> str:
    return format(decimal_value(value, default=default).quantize(Decimal("0.0001")), "f")


def ensure_day_trade_db() -> None:
    main_module.ensure_investment_db()
    if main_module.use_postgres_investment_db():
        with main_module.psycopg.connect(main_module.investment_database_url()) as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS day_trade_settings (
                    owner_key TEXT PRIMARY KEY,
                    capital_text TEXT NOT NULL DEFAULT '0',
                    initial_capital_text TEXT NOT NULL DEFAULT '0',
                    daily_loss_limit_text TEXT NOT NULL DEFAULT '0',
                    daily_target_text TEXT NOT NULL DEFAULT '0',
                    max_operations INTEGER NOT NULL DEFAULT 5,
                    risk_per_trade_text TEXT NOT NULL DEFAULT '0',
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
                """
            )
            connection.execute(
                """
                ALTER TABLE day_trade_settings
                ADD COLUMN IF NOT EXISTS initial_capital_text TEXT NOT NULL DEFAULT '0'
                """
            )
            connection.execute(
                """
                UPDATE day_trade_settings
                SET initial_capital_text = capital_text
                WHERE initial_capital_text = '0' AND capital_text <> '0'
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS day_trade_capital_deposits (
                    id BIGSERIAL PRIMARY KEY,
                    owner_key TEXT NOT NULL,
                    deposit_date DATE NOT NULL,
                    movement_type TEXT NOT NULL DEFAULT 'Entrada',
                    source_type TEXT NOT NULL,
                    source_description TEXT NOT NULL DEFAULT '',
                    amount_text TEXT NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
                """
            )
            connection.execute(
                """
                ALTER TABLE day_trade_capital_deposits
                ADD COLUMN IF NOT EXISTS movement_type TEXT NOT NULL DEFAULT 'Entrada'
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS day_trade_operations (
                    id BIGSERIAL PRIMARY KEY,
                    owner_key TEXT NOT NULL,
                    trade_date DATE NOT NULL,
                    trade_weekday TEXT NOT NULL DEFAULT '',
                    entry_time TEXT NOT NULL,
                    exit_time TEXT,
                    asset TEXT NOT NULL,
                    market TEXT NOT NULL,
                    direction TEXT NOT NULL CHECK (direction IN ('Compra', 'Venda')),
                    quantity INTEGER NOT NULL CHECK (quantity > 0),
                    entry_price_text TEXT NOT NULL,
                    exit_price_text TEXT,
                    point_value_text TEXT NOT NULL,
                    stop_price_text TEXT NOT NULL,
                    target_price_text TEXT NOT NULL,
                    costs_text TEXT NOT NULL DEFAULT '0',
                    strategy TEXT NOT NULL,
                    exit_reason TEXT,
                    operation_status TEXT NOT NULL DEFAULT '',
                    notes TEXT,
                    status TEXT NOT NULL DEFAULT 'ABERTA' CHECK (status IN ('ABERTA', 'ENCERRADA')),
                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
                """
            )
            connection.execute(
                """
                ALTER TABLE day_trade_operations
                ADD COLUMN IF NOT EXISTS operation_status TEXT NOT NULL DEFAULT ''
                """
            )
            connection.execute(
                """
                ALTER TABLE day_trade_operations
                ADD COLUMN IF NOT EXISTS trade_weekday TEXT NOT NULL DEFAULT ''
                """
            )
            connection.execute(
                """
                UPDATE day_trade_operations
                SET trade_weekday = CASE EXTRACT(ISODOW FROM trade_date)
                    WHEN 1 THEN 'segunda-feira'
                    WHEN 2 THEN 'terça-feira'
                    WHEN 3 THEN 'quarta-feira'
                    WHEN 4 THEN 'quinta-feira'
                    WHEN 5 THEN 'sexta-feira'
                    WHEN 6 THEN 'sábado'
                    WHEN 7 THEN 'domingo'
                END
                WHERE trade_weekday = ''
                """
            )
            connection.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_day_trade_owner_date
                ON day_trade_operations (owner_key, trade_date, id)
                """
            )
        return

    with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS day_trade_settings (
                owner_key TEXT PRIMARY KEY,
                capital_text TEXT NOT NULL DEFAULT '0',
                initial_capital_text TEXT NOT NULL DEFAULT '0',
                daily_loss_limit_text TEXT NOT NULL DEFAULT '0',
                daily_target_text TEXT NOT NULL DEFAULT '0',
                max_operations INTEGER NOT NULL DEFAULT 5,
                risk_per_trade_text TEXT NOT NULL DEFAULT '0',
                updated_at TEXT NOT NULL
            )
            """
        )
        settings_columns = {
            str(row[1])
            for row in connection.execute("PRAGMA table_info(day_trade_settings)")
        }
        if "initial_capital_text" not in settings_columns:
            connection.execute(
                "ALTER TABLE day_trade_settings "
                "ADD COLUMN initial_capital_text TEXT NOT NULL DEFAULT '0'"
            )
        connection.execute(
            """
            UPDATE day_trade_settings
            SET initial_capital_text = capital_text
            WHERE initial_capital_text = '0' AND capital_text <> '0'
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS day_trade_capital_deposits (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                owner_key TEXT NOT NULL,
                deposit_date TEXT NOT NULL,
                movement_type TEXT NOT NULL DEFAULT 'Entrada',
                source_type TEXT NOT NULL,
                source_description TEXT NOT NULL DEFAULT '',
                amount_text TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
            """
        )
        deposit_columns = {
            str(row[1])
            for row in connection.execute(
                "PRAGMA table_info(day_trade_capital_deposits)"
            )
        }
        if "movement_type" not in deposit_columns:
            connection.execute(
                "ALTER TABLE day_trade_capital_deposits "
                "ADD COLUMN movement_type TEXT NOT NULL DEFAULT 'Entrada'"
            )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS day_trade_operations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                owner_key TEXT NOT NULL,
                trade_date TEXT NOT NULL,
                trade_weekday TEXT NOT NULL DEFAULT '',
                entry_time TEXT NOT NULL,
                exit_time TEXT,
                asset TEXT NOT NULL,
                market TEXT NOT NULL,
                direction TEXT NOT NULL CHECK (direction IN ('Compra', 'Venda')),
                quantity INTEGER NOT NULL CHECK (quantity > 0),
                entry_price_text TEXT NOT NULL,
                exit_price_text TEXT,
                point_value_text TEXT NOT NULL,
                stop_price_text TEXT NOT NULL,
                target_price_text TEXT NOT NULL,
                costs_text TEXT NOT NULL DEFAULT '0',
                strategy TEXT NOT NULL,
                exit_reason TEXT,
                operation_status TEXT NOT NULL DEFAULT '',
                notes TEXT,
                status TEXT NOT NULL DEFAULT 'ABERTA' CHECK (status IN ('ABERTA', 'ENCERRADA')),
                created_at TEXT NOT NULL
            )
            """
        )
        columns = {
            str(row[1])
            for row in connection.execute("PRAGMA table_info(day_trade_operations)")
        }
        if "operation_status" not in columns:
            connection.execute(
                "ALTER TABLE day_trade_operations "
                "ADD COLUMN operation_status TEXT NOT NULL DEFAULT ''"
            )
        if "trade_weekday" not in columns:
            connection.execute(
                "ALTER TABLE day_trade_operations "
                "ADD COLUMN trade_weekday TEXT NOT NULL DEFAULT ''"
            )
        connection.execute(
            """
            UPDATE day_trade_operations
            SET trade_weekday = CASE strftime('%w', trade_date)
                WHEN '0' THEN 'domingo'
                WHEN '1' THEN 'segunda-feira'
                WHEN '2' THEN 'terça-feira'
                WHEN '3' THEN 'quarta-feira'
                WHEN '4' THEN 'quinta-feira'
                WHEN '5' THEN 'sexta-feira'
                WHEN '6' THEN 'sábado'
            END
            WHERE trade_weekday = ''
            """
        )
        connection.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_day_trade_owner_date
            ON day_trade_operations (owner_key, trade_date, id)
            """
        )


def load_settings(owner_key: str = DEFAULT_OWNER_KEY) -> dict[str, Any]:
    ensure_day_trade_db()
    query = """
        SELECT capital_text, initial_capital_text, daily_loss_limit_text,
               daily_target_text, max_operations, risk_per_trade_text
        FROM day_trade_settings WHERE owner_key = {placeholder}
    """
    if main_module.use_postgres_investment_db():
        with main_module.psycopg.connect(main_module.investment_database_url()) as connection:
            row = connection.execute(query.format(placeholder="%s"), (owner_key,)).fetchone()
    else:
        with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
            row = connection.execute(query.format(placeholder="?"), (owner_key,)).fetchone()
    if row is None:
        return {
            "capital_text": "0",
            "initial_capital_text": "0",
            "daily_loss_limit_text": "0",
            "daily_target_text": "0",
            "max_operations": 5,
            "risk_per_trade_text": "0",
        }
    return {
        "capital_text": str(row[0]),
        "initial_capital_text": str(row[1]),
        "daily_loss_limit_text": str(row[2]),
        "daily_target_text": str(row[3]),
        "max_operations": int(row[4]),
        "risk_per_trade_text": str(row[5]),
    }


def _capital_deposit_total(owner_key: str = DEFAULT_OWNER_KEY) -> Decimal:
    query = """
        SELECT amount_text, movement_type FROM day_trade_capital_deposits
        WHERE owner_key = {placeholder}
    """
    if main_module.use_postgres_investment_db():
        with main_module.psycopg.connect(main_module.investment_database_url()) as connection:
            rows = connection.execute(
                query.format(placeholder="%s"), (owner_key,)
            ).fetchall()
    else:
        with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
            rows = connection.execute(
                query.format(placeholder="?"), (owner_key,)
            ).fetchall()
    return sum(
        (
            -decimal_value(row[0])
            if str(row[1]) == "Subtracao"
            else decimal_value(row[0])
            for row in rows
        ),
        Decimal("0"),
    )


def save_settings(settings: dict[str, Any], owner_key: str = DEFAULT_OWNER_KEY) -> dict[str, Any]:
    ensure_day_trade_db()
    initial_capital = decimal_value(settings.get("capital_text"))
    current_capital = initial_capital + _capital_deposit_total(owner_key)
    values = (
        owner_key,
        decimal_text(current_capital),
        decimal_text(initial_capital),
        decimal_text(settings.get("daily_loss_limit_text")),
        decimal_text(settings.get("daily_target_text")),
        int(settings.get("max_operations", 5)),
        decimal_text(settings.get("risk_per_trade_text")),
    )
    if main_module.use_postgres_investment_db():
        with main_module.psycopg.connect(main_module.investment_database_url()) as connection:
            connection.execute(
                """
                INSERT INTO day_trade_settings (
                    owner_key, capital_text, initial_capital_text,
                    daily_loss_limit_text, daily_target_text,
                    max_operations, risk_per_trade_text, updated_at
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, NOW())
                ON CONFLICT (owner_key) DO UPDATE SET
                    capital_text = EXCLUDED.capital_text,
                    initial_capital_text = EXCLUDED.initial_capital_text,
                    daily_loss_limit_text = EXCLUDED.daily_loss_limit_text,
                    daily_target_text = EXCLUDED.daily_target_text,
                    max_operations = EXCLUDED.max_operations,
                    risk_per_trade_text = EXCLUDED.risk_per_trade_text,
                    updated_at = NOW()
                """,
                values,
            )
    else:
        now = datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds")
        with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
            connection.execute(
                """
                INSERT INTO day_trade_settings (
                    owner_key, capital_text, initial_capital_text,
                    daily_loss_limit_text, daily_target_text,
                    max_operations, risk_per_trade_text, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(owner_key) DO UPDATE SET
                    capital_text = excluded.capital_text,
                    initial_capital_text = excluded.initial_capital_text,
                    daily_loss_limit_text = excluded.daily_loss_limit_text,
                    daily_target_text = excluded.daily_target_text,
                    max_operations = excluded.max_operations,
                    risk_per_trade_text = excluded.risk_per_trade_text,
                    updated_at = excluded.updated_at
                """,
                (*values, now),
            )
    return load_settings(owner_key)


def save_initial_capital(
    capital_text: str, owner_key: str = DEFAULT_OWNER_KEY
) -> dict[str, Any]:
    ensure_day_trade_db()
    initial_capital = decimal_value(capital_text)
    current_capital = initial_capital + _capital_deposit_total(owner_key)
    if main_module.use_postgres_investment_db():
        with main_module.psycopg.connect(main_module.investment_database_url()) as connection:
            connection.execute(
                """
                INSERT INTO day_trade_settings (
                    owner_key, capital_text, initial_capital_text, updated_at
                ) VALUES (%s, %s, %s, NOW())
                ON CONFLICT (owner_key) DO UPDATE SET
                    capital_text = EXCLUDED.capital_text,
                    initial_capital_text = EXCLUDED.initial_capital_text,
                    updated_at = NOW()
                """,
                (
                    owner_key,
                    decimal_text(current_capital),
                    decimal_text(initial_capital),
                ),
            )
    else:
        now = datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds")
        with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
            connection.execute(
                """
                INSERT INTO day_trade_settings (
                    owner_key, capital_text, initial_capital_text, updated_at
                ) VALUES (?, ?, ?, ?)
                ON CONFLICT(owner_key) DO UPDATE SET
                    capital_text = excluded.capital_text,
                    initial_capital_text = excluded.initial_capital_text,
                    updated_at = excluded.updated_at
                """,
                (
                    owner_key,
                    decimal_text(current_capital),
                    decimal_text(initial_capital),
                    now,
                ),
            )
    return load_settings(owner_key)


def save_capital(capital_text: str, owner_key: str = DEFAULT_OWNER_KEY) -> dict[str, Any]:
    return save_initial_capital(capital_text, owner_key)


def list_capital_deposits(owner_key: str = DEFAULT_OWNER_KEY) -> list[dict[str, Any]]:
    ensure_day_trade_db()
    query = """
        SELECT id, deposit_date, movement_type, source_type,
               source_description, amount_text, created_at
        FROM day_trade_capital_deposits
        WHERE owner_key = {placeholder}
        ORDER BY deposit_date DESC, id DESC
    """
    if main_module.use_postgres_investment_db():
        with main_module.psycopg.connect(main_module.investment_database_url()) as connection:
            rows = connection.execute(
                query.format(placeholder="%s"), (owner_key,)
            ).fetchall()
    else:
        with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
            rows = connection.execute(
                query.format(placeholder="?"), (owner_key,)
            ).fetchall()
    return [
        {
            "id": int(row[0]),
            "deposit_date": str(row[1])[:10],
            "movement_type": str(row[2]),
            "source_type": str(row[3]),
            "source_description": str(row[4] or ""),
            "amount_text": str(row[5]),
            "created_at": str(row[6]),
        }
        for row in rows
    ]


def operations_net_result(owner_key: str = DEFAULT_OWNER_KEY) -> Decimal:
    """Return the net result of every closed Day Trade operation."""
    ensure_day_trade_db()
    query = """
        SELECT direction, quantity, entry_price_text, exit_price_text,
               point_value_text, costs_text
        FROM day_trade_operations
        WHERE owner_key = {placeholder}
          AND status = 'ENCERRADA'
          AND exit_price_text IS NOT NULL
          AND exit_price_text <> ''
    """
    if main_module.use_postgres_investment_db():
        with main_module.psycopg.connect(main_module.investment_database_url()) as connection:
            rows = connection.execute(
                query.format(placeholder="%s"), (owner_key,)
            ).fetchall()
    else:
        with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
            rows = connection.execute(
                query.format(placeholder="?"), (owner_key,)
            ).fetchall()

    result = Decimal("0")
    for (
        direction,
        quantity,
        entry_text,
        exit_text,
        point_value_text,
        costs_text,
    ) in rows:
        entry = decimal_value(entry_text)
        exit_price = decimal_value(exit_text)
        difference = (
            exit_price - entry if str(direction) == "Compra" else entry - exit_price
        )
        gross = difference * Decimal(int(quantity)) * decimal_value(
            point_value_text, default="1"
        )
        result += gross - decimal_value(costs_text, default="0")
    return result


def capital_statement(owner_key: str = DEFAULT_OWNER_KEY) -> dict[str, Any]:
    """Build a chronological audit trail for the Day Trade capital balance."""
    summary = capital_summary(owner_key)
    initial = decimal_value(summary["initial_capital_text"])
    entries: list[dict[str, Any]] = []
    if initial != 0:
        entries.append(
            {
                "id": "initial",
                "sort_key": "0000-00-00T00:00:00-initial",
                "date": "",
                "time": "",
                "type": "capital_initial",
                "title": "Capital inicial",
                "description": "Base inicial do investimento Day Trade",
                "amount": initial,
            }
        )

    for deposit in list_capital_deposits(owner_key):
        amount = decimal_value(deposit["amount_text"])
        if deposit["movement_type"] == "Subtracao":
            amount = -amount
        source_label = (
            "Ajuste manual Day Trade"
            if deposit["source_type"] == "Day Trade"
            else "Movimentacao externa"
        )
        entries.append(
            {
                "id": f"deposit-{deposit['id']}",
                "sort_key": (
                    f"{deposit['deposit_date']}T00:00:00-"
                    f"deposit-{int(deposit['id']):012d}"
                ),
                "date": deposit["deposit_date"],
                "time": "",
                "type": "manual_day_trade_adjustment"
                if deposit["source_type"] == "Day Trade"
                else "external_movement",
                "title": source_label,
                "description": deposit["source_description"] or source_label,
                "amount": amount,
            }
        )

    query = """
        SELECT id, trade_date, entry_time, asset, market, direction, quantity,
               entry_price_text, exit_price_text, point_value_text, costs_text,
               operation_status, strategy
        FROM day_trade_operations
        WHERE owner_key = {placeholder}
          AND status = 'ENCERRADA'
          AND exit_price_text IS NOT NULL
          AND exit_price_text <> ''
        ORDER BY trade_date, entry_time, id
    """
    if main_module.use_postgres_investment_db():
        with main_module.psycopg.connect(main_module.investment_database_url()) as connection:
            operation_rows = connection.execute(
                query.format(placeholder="%s"), (owner_key,)
            ).fetchall()
    else:
        with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
            operation_rows = connection.execute(
                query.format(placeholder="?"), (owner_key,)
            ).fetchall()

    for row in operation_rows:
        entry_price = decimal_value(row[7])
        exit_price = decimal_value(row[8])
        price_difference = (
            exit_price - entry_price
            if str(row[5]) == "Compra"
            else entry_price - exit_price
        )
        net_result = (
            price_difference
            * Decimal(int(row[6]))
            * decimal_value(row[9], default="1")
            - decimal_value(row[10], default="0")
        )
        operation_status = str(row[11] or "")
        asset = str(row[3])
        market = str(row[4])
        direction = str(row[5])
        quantity = int(row[6])
        strategy = str(row[12] or "")
        entries.append(
            {
                "id": f"operation-{int(row[0])}",
                "sort_key": (
                    f"{str(row[1])[:10]}T{str(row[2])}-"
                    f"operation-{int(row[0]):012d}"
                ),
                "date": str(row[1])[:10],
                "time": str(row[2]),
                "type": "day_trade_operation",
                "title": f"{operation_status or 'Operacao'} - {asset}",
                "description": (
                    f"{market} - {direction} - {quantity} contrato(s)"
                    + (f" - {strategy}" if strategy else "")
                ),
                "amount": net_result,
            }
        )

    entries.sort(key=lambda item: str(item["sort_key"]))
    running_balance = Decimal("0")
    serialized_entries: list[dict[str, Any]] = []
    for entry in entries:
        amount = decimal_value(entry.pop("amount"))
        running_balance += amount
        entry.pop("sort_key", None)
        serialized_entries.append(
            {
                **entry,
                "direction": "Entrada" if amount >= 0 else "Saida",
                "amount_text": decimal_text(amount),
                "balance_text": decimal_text(running_balance),
            }
        )

    return {**summary, "statement_entries": serialized_entries}


def capital_summary(owner_key: str = DEFAULT_OWNER_KEY) -> dict[str, Any]:
    settings = load_settings(owner_key)
    initial = decimal_value(settings.get("initial_capital_text"))
    deposits = list_capital_deposits(owner_key)
    external_net = sum(
        (
            -decimal_value(item["amount_text"])
            if item["movement_type"] == "Subtracao"
            else decimal_value(item["amount_text"])
            for item in deposits
            if item["source_type"] == "Capital extra"
        ),
        Decimal("0"),
    )
    manual_day_trade_adjustment = sum(
        (
            -decimal_value(item["amount_text"])
            if item["movement_type"] == "Subtracao"
            else decimal_value(item["amount_text"])
            for item in deposits
            if item["source_type"] == "Day Trade"
        ),
        Decimal("0"),
    )
    automatic_day_trade_result = operations_net_result(owner_key)
    day_trade_result = manual_day_trade_adjustment + automatic_day_trade_result
    movement_total = external_net + day_trade_result
    contributed_capital = initial + external_net
    current = contributed_capital + day_trade_result
    growth_percent = (
        movement_total / initial * Decimal("100") if initial else Decimal("0")
    )
    operational_return_percent = (
        day_trade_result / contributed_capital * Decimal("100")
        if contributed_capital > 0
        else Decimal("0")
    )
    day_trade_share_global_percent = (
        day_trade_result / current * Decimal("100")
        if current != 0
        else Decimal("0")
    )
    return {
        "initial_capital_text": decimal_text(initial),
        "capital_text": decimal_text(current),
        "deposited_total_text": decimal_text(movement_total),
        "growth_amount_text": decimal_text(movement_total),
        "growth_percent": float(growth_percent),
        "external_net_text": decimal_text(external_net),
        "day_trade_result_text": decimal_text(day_trade_result),
        "automatic_day_trade_result_text": decimal_text(
            automatic_day_trade_result
        ),
        "manual_day_trade_adjustment_text": decimal_text(
            manual_day_trade_adjustment
        ),
        "contributed_capital_text": decimal_text(contributed_capital),
        "operational_return_percent": float(operational_return_percent),
        "day_trade_share_global_percent": float(day_trade_share_global_percent),
        "deposits": deposits,
    }


def add_capital_deposit(
    deposit_date: str,
    movement_type: str,
    source_type: str,
    source_description: str,
    amount_text: str,
    owner_key: str = DEFAULT_OWNER_KEY,
) -> dict[str, Any]:
    ensure_day_trade_db()
    amount = decimal_text(amount_text)
    now = datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds")
    values = (
        owner_key,
        deposit_date,
        movement_type,
        source_type,
        source_description,
        amount,
    )
    if main_module.use_postgres_investment_db():
        with main_module.psycopg.connect(main_module.investment_database_url()) as connection:
            connection.execute(
                """
                INSERT INTO day_trade_capital_deposits (
                    owner_key, deposit_date, movement_type, source_type,
                    source_description, amount_text
                ) VALUES (%s, %s, %s, %s, %s, %s)
                """,
                values,
            )
    else:
        with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
            connection.execute(
                """
                INSERT INTO day_trade_capital_deposits (
                    owner_key, deposit_date, movement_type, source_type,
                    source_description, amount_text, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (*values, now),
            )
    summary = capital_summary(owner_key)
    save_initial_capital(summary["initial_capital_text"], owner_key)
    return capital_summary(owner_key)


def reset_capital(owner_key: str = DEFAULT_OWNER_KEY) -> dict[str, Any]:
    ensure_day_trade_db()
    if main_module.use_postgres_investment_db():
        with main_module.psycopg.connect(main_module.investment_database_url()) as connection:
            connection.execute(
                "DELETE FROM day_trade_capital_deposits WHERE owner_key = %s",
                (owner_key,),
            )
    else:
        with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
            connection.execute(
                "DELETE FROM day_trade_capital_deposits WHERE owner_key = ?",
                (owner_key,),
            )
    return save_initial_capital("0", owner_key)


def create_operation(item: dict[str, Any], owner_key: str = DEFAULT_OWNER_KEY) -> int:
    ensure_day_trade_db()
    now = datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds")
    operation_result = str(item["operation_result"])
    exit_price_text = (
        item["target_price_text"]
        if operation_result == "Gain"
        else item["stop_price_text"]
    )
    values = (
        owner_key,
        item["trade_date"],
        item["trade_weekday"],
        item["entry_time"],
        item["entry_time"],
        item["asset"],
        item["market"],
        item["direction"],
        int(item["quantity"]),
        decimal_text(item["entry_price_text"]),
        decimal_text(exit_price_text),
        decimal_text(item["point_value_text"], default="1"),
        decimal_text(item["stop_price_text"]),
        decimal_text(item["target_price_text"]),
        "0.0000",
        item["strategy"],
        operation_result,
        operation_result,
        item.get("notes", ""),
        "ENCERRADA",
    )
    if main_module.use_postgres_investment_db():
        with main_module.psycopg.connect(main_module.investment_database_url()) as connection:
            row = connection.execute(
                """
                INSERT INTO day_trade_operations (
                    owner_key, trade_date, trade_weekday, entry_time, exit_time, asset, market,
                    direction, quantity, entry_price_text, exit_price_text,
                    point_value_text, stop_price_text, target_price_text,
                    costs_text, strategy, exit_reason, operation_status, notes, status
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                          %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                RETURNING id
                """,
                values,
            ).fetchone()
        return int(row[0])
    with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
        cursor = connection.execute(
            """
            INSERT INTO day_trade_operations (
                owner_key, trade_date, trade_weekday, entry_time, exit_time, asset, market,
                direction, quantity, entry_price_text, exit_price_text,
                point_value_text, stop_price_text, target_price_text,
                costs_text, strategy, exit_reason, operation_status, notes,
                status, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (*values, now),
        )
    return int(cursor.lastrowid)


def update_operation(
    item_id: str,
    item: dict[str, Any],
    owner_key: str = DEFAULT_OWNER_KEY,
) -> bool:
    ensure_day_trade_db()
    operation_result = str(item["operation_result"])
    exit_price_text = (
        item["target_price_text"]
        if operation_result == "Gain"
        else item["stop_price_text"]
    )
    values = (
        item["trade_date"],
        item["trade_weekday"],
        item["entry_time"],
        item["entry_time"],
        item["asset"],
        item["market"],
        item["direction"],
        int(item["quantity"]),
        decimal_text(item["entry_price_text"]),
        decimal_text(exit_price_text),
        decimal_text(item["point_value_text"], default="1"),
        decimal_text(item["stop_price_text"]),
        decimal_text(item["target_price_text"]),
        item["strategy"],
        operation_result,
        operation_result,
        item.get("notes", ""),
        int(item_id),
        owner_key,
    )
    query = """
        UPDATE day_trade_operations
        SET trade_date = {p}, trade_weekday = {p}, entry_time = {p}, exit_time = {p},
            asset = {p}, market = {p}, direction = {p}, quantity = {p},
            entry_price_text = {p}, exit_price_text = {p},
            point_value_text = {p}, stop_price_text = {p},
            target_price_text = {p}, strategy = {p}, exit_reason = {p},
            operation_status = {p}, notes = {p}, status = 'ENCERRADA'
        WHERE id = {p} AND owner_key = {p}
    """
    if main_module.use_postgres_investment_db():
        with main_module.psycopg.connect(main_module.investment_database_url()) as connection:
            cursor = connection.execute(query.format(p="%s"), values)
    else:
        with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
            cursor = connection.execute(query.format(p="?"), values)
    return cursor.rowcount > 0


def close_operation(
    item_id: str,
    exit_price_text: str,
    exit_time: str,
    costs_text: str,
    exit_reason: str,
    owner_key: str = DEFAULT_OWNER_KEY,
) -> bool:
    ensure_day_trade_db()
    select_query = """
        SELECT entry_time, status FROM day_trade_operations
        WHERE id = {p} AND owner_key = {p}
    """
    if main_module.use_postgres_investment_db():
        with main_module.psycopg.connect(main_module.investment_database_url()) as connection:
            existing = connection.execute(
                select_query.format(p="%s"), (int(item_id), owner_key)
            ).fetchone()
    else:
        with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
            existing = connection.execute(
                select_query.format(p="?"), (int(item_id), owner_key)
            ).fetchone()
    if existing is None or str(existing[1]) != "ABERTA":
        return False
    if exit_time < str(existing[0]):
        raise ValueError("O horario de saida nao pode ser anterior ao horario de entrada.")
    values = (
        decimal_text(exit_price_text),
        exit_time,
        decimal_text(costs_text),
        exit_reason,
        "Gain"
        if exit_reason == "Alvo atingido"
        else "stop loss"
        if exit_reason == "Stop acionado"
        else "",
        int(item_id),
        owner_key,
    )
    query = """
        UPDATE day_trade_operations
        SET exit_price_text = {p}, exit_time = {p}, costs_text = {p},
            exit_reason = {p}, operation_status = {p}, status = 'ENCERRADA'
        WHERE id = {p} AND owner_key = {p} AND status = 'ABERTA'
    """
    if main_module.use_postgres_investment_db():
        with main_module.psycopg.connect(main_module.investment_database_url()) as connection:
            cursor = connection.execute(query.format(p="%s"), values)
    else:
        with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
            cursor = connection.execute(query.format(p="?"), values)
    return cursor.rowcount > 0


def delete_operation(item_id: str, owner_key: str = DEFAULT_OWNER_KEY) -> bool:
    ensure_day_trade_db()
    if main_module.use_postgres_investment_db():
        with main_module.psycopg.connect(main_module.investment_database_url()) as connection:
            cursor = connection.execute(
                "DELETE FROM day_trade_operations WHERE id = %s AND owner_key = %s",
                (int(item_id), owner_key),
            )
    else:
        with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
            cursor = connection.execute(
                "DELETE FROM day_trade_operations WHERE id = ? AND owner_key = ?",
                (int(item_id), owner_key),
            )
    return cursor.rowcount > 0


def operation_metrics(item: dict[str, Any]) -> dict[str, float | str]:
    entry = decimal_value(item["entry_price_text"])
    point_value = decimal_value(item["point_value_text"], default="1")
    quantity = Decimal(int(item["quantity"]))
    stop = decimal_value(item["stop_price_text"])
    target = decimal_value(item["target_price_text"])
    planned_risk = abs(entry - stop) * quantity * point_value
    potential_gain = abs(target - entry) * quantity * point_value
    risk_reward = potential_gain / planned_risk if planned_risk else Decimal("0")
    gross = Decimal("0")
    net = Decimal("0")
    if item["status"] == "ENCERRADA" and item.get("exit_price_text"):
        exit_price = decimal_value(item["exit_price_text"])
        difference = exit_price - entry if item["direction"] == "Compra" else entry - exit_price
        gross = difference * quantity * point_value
        net = gross - decimal_value(item.get("costs_text", "0"))
    return {
        "planned_risk": float(planned_risk),
        "potential_gain": float(potential_gain),
        "risk_reward": float(risk_reward),
        "gross_result": float(gross),
        "net_result": float(net),
    }


def _operation_rows_to_items(rows: list[tuple[Any, ...]]) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for row in rows:
        item = {
            "id": int(row[0]),
            "trade_date": str(row[1])[:10],
            "trade_weekday": str(row[2]),
            "entry_time": str(row[3]),
            "exit_time": str(row[4] or ""),
            "asset": str(row[5]),
            "market": str(row[6]),
            "direction": str(row[7]),
            "quantity": int(row[8]),
            "entry_price_text": str(row[9]),
            "exit_price_text": str(row[10] or ""),
            "point_value_text": str(row[11]),
            "stop_price_text": str(row[12]),
            "target_price_text": str(row[13]),
            "costs_text": str(row[14] or "0"),
            "strategy": str(row[15]),
            "exit_reason": str(row[16] or ""),
            "notes": str(row[17] or ""),
            "status": str(row[18]),
            "created_at": str(row[19]),
            "operation_result": str(row[20] or ""),
        }
        entry = decimal_value(item["entry_price_text"])
        stop = decimal_value(item["stop_price_text"])
        target = decimal_value(item["target_price_text"])
        item["stop_points"] = float(abs(entry - stop))
        item["target_points"] = float(abs(target - entry))
        item["total_point_value"] = float(
            decimal_value(item["point_value_text"]) * Decimal(item["quantity"])
        )
        item.update(operation_metrics(item))
        items.append(item)
    return items


def list_operations_range(
    date_from: str, date_to: str, owner_key: str = DEFAULT_OWNER_KEY
) -> list[dict[str, Any]]:
    ensure_day_trade_db()
    query = """
        SELECT id, trade_date, trade_weekday, entry_time, exit_time, asset, market, direction,
               quantity, entry_price_text, exit_price_text, point_value_text,
               stop_price_text, target_price_text, costs_text, strategy,
               exit_reason, notes, status, created_at, operation_status
        FROM day_trade_operations
        WHERE owner_key = {p} AND trade_date BETWEEN {p} AND {p}
        ORDER BY trade_date, entry_time, id
    """
    if main_module.use_postgres_investment_db():
        with main_module.psycopg.connect(main_module.investment_database_url()) as connection:
            rows = connection.execute(
                query.format(p="%s"), (owner_key, date_from, date_to)
            ).fetchall()
    else:
        with sqlite3.connect(main_module.INVESTMENT_DB_PATH) as connection:
            rows = connection.execute(
                query.format(p="?"), (owner_key, date_from, date_to)
            ).fetchall()
    return _operation_rows_to_items(rows)


def list_operations(trade_date: str, owner_key: str = DEFAULT_OWNER_KEY) -> list[dict[str, Any]]:
    return list_operations_range(trade_date, trade_date, owner_key)


def build_bi_payload(
    date_from: str, date_to: str, owner_key: str = DEFAULT_OWNER_KEY
) -> dict[str, Any]:
    return {
        "ok": True,
        "date_from": date_from,
        "date_to": date_to,
        "account_type": "REAL",
        "items": list_operations_range(date_from, date_to, owner_key),
    }


def build_payload(trade_date: str, owner_key: str = DEFAULT_OWNER_KEY) -> dict[str, Any]:
    items = list_operations(trade_date, owner_key)
    settings = load_settings(owner_key)
    closed = [item for item in items if item["status"] == "ENCERRADA"]
    net_result = sum(float(item["net_result"]) for item in closed)
    gains = sum(1 for item in closed if float(item["net_result"]) > 0)
    losses = sum(1 for item in closed if float(item["net_result"]) < 0)
    costs = sum(decimal_value(item["costs_text"]) for item in closed)
    max_operations = int(settings["max_operations"])
    return {
        "ok": True,
        "trade_date": trade_date,
        "account_type": "REAL",
        "settings": settings,
        "items": items,
        "summary": {
            "net_result": net_result,
            "gross_result": sum(float(item["gross_result"]) for item in closed),
            "costs": float(costs),
            "gains": gains,
            "losses": losses,
            "open_operations": sum(1 for item in items if item["status"] == "ABERTA"),
            "closed_operations": len(closed),
            "operation_count": len(items),
            "operations_remaining": max(0, max_operations - len(items)),
            "win_rate": (gains / len(closed) * 100) if closed else 0,
        },
    }
