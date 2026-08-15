from __future__ import annotations

import calendar
import flet as ft
import flet.canvas as cv
import html
import hmac
import json
import os
import re
import secrets
import sqlite3
import time
import unicodedata
from datetime import datetime, time as datetime_time
from pathlib import Path
from urllib.parse import urlparse
from zoneinfo import ZoneInfo

try:
    import psycopg
except ImportError:
    psycopg = None

from market_data import (
    SHANGHAI_TICKER,
    IBOVESPA_FALLBACK_TICKERS,
    RARE_EARTH_TICKERS,
    US_AI_TICKERS,
    US_INDEX_TICKERS,
    daily_quote_for_search,
    fetch_dollar_brl_quote,
    fetch_brazil_fundamentals,
    fetch_ibov_dashboard_quote,
    fetch_ibovespa_portfolio,
    fetch_yahoo_candles,
    fetch_yahoo_candles_cached,
    is_any_index_market_open,
    is_brazil_market_open,
    is_brazil_quote_stale,
    is_cme_equity_futures_market_open,
    is_forex_market_open,
    is_japan_market_open,
    is_shanghai_market_open,
    is_us_stock_market_open,
    fundamental_valuation,
    label_indexes,
    moving_average,
    multi_horizon_trend,
    price_text,
    save_candlestick_svg,
    stream_brazil_market_quotes,
    stream_emini_sp500_quote,
    stream_nikkei_quote,
    stream_rare_earth_quotes,
    stream_shanghai_quote,
    stream_tradingview_quotes,
    stream_us_market_quotes,
    trend_explanation,
    yahoo_symbol_for_search,
)


FAST_REFRESH_SECONDS = 5
IBOV_REFRESH_SECONDS = max(
    30,
    int(os.getenv("IBOV_REFRESH_SECONDS", "60" if os.getenv("BRAPI_TOKEN") else "300")),
)
FULL_REFRESH_SECONDS = 60
INITIAL_FULL_REFRESH_DELAY_SECONDS = 10
APP_VERSION = "2026.07.09-budget-form-field-font-v29"
INVESTMENT_DATA_DIR = Path(os.getenv("EKT_DATA_DIR", Path(__file__).with_name("data")))
INVESTMENT_DB_PATH = INVESTMENT_DATA_DIR / "investments.db"
LEGACY_INVESTMENT_DB_PATH = Path(__file__).with_name("investments.db")
CLIENT_INVESTMENTS_KEY = "ekt_ia_systems.saved_investments"
CLIENT_INVESTMENT_AMOUNTS_KEY = "ekt_ia_systems.investment_amounts"
CLIENT_MONTHLY_BUDGET_KEY = "ekt_ia_systems.monthly_budget"
DEFAULT_BUDGET_OWNER_KEY = "adm"
DAY_TRADE_INVESTMENT_NAME = "Capital alocado Day Trade"
BUDGET_REPORT_PRINT_TOKENS: dict[str, tuple[float, str]] = {}
BUDGET_REPORT_TOKEN_TTL_SECONDS = 15 * 60
LEGACY_BUDGET_TABLES = (
    "budget_values",
    "budget_expenses",
    "budget_revenues",
    "budget_entries",
    "budget_fields",
    "budget_schemas",
)
IBOV_SECTORS = {
    "Financeiro e Seguros": {
        "B3SA3", "BBAS3", "BBDC3", "BBDC4", "BBSE3", "BPAC11", "CXSE3",
        "ITSA4", "ITUB4", "PSSA3", "SANB11",
    },
    "Energia Eletrica e Saneamento": {
        "AURE3", "AXIA3", "CMIG4", "CPFE3", "CPLE3", "CSMG3", "EGIE3",
        "ENEV3", "ENGI11", "EQTL3", "ISAE4", "SBSP3", "TAEE11",
    },
    "Petroleo, Gas e Combustiveis": {
        "BRAV3", "CSAN3", "PETR3", "PETR4", "PRIO3", "RECV3",
        "UGPA3", "VBBR3",
    },
    "Mineracao, Siderurgia e Papel": {
        "BRAP4", "CMIN3", "CSNA3", "GGBR4", "GOAU4", "KLBN11", "SUZB3",
        "USIM5", "VALE3",
    },
    "Alimentos, Bebidas e Agro": {
        "ABEV3", "BEEF3", "MBRF3", "SLCE3",
    },
    "Varejo e Consumo": {
        "ASAI3", "AZZA3", "CEAB3", "LREN3", "MGLU3", "NATU3", "VIVA3",
    },
    "Saude": {"FLRY3", "HAPV3", "HYPE3", "RADL3", "RDOR3"},
    "Construcao e Imoveis": {
        "ALOS3", "CURY3", "CYRE3", "DIRR3", "IGTI11", "MRVE3", "MULT3",
    },
    "Transporte, Logistica e Locacao": {
        "MOTV3", "POMO4", "RAIL3", "RENT3",
        "VAMO3",
    },
    "Industria e Materiais": {"BRKM5", "EMBJ3", "WEGE3"},
    "Tecnologia, Telecom e Educacao": {"COGN3", "TIMS3", "TOTS3", "VIVT3", "YDUQ3"},
    "Servicos": {"SMFT3"},
    "Outros": set(),
}
IBOV_SECTOR_BY_SYMBOL = {
    symbol: sector
    for sector, symbols in IBOV_SECTORS.items()
    for symbol in symbols
}
SANTANDER_FIXED_INCOME_OPTIONS = [
    {
        "name": "CDB CDI Santander",
        "issuer": "Banco Santander Brasil",
        "category": "CDB",
        "indexer": "Pos-fixado CDI",
        "maturity": "Conforme oferta disponivel",
        "source": "Santander Investimentos",
    },
    {
        "name": "LCI Pos Santander 18 meses",
        "issuer": "Banco Santander Brasil",
        "category": "LCI",
        "indexer": "Pos-fixado",
        "maturity": "18 meses",
        "source": "Recomendacao publica Santander",
    },
    {
        "name": "LCI Pre Santander 1 ano",
        "issuer": "Banco Santander Brasil",
        "category": "LCI",
        "indexer": "Prefixado",
        "maturity": "1 ano",
        "source": "Recomendacao publica Santander",
    },
    {
        "name": "LIG IPCA Santander 2030",
        "issuer": "Banco Santander Brasil",
        "category": "LIG",
        "indexer": "IPCA",
        "maturity": "2030",
        "source": "Recomendacao publica Santander",
    },
    {
        "name": "Santander Renda Fixa Referenciado DI Premium",
        "issuer": "Santander Asset Management",
        "category": "Fundo de renda fixa",
        "indexer": "DI/CDI",
        "maturity": "Liquidez conforme regulamento",
        "source": "Santander Asset Management",
    },
    {
        "name": "Santander Infraestrutura Inflacao 2",
        "issuer": "Santander Asset Management",
        "category": "Renda fixa infraestrutura",
        "indexer": "IPCA",
        "maturity": "Conforme regulamento",
        "source": "Recomendacao publica Santander",
    },
    {
        "name": "Caderneta de poupanca Santander",
        "issuer": "Banco Santander Brasil",
        "category": "Poupanca",
        "indexer": "TR + rendimento da poupanca",
        "maturity": "Liquidez diaria",
        "source": "Santander",
    },
]


def investment_database_url() -> str:
    if os.getenv("EKT_DISABLE_POSTGRES", "").strip().lower() in {"1", "true", "yes", "on"}:
        return ""
    return (
        os.getenv("DATABASE_EXTERNAL_URL", "").strip()
        or os.getenv("DATABASE_PUBLIC_URL", "").strip()
        or os.getenv("DATABASE_URL", "").strip()
    )


def investment_database_url_source() -> str:
    if os.getenv("EKT_DISABLE_POSTGRES", "").strip().lower() in {"1", "true", "yes", "on"}:
        return "EKT_DISABLE_POSTGRES"
    if os.getenv("DATABASE_EXTERNAL_URL", "").strip():
        return "DATABASE_EXTERNAL_URL"
    if os.getenv("DATABASE_PUBLIC_URL", "").strip():
        return "DATABASE_PUBLIC_URL"
    if os.getenv("DATABASE_URL", "").strip():
        return "DATABASE_URL"
    return ""


def investment_database_host() -> str:
    database_url = investment_database_url()
    if not database_url:
        return ""
    return urlparse(database_url).hostname or ""


def investments_credentials_configured() -> bool:
    return bool(os.getenv("INVESTMENTS_USER", "").strip()) and bool(
        os.getenv("INVESTMENTS_PASSWORD", "")
    )


def validate_investments_credentials(login: str, password: str) -> bool:
    expected_login = os.getenv("INVESTMENTS_USER", "").strip()
    expected_password = os.getenv("INVESTMENTS_PASSWORD", "")
    if not expected_login or not expected_password:
        return False
    return hmac.compare_digest(login.strip(), expected_login) and hmac.compare_digest(
        password,
        expected_password,
    )


def use_postgres_investment_db() -> bool:
    return bool(investment_database_url()) and psycopg is not None


def investment_db_connection():
    """Open a fresh, bounded connection; stale connections are never reused."""
    if psycopg is None:
        raise RuntimeError("Driver PostgreSQL indisponivel.")
    return psycopg.connect(investment_database_url(), connect_timeout=10)


def ensure_sqlite_investment_db() -> None:
    INVESTMENT_DATA_DIR.mkdir(parents=True, exist_ok=True)
    if LEGACY_INVESTMENT_DB_PATH.exists() and not INVESTMENT_DB_PATH.exists():
        LEGACY_INVESTMENT_DB_PATH.replace(INVESTMENT_DB_PATH)
    with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS investments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                product_name TEXT NOT NULL UNIQUE,
                issuer TEXT NOT NULL,
                category TEXT NOT NULL,
                indexer TEXT NOT NULL,
                maturity TEXT NOT NULL,
                source TEXT NOT NULL,
                amount_text TEXT NOT NULL DEFAULT '0,00',
                created_at TEXT NOT NULL
            )
            """
        )
        columns = {
            str(row[1])
            for row in connection.execute("PRAGMA table_info(investments)").fetchall()
        }
        if "amount_text" not in columns:
            connection.execute(
                "ALTER TABLE investments ADD COLUMN amount_text TEXT NOT NULL DEFAULT '0,00'"
            )


def ensure_postgres_investment_db() -> None:
    if not use_postgres_investment_db():
        return
    with investment_db_connection() as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS investments (
                id BIGSERIAL PRIMARY KEY,
                product_name TEXT NOT NULL UNIQUE,
                issuer TEXT NOT NULL,
                category TEXT NOT NULL,
                indexer TEXT NOT NULL,
                maturity TEXT NOT NULL,
                source TEXT NOT NULL,
                amount_text TEXT NOT NULL DEFAULT '0,00',
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
            """
        )
        connection.execute(
            "ALTER TABLE investments ADD COLUMN IF NOT EXISTS amount_text TEXT NOT NULL DEFAULT '0,00'"
        )


def ensure_investment_db() -> None:
    if use_postgres_investment_db():
        ensure_postgres_investment_db()
    else:
        ensure_sqlite_investment_db()
    drop_legacy_budget_builder_storage()


def drop_legacy_budget_builder_storage() -> None:
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            for table_name in LEGACY_BUDGET_TABLES:
                connection.execute(f"DROP TABLE IF EXISTS {table_name} CASCADE")
        return

    with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
        connection.execute("PRAGMA foreign_keys = OFF")
        for table_name in LEGACY_BUDGET_TABLES:
            connection.execute(f"DROP TABLE IF EXISTS {table_name}")
        connection.execute("PRAGMA foreign_keys = ON")


def save_investment_option(option: dict[str, str]) -> bool:
    ensure_investment_db()
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            cursor = connection.execute(
                """
                INSERT INTO investments (
                    product_name, issuer, category, indexer, maturity, source
                ) VALUES (%s, %s, %s, %s, %s, %s)
                ON CONFLICT (product_name) DO NOTHING
                """,
                (
                    option["name"],
                    option["issuer"],
                    option["category"],
                    option["indexer"],
                    option["maturity"],
                    option["source"],
                ),
            )
        return cursor.rowcount > 0

    with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
        cursor = connection.execute(
            """
            INSERT OR IGNORE INTO investments (
                product_name, issuer, category, indexer, maturity, source, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                option["name"],
                option["issuer"],
                option["category"],
                option["indexer"],
                option["maturity"],
                option["source"],
                datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds"),
            ),
        )
    return cursor.rowcount > 0


def load_saved_investments() -> list[tuple[str, str, str]]:
    ensure_investment_db()
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            rows = connection.execute(
                """
                SELECT product_name, category, created_at
                FROM investments
                ORDER BY id DESC
                """
            ).fetchall()
        return [(str(name), str(category), str(created_at)) for name, category, created_at in rows]

    with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
        rows = connection.execute(
            """
            SELECT product_name, category, created_at
            FROM investments
            ORDER BY id DESC
            """
        ).fetchall()
    return [(str(name), str(category), str(created_at)) for name, category, created_at in rows]


def delete_saved_investment(product_name: str) -> bool:
    ensure_investment_db()
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            cursor = connection.execute(
                "DELETE FROM investments WHERE product_name = %s",
                (product_name,),
            )
        return cursor.rowcount > 0

    with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
        cursor = connection.execute(
            "DELETE FROM investments WHERE product_name = ?",
            (product_name,),
        )
    return cursor.rowcount > 0


def load_saved_investment_records() -> list[dict[str, object]]:
    ensure_investment_db()
    query = """
        SELECT id, product_name, issuer, category, indexer, maturity,
               source, amount_text, created_at
        FROM investments
        ORDER BY id DESC
    """
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            rows = connection.execute(query).fetchall()
    else:
        with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
            rows = connection.execute(query).fetchall()
    return [
        {
            "id": int(item_id),
            "name": str(name),
            "issuer": str(issuer),
            "category": str(category),
            "indexer": str(indexer),
            "maturity": str(maturity),
            "source": str(source),
            "amount_text": str(amount_text or "0,00"),
            "created_at": str(created_at),
        }
        for item_id, name, issuer, category, indexer, maturity, source, amount_text, created_at in rows
    ]


def save_day_trade_investment_amount(amount_text: str) -> None:
    ensure_investment_db()
    values = (
        DAY_TRADE_INVESTMENT_NAME,
        "Conta real",
        "Day Trade",
        "Capital operacional",
        "Liquidez diaria",
        "Controle Day Trade",
        amount_text,
    )
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            connection.execute(
                """
                INSERT INTO investments (
                    product_name, issuer, category, indexer, maturity,
                    source, amount_text
                ) VALUES (%s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (product_name) DO UPDATE SET
                    issuer = EXCLUDED.issuer,
                    category = EXCLUDED.category,
                    indexer = EXCLUDED.indexer,
                    maturity = EXCLUDED.maturity,
                    source = EXCLUDED.source,
                    amount_text = EXCLUDED.amount_text
                """,
                values,
            )
        return

    with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
        connection.execute(
            """
            INSERT INTO investments (
                product_name, issuer, category, indexer, maturity,
                source, amount_text, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(product_name) DO UPDATE SET
                issuer = excluded.issuer,
                category = excluded.category,
                indexer = excluded.indexer,
                maturity = excluded.maturity,
                source = excluded.source,
                amount_text = excluded.amount_text
            """,
            (
                *values,
                datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(
                    timespec="seconds"
                ),
            ),
        )


def update_saved_investment_amount(item_id: str, amount_text: str) -> bool:
    ensure_investment_db()
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            cursor = connection.execute(
                "UPDATE investments SET amount_text = %s WHERE id = %s",
                (amount_text, int(item_id)),
            )
        return cursor.rowcount > 0
    with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
        cursor = connection.execute(
            "UPDATE investments SET amount_text = ? WHERE id = ?",
            (amount_text, int(item_id)),
        )
    return cursor.rowcount > 0


def delete_saved_investment_by_id(item_id: str) -> bool:
    ensure_investment_db()
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            cursor = connection.execute(
                "DELETE FROM investments WHERE id = %s",
                (int(item_id),),
            )
        return cursor.rowcount > 0
    with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
        cursor = connection.execute(
            "DELETE FROM investments WHERE id = ?",
            (int(item_id),),
        )
    return cursor.rowcount > 0


def ensure_monthly_budget_db() -> None:
    ensure_investment_db()
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS monthly_budget_items (
                    id BIGSERIAL PRIMARY KEY,
                    owner_key TEXT NOT NULL,
                    reference_month DATE,
                    item_type TEXT NOT NULL CHECK (item_type IN ('Receita', 'Despesa')),
                    tipo_receita TEXT,
                    tipo_receita_outros VARCHAR(80),
                    description TEXT NOT NULL,
                    observation TEXT NOT NULL DEFAULT '',
                    amount_text TEXT NOT NULL,
                    received_amount_text TEXT NOT NULL DEFAULT '0,00',
                    due_date DATE NOT NULL,
                    payment_date DATE,
                    settled BOOLEAN NOT NULL DEFAULT FALSE,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS expense_natures (
                    id BIGSERIAL PRIMARY KEY,
                    owner_key TEXT NOT NULL,
                    name VARCHAR(80) NOT NULL,
                    normalized_name VARCHAR(80) NOT NULL,
                    active BOOLEAN NOT NULL DEFAULT TRUE,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    UNIQUE (owner_key, normalized_name)
                )
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS monthly_budget_periods (
                    owner_key TEXT NOT NULL,
                    reference_month DATE NOT NULL,
                    closed BOOLEAN NOT NULL DEFAULT FALSE,
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    PRIMARY KEY (owner_key, reference_month)
                )
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS monthly_budget_period_imports (
                    owner_key TEXT NOT NULL,
                    target_month DATE NOT NULL,
                    source_month DATE NOT NULL,
                    imported_count INTEGER NOT NULL DEFAULT 0,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    PRIMARY KEY (owner_key, target_month)
                )
                """
            )
            connection.execute(
                "ALTER TABLE monthly_budget_items ADD COLUMN IF NOT EXISTS expense_nature_id BIGINT"
            )
            connection.execute(
                """
                DO $$ BEGIN
                    IF NOT EXISTS (
                        SELECT 1 FROM pg_constraint
                        WHERE conname = 'monthly_budget_items_expense_nature_fk'
                    ) THEN
                        ALTER TABLE monthly_budget_items
                        ADD CONSTRAINT monthly_budget_items_expense_nature_fk
                        FOREIGN KEY (expense_nature_id) REFERENCES expense_natures(id)
                        ON DELETE RESTRICT NOT VALID;
                    END IF;
                END $$
                """
            )
            connection.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_monthly_budget_expense_nature
                ON monthly_budget_items (owner_key, expense_nature_id)
                """
            )
            connection.execute(
                "ALTER TABLE monthly_budget_items ADD COLUMN IF NOT EXISTS payment_date DATE"
            )
            connection.execute(
                "ALTER TABLE monthly_budget_items ADD COLUMN IF NOT EXISTS observation TEXT NOT NULL DEFAULT ''"
            )
            connection.execute(
                "ALTER TABLE monthly_budget_items ADD COLUMN IF NOT EXISTS received_amount_text TEXT NOT NULL DEFAULT '0,00'"
            )
            connection.execute(
                "ALTER TABLE monthly_budget_items ADD COLUMN IF NOT EXISTS tipo_receita TEXT"
            )
            connection.execute(
                "ALTER TABLE monthly_budget_items ADD COLUMN IF NOT EXISTS tipo_receita_outros VARCHAR(80)"
            )
            connection.execute(
                "ALTER TABLE monthly_budget_items ALTER COLUMN reference_month DROP NOT NULL"
            )
            connection.execute(
                """
                UPDATE monthly_budget_items
                SET received_amount_text = amount_text
                WHERE item_type = 'Receita' AND settled = TRUE
                  AND received_amount_text IN ('', '0', '0,00', '0.00')
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS caixa (
                    id BIGSERIAL PRIMARY KEY,
                    owner_key TEXT NOT NULL,
                    source_budget_item_id BIGINT NOT NULL,
                    reference_month DATE NOT NULL,
                    item_type TEXT NOT NULL,
                    description TEXT NOT NULL,
                    observation TEXT NOT NULL DEFAULT '',
                    amount_text TEXT NOT NULL,
                    due_date DATE NOT NULL,
                    payment_date DATE NOT NULL,
                    settled BOOLEAN NOT NULL,
                    source_created_at TIMESTAMPTZ,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    UNIQUE (owner_key, source_budget_item_id)
                )
                """
            )
            connection.execute(
                "ALTER TABLE caixa ADD COLUMN IF NOT EXISTS observation TEXT NOT NULL DEFAULT ''"
            )
            connection.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_monthly_budget_owner_month
                ON monthly_budget_items (owner_key, reference_month)
                """
            )
            connection.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_monthly_budget_owner_due_date
                ON monthly_budget_items (owner_key, due_date)
                """
            )
            connection.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_monthly_budget_owner_payment_date
                ON monthly_budget_items (owner_key, payment_date)
                WHERE payment_date IS NOT NULL
                """
            )
            connection.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_monthly_budget_expense_descriptions
                ON monthly_budget_items (owner_key, item_type, created_at DESC)
                """
            )
            connection.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_caixa_owner_payment
                ON caixa (owner_key, payment_date)
                """
            )
            connection.execute(
                """
                INSERT INTO caixa (
                    owner_key, source_budget_item_id, reference_month, item_type,
                    description, observation, amount_text, due_date, payment_date, settled,
                    source_created_at
                )
                SELECT owner_key, id, reference_month, item_type, description,
                       observation, received_amount_text, due_date, COALESCE(payment_date, CURRENT_DATE),
                       settled, created_at
                FROM monthly_budget_items
                WHERE item_type = 'Receita'
                  AND received_amount_text NOT IN ('', '0', '0,00', '0.00')
                ON CONFLICT (owner_key, source_budget_item_id) DO UPDATE SET
                    description = EXCLUDED.description,
                    observation = EXCLUDED.observation,
                    amount_text = EXCLUDED.amount_text,
                    payment_date = EXCLUDED.payment_date,
                    settled = EXCLUDED.settled,
                    updated_at = NOW()
                """
            )
        return

    with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS monthly_budget_items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                owner_key TEXT NOT NULL,
                reference_month TEXT,
                item_type TEXT NOT NULL CHECK (item_type IN ('Receita', 'Despesa')),
                tipo_receita TEXT,
                tipo_receita_outros TEXT,
                description TEXT NOT NULL,
                observation TEXT NOT NULL DEFAULT '',
                amount_text TEXT NOT NULL,
                received_amount_text TEXT NOT NULL DEFAULT '0,00',
                due_date TEXT NOT NULL,
                payment_date TEXT,
                settled INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS expense_natures (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                owner_key TEXT NOT NULL,
                name TEXT NOT NULL,
                normalized_name TEXT NOT NULL,
                active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE (owner_key, normalized_name)
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS monthly_budget_periods (
                owner_key TEXT NOT NULL,
                reference_month TEXT NOT NULL,
                closed INTEGER NOT NULL DEFAULT 0,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (owner_key, reference_month)
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS monthly_budget_period_imports (
                owner_key TEXT NOT NULL,
                target_month TEXT NOT NULL,
                source_month TEXT NOT NULL,
                imported_count INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                PRIMARY KEY (owner_key, target_month)
            )
            """
        )
        columns = {
            str(row[1])
            for row in connection.execute("PRAGMA table_info(monthly_budget_items)").fetchall()
        }
        if "payment_date" not in columns:
            connection.execute("ALTER TABLE monthly_budget_items ADD COLUMN payment_date TEXT")
        if "observation" not in columns:
            connection.execute(
                "ALTER TABLE monthly_budget_items ADD COLUMN observation TEXT NOT NULL DEFAULT ''"
            )
        if "received_amount_text" not in columns:
            connection.execute(
                "ALTER TABLE monthly_budget_items ADD COLUMN received_amount_text TEXT NOT NULL DEFAULT '0,00'"
            )
        if "tipo_receita" not in columns:
            connection.execute(
                "ALTER TABLE monthly_budget_items ADD COLUMN tipo_receita TEXT"
            )
        if "tipo_receita_outros" not in columns:
            connection.execute(
                "ALTER TABLE monthly_budget_items ADD COLUMN tipo_receita_outros TEXT"
            )
        if "expense_nature_id" not in columns:
            connection.execute(
                "ALTER TABLE monthly_budget_items ADD COLUMN expense_nature_id INTEGER"
            )
        connection.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_monthly_budget_expense_nature
            ON monthly_budget_items (owner_key, expense_nature_id)
            """
        )
        connection.execute(
            """
            UPDATE monthly_budget_items
            SET received_amount_text = amount_text
            WHERE item_type = 'Receita' AND settled = 1
              AND received_amount_text IN ('', '0', '0,00', '0.00')
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS caixa (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                owner_key TEXT NOT NULL,
                source_budget_item_id INTEGER NOT NULL,
                reference_month TEXT NOT NULL,
                item_type TEXT NOT NULL,
                description TEXT NOT NULL,
                observation TEXT NOT NULL DEFAULT '',
                amount_text TEXT NOT NULL,
                due_date TEXT NOT NULL,
                payment_date TEXT NOT NULL,
                settled INTEGER NOT NULL,
                source_created_at TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE (owner_key, source_budget_item_id)
            )
            """
        )
        caixa_columns = {
            str(row[1]) for row in connection.execute("PRAGMA table_info(caixa)").fetchall()
        }
        if "observation" not in caixa_columns:
            connection.execute(
                "ALTER TABLE caixa ADD COLUMN observation TEXT NOT NULL DEFAULT ''"
            )
        connection.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_monthly_budget_owner_month
            ON monthly_budget_items (owner_key, reference_month)
            """
        )
        connection.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_monthly_budget_owner_due_date
            ON monthly_budget_items (owner_key, due_date)
            """
        )
        connection.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_monthly_budget_owner_payment_date
            ON monthly_budget_items (owner_key, payment_date)
            WHERE payment_date IS NOT NULL AND payment_date <> ''
            """
        )
        connection.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_monthly_budget_expense_descriptions
            ON monthly_budget_items (owner_key, item_type, created_at DESC)
            """
        )
        connection.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_caixa_owner_payment
            ON caixa (owner_key, payment_date)
            """
        )
        now = datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds")
        connection.execute(
            """
            INSERT INTO caixa (
                owner_key, source_budget_item_id, reference_month, item_type,
                description, observation, amount_text, due_date, payment_date, settled,
                source_created_at, created_at, updated_at
            )
            SELECT owner_key, id, reference_month, item_type, description,
                   observation, received_amount_text, due_date,
                   COALESCE(NULLIF(payment_date, ''), date('now')),
                   settled, created_at, ?, ?
            FROM monthly_budget_items
            WHERE item_type = 'Receita'
              AND received_amount_text NOT IN ('', '0', '0,00', '0.00')
            ON CONFLICT(owner_key, source_budget_item_id) DO UPDATE SET
                description = excluded.description,
                observation = excluded.observation,
                amount_text = excluded.amount_text,
                payment_date = excluded.payment_date,
                settled = excluded.settled,
                updated_at = excluded.updated_at
            """,
            (now, now),
        )


def _sync_postgres_cash_entry(connection, item_id: int, owner_key: str) -> None:
    row = connection.execute(
        """
        SELECT owner_key, id, reference_month, item_type, description,
               observation, amount_text, received_amount_text, due_date,
               payment_date, settled, created_at
        FROM monthly_budget_items
        WHERE id = %s AND owner_key = %s
        """,
        (item_id, owner_key),
    ).fetchone()
    received_positive = bool(
        row
        and str(row[7] or "").strip() not in {"", "0", "0,00", "0.00"}
    )
    if row and row[3] == "Receita" and received_positive:
        connection.execute(
            """
            INSERT INTO caixa (
                owner_key, source_budget_item_id, reference_month, item_type,
                description, observation, amount_text, due_date, payment_date, settled,
                source_created_at
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, COALESCE(%s, CURRENT_DATE), %s, %s)
            ON CONFLICT (owner_key, source_budget_item_id) DO UPDATE SET
                reference_month = EXCLUDED.reference_month,
                item_type = EXCLUDED.item_type,
                description = EXCLUDED.description,
                observation = EXCLUDED.observation,
                amount_text = EXCLUDED.amount_text,
                due_date = EXCLUDED.due_date,
                payment_date = EXCLUDED.payment_date,
                settled = EXCLUDED.settled,
                source_created_at = EXCLUDED.source_created_at,
                updated_at = NOW()
            """,
            (
                row[0], row[1], row[2], row[3], row[4], row[5], row[7],
                row[8], row[9], row[10], row[11],
            ),
        )
    else:
        connection.execute(
            "DELETE FROM caixa WHERE source_budget_item_id = %s AND owner_key = %s",
            (item_id, owner_key),
        )


def _sync_sqlite_cash_entry(connection, item_id: int, owner_key: str) -> None:
    row = connection.execute(
        """
        SELECT owner_key, id, reference_month, item_type, description,
               observation, amount_text, received_amount_text, due_date,
               payment_date, settled, created_at
        FROM monthly_budget_items
        WHERE id = ? AND owner_key = ?
        """,
        (item_id, owner_key),
    ).fetchone()
    received_positive = bool(
        row
        and str(row[7] or "").strip() not in {"", "0", "0,00", "0.00"}
    )
    if row and row[3] == "Receita" and received_positive:
        now = datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds")
        values = (
            row[0], row[1], row[2], row[3], row[4], row[5], row[7], row[8],
            row[9] or datetime.now(ZoneInfo("America/Sao_Paulo")).strftime("%Y-%m-%d"),
            row[10], row[11], now, now,
        )
        connection.execute(
            """
            INSERT INTO caixa (
                owner_key, source_budget_item_id, reference_month, item_type,
                description, observation, amount_text, due_date, payment_date, settled,
                source_created_at, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(owner_key, source_budget_item_id) DO UPDATE SET
                reference_month = excluded.reference_month,
                item_type = excluded.item_type,
                description = excluded.description,
                observation = excluded.observation,
                amount_text = excluded.amount_text,
                due_date = excluded.due_date,
                payment_date = excluded.payment_date,
                settled = excluded.settled,
                source_created_at = excluded.source_created_at,
                updated_at = excluded.updated_at
            """,
            values,
        )
    else:
        connection.execute(
            "DELETE FROM caixa WHERE source_budget_item_id = ? AND owner_key = ?",
            (item_id, owner_key),
        )


def prepare_budget_storage_after_login() -> None:
    ensure_monthly_budget_db()


def normalize_expense_nature_name(value: object) -> tuple[str, str]:
    name = " ".join(str(value or "").strip().split())
    if not name:
        raise ValueError("Informe o nome da natureza.")
    if len(name) > 80:
        raise ValueError("O nome da natureza deve possuir no máximo 80 caracteres.")
    normalized = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode().casefold()
    return name, normalized


def list_expense_natures(owner_key: str = DEFAULT_BUDGET_OWNER_KEY) -> list[dict[str, object]]:
    ensure_monthly_budget_db()
    query = """
        SELECT n.id, n.name, n.active, n.created_at, n.updated_at,
               COUNT(i.id) AS usage_count
        FROM expense_natures n
        LEFT JOIN monthly_budget_items i
          ON i.owner_key = n.owner_key AND i.expense_nature_id = n.id
        WHERE n.owner_key = {placeholder}
        GROUP BY n.id, n.name, n.active, n.created_at, n.updated_at
        ORDER BY n.active DESC, n.name
    """
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            rows = connection.execute(query.format(placeholder="%s"), (owner_key,)).fetchall()
    else:
        with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
            rows = connection.execute(query.format(placeholder="?"), (owner_key,)).fetchall()
    return [{"id": int(row[0]), "name": str(row[1]), "active": bool(row[2]),
             "created_at": str(row[3]), "updated_at": str(row[4]),
             "usage_count": int(row[5])} for row in rows]


def save_expense_nature(name: object, owner_key: str = DEFAULT_BUDGET_OWNER_KEY) -> int:
    ensure_monthly_budget_db()
    display, normalized = normalize_expense_nature_name(name)
    now = datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds")
    try:
        if use_postgres_investment_db():
            with investment_db_connection() as connection:
                row = connection.execute(
                    "INSERT INTO expense_natures (owner_key,name,normalized_name) VALUES (%s,%s,%s) RETURNING id",
                    (owner_key, display, normalized)).fetchone()
            return int(row[0])
        with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
            cursor = connection.execute(
                "INSERT INTO expense_natures (owner_key,name,normalized_name,created_at,updated_at) VALUES (?,?,?,?,?)",
                (owner_key, display, normalized, now, now))
            return int(cursor.lastrowid)
    except Exception as exc:
        if "unique" in str(exc).lower() or "duplicate" in str(exc).lower():
            raise ValueError("Já existe uma natureza com esse nome.") from exc
        raise


def update_expense_nature(nature_id: int, *, name: object | None = None,
                          active: bool | None = None,
                          owner_key: str = DEFAULT_BUDGET_OWNER_KEY) -> bool:
    ensure_monthly_budget_db()
    existing = next((n for n in list_expense_natures(owner_key) if n["id"] == int(nature_id)), None)
    if existing is None:
        return False
    display, normalized = normalize_expense_nature_name(name if name is not None else existing["name"])
    enabled = bool(existing["active"] if active is None else active)
    now = datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds")
    try:
        if use_postgres_investment_db():
            with investment_db_connection() as connection:
                cursor = connection.execute(
                    "UPDATE expense_natures SET name=%s, normalized_name=%s, active=%s, updated_at=NOW() WHERE id=%s AND owner_key=%s",
                    (display, normalized, enabled, int(nature_id), owner_key))
        else:
            with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
                cursor = connection.execute(
                    "UPDATE expense_natures SET name=?, normalized_name=?, active=?, updated_at=? WHERE id=? AND owner_key=?",
                    (display, normalized, 1 if enabled else 0, now, int(nature_id), owner_key))
        return cursor.rowcount > 0
    except Exception as exc:
        if "unique" in str(exc).lower() or "duplicate" in str(exc).lower():
            raise ValueError("Já existe uma natureza com esse nome.") from exc
        raise


def delete_expense_nature(nature_id: int, owner_key: str = DEFAULT_BUDGET_OWNER_KEY) -> bool:
    ensure_monthly_budget_db()
    placeholder = "%s" if use_postgres_investment_db() else "?"
    manager = investment_db_connection() if use_postgres_investment_db() else sqlite3.connect(INVESTMENT_DB_PATH)
    with manager as connection:
        used = connection.execute(
            f"SELECT COUNT(*) FROM monthly_budget_items WHERE owner_key={placeholder} AND expense_nature_id={placeholder}",
            (owner_key, int(nature_id))).fetchone()[0]
        if used:
            raise ValueError("Esta natureza está vinculada a despesas e não pode ser excluída diretamente.")
        cursor = connection.execute(
            f"DELETE FROM expense_natures WHERE id={placeholder} AND owner_key={placeholder}",
            (int(nature_id), owner_key))
    return cursor.rowcount > 0


def categorize_expenses(item_ids: list[int], nature_id: int,
                        owner_key: str = DEFAULT_BUDGET_OWNER_KEY) -> int:
    ensure_monthly_budget_db()
    unique_ids = sorted({int(value) for value in item_ids})
    if not unique_ids:
        raise ValueError("Selecione ao menos uma despesa.")
    nature = next((n for n in list_expense_natures(owner_key)
                   if n["id"] == int(nature_id) and n["active"]), None)
    if nature is None:
        raise ValueError("Selecione uma natureza ativa.")
    postgres = use_postgres_investment_db()
    placeholder = "%s" if postgres else "?"
    placeholders = ",".join([placeholder] * len(unique_ids))
    manager = investment_db_connection() if postgres else sqlite3.connect(INVESTMENT_DB_PATH)
    with manager as connection:
        cursor = connection.execute(
            f"UPDATE monthly_budget_items SET expense_nature_id={placeholder} WHERE owner_key={placeholder} AND item_type='Despesa' AND id IN ({placeholders})",
            (int(nature_id), owner_key, *unique_ids))
    return int(cursor.rowcount)


def save_monthly_budget_item(
    reference_month: str,
    item_type: str,
    description: str,
    amount_text: str,
    due_date: str,
    payment_date: str | None,
    settled: bool,
    observation: str = "",
    received_amount_text: str = "0,00",
    owner_key: str = DEFAULT_BUDGET_OWNER_KEY,
    tipo_receita: str | None = None,
    tipo_receita_outros: str | None = None,
    expense_nature_id: int | None = None,
) -> int:
    ensure_monthly_budget_db()
    if item_type == "Receita" and settled and received_amount_text in {"", "0", "0,00", "0.00"}:
        received_amount_text = amount_text
    if item_type != "Receita":
        received_amount_text = "0,00"
        tipo_receita = None
        tipo_receita_outros = None
    else:
        expense_nature_id = None
        if tipo_receita != "OUTROS":
            tipo_receita_outros = None
    month_date = f"{reference_month}-01"
    now = datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds")
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            row = connection.execute(
                """
                INSERT INTO monthly_budget_items (
                    owner_key, reference_month, item_type, tipo_receita,
                    tipo_receita_outros, expense_nature_id, description, observation,
                    amount_text, received_amount_text, due_date, payment_date, settled
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                RETURNING id
                """,
                (
                    owner_key, month_date, item_type, tipo_receita,
                    tipo_receita_outros, expense_nature_id, description, observation, amount_text,
                    received_amount_text, due_date, payment_date, bool(settled),
                ),
            ).fetchone()
            _sync_postgres_cash_entry(connection, int(row[0]), owner_key)
        return int(row[0])

    with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
        cursor = connection.execute(
            """
            INSERT INTO monthly_budget_items (
                owner_key, reference_month, item_type, tipo_receita,
                tipo_receita_outros, expense_nature_id, description, observation,
                amount_text, received_amount_text, due_date, payment_date, settled, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                owner_key, month_date, item_type, tipo_receita,
                tipo_receita_outros, expense_nature_id, description, observation, amount_text,
                received_amount_text, due_date, payment_date,
                1 if settled else 0, now,
            ),
        )
        _sync_sqlite_cash_entry(connection, int(cursor.lastrowid), owner_key)
    return int(cursor.lastrowid)


def load_monthly_budget_items(
    reference_month: str | None = None,
    owner_key: str = DEFAULT_BUDGET_OWNER_KEY,
) -> list[dict[str, object]]:
    ensure_monthly_budget_db()
    month_date = f"{reference_month}-01" if reference_month else None
    query = """
        SELECT i.id, reference_month, item_type, tipo_receita, tipo_receita_outros,
               i.expense_nature_id, n.name, n.active, description, observation, amount_text,
               received_amount_text, due_date, payment_date, settled, i.created_at
        FROM monthly_budget_items i
        LEFT JOIN expense_natures n ON n.id=i.expense_nature_id AND n.owner_key=i.owner_key
        WHERE i.owner_key = {owner_placeholder}
        {month_filter}
        ORDER BY reference_month NULLS FIRST, item_type DESC, due_date, i.id
    """
    month_filter = (
        "AND reference_month = {month_placeholder}" if month_date else ""
    )
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            rows = connection.execute(
                query.format(
                    owner_placeholder="%s",
                    month_placeholder="%s",
                    month_filter=month_filter.format(month_placeholder="%s"),
                ),
                (owner_key, month_date) if month_date else (owner_key,),
            ).fetchall()
    else:
        with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
            rows = connection.execute(
                query.replace(" NULLS FIRST", "").format(
                    owner_placeholder="?",
                    month_placeholder="?",
                    month_filter=month_filter.format(month_placeholder="?"),
                ),
                (owner_key, month_date) if month_date else (owner_key,),
            ).fetchall()
    return [
        {
            "id": int(item_id),
            "reference_month": str(stored_reference_month)[:7]
            if stored_reference_month
            else "",
            "item_type": str(item_type),
            "tipo_receita": str(tipo_receita) if tipo_receita else None,
            "tipo_receita_outros": (
                str(tipo_receita_outros) if tipo_receita_outros else None
            ),
            "expense_nature_id": int(expense_nature_id) if expense_nature_id else None,
            "expense_nature_name": str(expense_nature_name) if expense_nature_name else None,
            "expense_nature_active": bool(expense_nature_active) if expense_nature_id else None,
            "description": str(description),
            "observation": str(observation or ""),
            "amount_text": str(amount_text),
            "received_amount_text": str(received_amount_text or "0,00"),
            "due_date": str(due_date)[:10],
            "payment_date": str(payment_date)[:10] if payment_date else "",
            "settled": bool(settled),
            "created_at": str(created_at),
        }
        for (
            item_id, stored_reference_month, item_type, tipo_receita,
            tipo_receita_outros, expense_nature_id, expense_nature_name,
            expense_nature_active, description,
            observation, amount_text, received_amount_text, due_date,
            payment_date, settled, created_at,
        ) in rows
    ]


def list_budget_expense_descriptions(
    owner_key: str = DEFAULT_BUDGET_OWNER_KEY,
    limit: int = 250,
) -> list[str]:
    """Return unique expense descriptions from all periods, newest first."""
    ensure_monthly_budget_db()
    query = """
        SELECT TRIM(description) AS clean_description,
               MAX(created_at) AS last_used,
               COUNT(*) AS use_count
        FROM monthly_budget_items
        WHERE owner_key = {owner_placeholder}
          AND item_type = 'Despesa'
          AND TRIM(COALESCE(description, '')) <> ''
        GROUP BY TRIM(description)
        ORDER BY last_used DESC, use_count DESC, clean_description
        LIMIT {limit_placeholder}
    """
    safe_limit = max(10, min(int(limit), 500))
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            rows = connection.execute(
                query.format(owner_placeholder="%s", limit_placeholder="%s"),
                (owner_key, safe_limit),
            ).fetchall()
    else:
        with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
            rows = connection.execute(
                query.format(owner_placeholder="?", limit_placeholder="?"),
                (owner_key, safe_limit),
            ).fetchall()
    unique: list[str] = []
    seen: set[str] = set()
    for row in rows:
        description = str(row[0]).strip()
        normalized = "".join(
            character
            for character in unicodedata.normalize("NFD", description.casefold())
            if unicodedata.category(character) != "Mn"
        )
        if not description or normalized in seen:
            continue
        seen.add(normalized)
        unique.append(description)
        if len(unique) >= safe_limit:
            break
    return unique


def load_yearly_budget_items(
    year: int,
    owner_key: str = DEFAULT_BUDGET_OWNER_KEY,
) -> list[dict[str, object]]:
    """Retorna todos os lan�amentos de um ano para o m�dulo de BI."""
    ensure_monthly_budget_db()
    start_date = f"{int(year):04d}-01-01"
    end_date = f"{int(year) + 1:04d}-01-01"
    query = """
        SELECT id, reference_month, item_type, tipo_receita,
               tipo_receita_outros, description, observation,
               amount_text, received_amount_text, due_date, payment_date, settled, created_at
        FROM monthly_budget_items
        WHERE owner_key = {owner_placeholder}
          AND reference_month >= {start_placeholder}
          AND reference_month < {end_placeholder}
        ORDER BY reference_month, item_type DESC, due_date, id
    """
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            rows = connection.execute(
                query.format(
                    owner_placeholder="%s",
                    start_placeholder="%s",
                    end_placeholder="%s",
                ),
                (owner_key, start_date, end_date),
            ).fetchall()
    else:
        with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
            rows = connection.execute(
                query.format(
                    owner_placeholder="?",
                    start_placeholder="?",
                    end_placeholder="?",
                ),
                (owner_key, start_date, end_date),
            ).fetchall()
    return [
        {
            "id": int(row[0]),
            "reference_month": str(row[1])[:7],
            "item_type": str(row[2]),
            "tipo_receita": str(row[3]) if row[3] else None,
            "tipo_receita_outros": str(row[4]) if row[4] else None,
            "description": str(row[5]),
            "observation": str(row[6] or ""),
            "amount_text": str(row[7]),
            "received_amount_text": str(row[8] or "0,00"),
            "due_date": str(row[9])[:10],
            "payment_date": str(row[10])[:10] if row[10] else "",
            "settled": bool(row[11]),
            "created_at": str(row[12]),
        }
        for row in rows
    ]


def list_monthly_budget_months(
    owner_key: str = DEFAULT_BUDGET_OWNER_KEY,
) -> list[str]:
    ensure_monthly_budget_db()
    query = """
        SELECT DISTINCT reference_month
        FROM monthly_budget_items
        WHERE owner_key = {owner_placeholder}
        ORDER BY reference_month
    """
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            rows = connection.execute(
                query.format(owner_placeholder="%s"),
                (owner_key,),
            ).fetchall()
    else:
        with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
            rows = connection.execute(
                query.format(owner_placeholder="?"),
                (owner_key,),
            ).fetchall()
    months = []
    for (reference_month,) in rows:
        if not reference_month:
            continue
        month_text = str(reference_month)[:7]
        if month_text:
            months.append(month_text)
    return months


def list_monthly_budget_period_statuses(
    owner_key: str = DEFAULT_BUDGET_OWNER_KEY,
) -> dict[str, str]:
    """Retorna os rótulos persistidos; meses sem registro ficam em andamento."""
    ensure_monthly_budget_db()
    query = """
        SELECT reference_month, closed
        FROM monthly_budget_periods
        WHERE owner_key = {owner_placeholder}
        ORDER BY reference_month
    """
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            rows = connection.execute(
                query.format(owner_placeholder="%s"), (owner_key,)
            ).fetchall()
    else:
        with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
            rows = connection.execute(
                query.format(owner_placeholder="?"), (owner_key,)
            ).fetchall()
    return {
        str(reference_month)[:7]: "closed" if bool(closed) else "open"
        for reference_month, closed in rows
    }


def monthly_budget_period_status(
    reference_month: str,
    owner_key: str = DEFAULT_BUDGET_OWNER_KEY,
) -> str:
    return list_monthly_budget_period_statuses(owner_key).get(reference_month, "open")


def set_monthly_budget_period_status(
    reference_month: str,
    status: str,
    owner_key: str = DEFAULT_BUDGET_OWNER_KEY,
) -> bool:
    if not re.fullmatch(r"\d{4}-(0[1-9]|1[0-2])", reference_month):
        raise ValueError("Mês de referência inválido.")
    if status not in {"open", "closed"}:
        raise ValueError("Status mensal inválido.")
    ensure_monthly_budget_db()
    closed = status == "closed"
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            connection.execute(
                """
                INSERT INTO monthly_budget_periods (
                    owner_key, reference_month, closed, updated_at
                ) VALUES (%s, %s, %s, NOW())
                ON CONFLICT (owner_key, reference_month) DO UPDATE SET
                    closed = EXCLUDED.closed,
                    updated_at = NOW()
                """,
                (owner_key, f"{reference_month}-01", closed),
            )
        return True
    now = datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds")
    with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
        connection.execute(
            """
            INSERT INTO monthly_budget_periods (
                owner_key, reference_month, closed, updated_at
            ) VALUES (?, ?, ?, ?)
            ON CONFLICT(owner_key, reference_month) DO UPDATE SET
                closed = excluded.closed,
                updated_at = excluded.updated_at
            """,
            (owner_key, reference_month, int(closed), now),
        )
    return True


def monthly_budget_period_allows_import(
    reference_month: str,
    owner_key: str = DEFAULT_BUDGET_OWNER_KEY,
) -> bool:
    """Regra única para futuras importações: somente mês encerrado é elegível."""
    return monthly_budget_period_status(reference_month, owner_key) == "closed"


def list_monthly_budget_period_imports(
    owner_key: str = DEFAULT_BUDGET_OWNER_KEY,
) -> dict[str, dict[str, object]]:
    """Retorna o histórico que identifica, de forma permanente, meses importados."""
    ensure_monthly_budget_db()
    query = """
        SELECT target_month, source_month, imported_count, created_at
        FROM monthly_budget_period_imports
        WHERE owner_key = {owner_placeholder}
        ORDER BY target_month
    """
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            rows = connection.execute(
                query.format(owner_placeholder="%s"), (owner_key,)
            ).fetchall()
    else:
        with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
            rows = connection.execute(
                query.format(owner_placeholder="?"), (owner_key,)
            ).fetchall()
    return {
        str(target_month)[:7]: {
            "target_month": str(target_month)[:7],
            "source_month": str(source_month)[:7],
            "imported_count": int(imported_count or 0),
            "created_at": str(created_at or ""),
        }
        for target_month, source_month, imported_count, created_at in rows
    }


def previous_reference_month(reference_month: str) -> str:
    if not re.fullmatch(r"\d{4}-(0[1-9]|1[0-2])", reference_month):
        raise ValueError("Mês de referência inválido.")
    year, month = (int(part) for part in reference_month.split("-"))
    if month == 1:
        return f"{year - 1}-12"
    return f"{year}-{month - 1:02d}"


def _move_budget_date_to_month(value: object, target_month: str) -> str:
    source_text = str(value or "")[:10]
    try:
        day = int(source_text.split("-")[2])
        year, month = (int(part) for part in target_month.split("-"))
    except (IndexError, ValueError) as exc:
        raise ValueError("Data de vencimento inválida para importação.") from exc
    day = min(day, calendar.monthrange(year, month)[1])
    return f"{target_month}-{day:02d}"


def _budget_amount_as_float(value: object) -> float:
    cleaned = str(value or "0").strip().replace("R$", "").replace(" ", "")
    if "," in cleaned:
        cleaned = cleaned.replace(".", "").replace(",", ".")
    try:
        return float(cleaned or "0")
    except ValueError:
        return 0.0


def _format_budget_amount(value: float) -> str:
    formatted = f"{value:,.2f}"
    return "R$ " + formatted.replace(",", "X").replace(".", ",").replace("X", ".")


def preview_previous_month_budget_import(
    target_month: str,
    owner_key: str = DEFAULT_BUDGET_OWNER_KEY,
) -> dict[str, object]:
    """Monta a revisão de segurança sem alterar qualquer lançamento."""
    source_month = previous_reference_month(target_month)
    source_items = [
        item
        for item in load_monthly_budget_items(source_month, owner_key)
        if item["item_type"] == "Despesa"
    ]
    history = list_monthly_budget_period_imports(owner_key).get(target_month)
    return {
        "source_month": source_month,
        "target_month": target_month,
        "expense_count": len(source_items),
        "total_amount": round(
            sum(_budget_amount_as_float(item.get("amount_text")) for item in source_items),
            2,
        ),
        "total_amount_text": _format_budget_amount(
            sum(_budget_amount_as_float(item.get("amount_text")) for item in source_items)
        ),
        "source_status": monthly_budget_period_status(source_month, owner_key),
        "target_status": monthly_budget_period_status(target_month, owner_key),
        "already_imported": history is not None,
        "import_metadata": history,
    }


def import_previous_month_budget_expenses(
    target_month: str,
    owner_key: str = DEFAULT_BUDGET_OWNER_KEY,
) -> dict[str, object]:
    """Copia despesas do mês anterior como pendentes, uma única vez por destino."""
    source_month = previous_reference_month(target_month)
    if target_month in list_monthly_budget_period_imports(owner_key):
        raise PermissionError("Acesso negado: esse mês já teve uma importação.")
    if monthly_budget_period_status(target_month, owner_key) == "closed":
        raise ValueError("Reabra o mês de destino antes de importar despesas.")
    if not monthly_budget_period_allows_import(source_month, owner_key):
        raise ValueError("O mês anterior precisa estar encerrado para importar.")
    ensure_monthly_budget_db()
    source_items = [
        item
        for item in load_monthly_budget_items(source_month, owner_key)
        if item["item_type"] == "Despesa"
    ]
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            existing = connection.execute(
                """
                SELECT imported_count FROM monthly_budget_period_imports
                WHERE owner_key = %s AND target_month = %s
                """,
                (owner_key, f"{target_month}-01"),
            ).fetchone()
            if existing:
                raise PermissionError(
                    "Acesso negado: esse mês já teve uma importação."
                )
            for item in source_items:
                connection.execute(
                    """
                    INSERT INTO monthly_budget_items (
                        owner_key, reference_month, item_type, tipo_receita,
                        tipo_receita_outros, description, observation,
                        amount_text, received_amount_text, due_date, payment_date,
                        settled, expense_nature_id
                    ) VALUES (%s, %s, 'Despesa', NULL, NULL, %s, %s, %s,
                              '0,00', %s, NULL, FALSE, %s)
                    """,
                    (
                        owner_key, f"{target_month}-01", item["description"],
                        item.get("observation") or "", item["amount_text"],
                        _move_budget_date_to_month(item["due_date"], target_month),
                        item.get("expense_nature_id"),
                    ),
                )
            connection.execute(
                """
                INSERT INTO monthly_budget_period_imports (
                    owner_key, target_month, source_month, imported_count
                ) VALUES (%s, %s, %s, %s)
                """,
                (owner_key, f"{target_month}-01", f"{source_month}-01", len(source_items)),
            )
    else:
        now = datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds")
        with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
            existing = connection.execute(
                """
                SELECT imported_count FROM monthly_budget_period_imports
                WHERE owner_key = ? AND target_month = ?
                """,
                (owner_key, target_month),
            ).fetchone()
            if existing:
                raise PermissionError(
                    "Acesso negado: esse mês já teve uma importação."
                )
            for item in source_items:
                connection.execute(
                    """
                    INSERT INTO monthly_budget_items (
                        owner_key, reference_month, item_type, tipo_receita,
                        tipo_receita_outros, description, observation,
                        amount_text, received_amount_text, due_date, payment_date,
                        settled, expense_nature_id, created_at
                    ) VALUES (?, ?, 'Despesa', NULL, NULL, ?, ?, ?, '0,00', ?,
                              NULL, 0, ?, ?)
                    """,
                    (
                        owner_key, f"{target_month}-01", item["description"],
                        item.get("observation") or "", item["amount_text"],
                        _move_budget_date_to_month(item["due_date"], target_month),
                        item.get("expense_nature_id"), now,
                    ),
                )
            connection.execute(
                """
                INSERT INTO monthly_budget_period_imports (
                    owner_key, target_month, source_month, imported_count, created_at
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (owner_key, target_month, source_month, len(source_items), now),
            )
    return {
        "source_month": source_month, "target_month": target_month,
        "imported_count": len(source_items), "already_imported": False,
    }


def load_caixa_entries(
    owner_key: str = DEFAULT_BUDGET_OWNER_KEY,
) -> list[dict[str, object]]:
    """Retorna as receitas efetivamente recebidas, prontas para o modulo Caixa."""
    ensure_monthly_budget_db()
    query = """
        SELECT id, source_budget_item_id, reference_month, item_type,
               description, observation, amount_text, due_date, payment_date, settled,
               source_created_at, created_at, updated_at
        FROM caixa
        WHERE owner_key = {owner_placeholder}
        ORDER BY payment_date DESC, id DESC
    """
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            rows = connection.execute(
                query.format(owner_placeholder="%s"),
                (owner_key,),
            ).fetchall()
    else:
        with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
            rows = connection.execute(
                query.format(owner_placeholder="?"),
                (owner_key,),
            ).fetchall()
    return [
        {
            "id": int(row[0]),
            "source_budget_item_id": int(row[1]),
            "reference_month": str(row[2])[:7],
            "item_type": str(row[3]),
            "description": str(row[4]),
            "observation": str(row[5] or ""),
            "amount_text": str(row[6]),
            "due_date": str(row[7])[:10],
            "payment_date": str(row[8])[:10],
            "settled": bool(row[9]),
            "source_created_at": str(row[10]) if row[10] else "",
            "created_at": str(row[11]),
            "updated_at": str(row[12]),
        }
        for row in rows
    ]


def update_monthly_budget_item_status(
    item_id: str,
    settled: bool,
    owner_key: str = DEFAULT_BUDGET_OWNER_KEY,
) -> bool:
    ensure_monthly_budget_db()
    today = datetime.now(ZoneInfo("America/Sao_Paulo")).strftime("%Y-%m-%d")
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            cursor = connection.execute(
                """
                UPDATE monthly_budget_items
                SET settled = %s,
                    received_amount_text = CASE
                        WHEN item_type <> 'Receita' THEN '0,00'
                        WHEN %s THEN amount_text
                        ELSE '0,00'
                    END,
                    payment_date = CASE
                        WHEN NOT %s THEN NULL
                        WHEN %s AND payment_date IS NULL THEN %s::date
                        ELSE payment_date
                    END
                WHERE id = %s AND owner_key = %s
                """,
                (bool(settled), bool(settled), bool(settled), bool(settled), today, int(item_id), owner_key),
            )
            if cursor.rowcount > 0:
                _sync_postgres_cash_entry(connection, int(item_id), owner_key)
        return cursor.rowcount > 0

    with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
        cursor = connection.execute(
            """
            UPDATE monthly_budget_items
            SET settled = ?,
                received_amount_text = CASE
                    WHEN item_type <> 'Receita' THEN '0,00'
                    WHEN ? = 1 THEN amount_text
                    ELSE '0,00'
                END,
                payment_date = CASE
                    WHEN ? = 0 THEN NULL
                    WHEN ? = 1 AND (payment_date IS NULL OR payment_date = '') THEN ?
                    ELSE payment_date
                END
            WHERE id = ? AND owner_key = ?
            """,
            (1 if settled else 0, 1 if settled else 0, 1 if settled else 0, 1 if settled else 0, today, int(item_id), owner_key),
        )
        if cursor.rowcount > 0:
            _sync_sqlite_cash_entry(connection, int(item_id), owner_key)
    return cursor.rowcount > 0


def update_monthly_budget_item(
    item_id: str,
    reference_month: str,
    item_type: str,
    description: str,
    amount_text: str,
    due_date: str,
    payment_date: str | None,
    settled: bool,
    observation: str = "",
    received_amount_text: str = "0,00",
    owner_key: str = DEFAULT_BUDGET_OWNER_KEY,
    tipo_receita: str | None = None,
    tipo_receita_outros: str | None = None,
    expense_nature_id: int | None = None,
) -> bool:
    ensure_monthly_budget_db()
    if item_type == "Receita" and settled and received_amount_text in {"", "0", "0,00", "0.00"}:
        received_amount_text = amount_text
    if item_type != "Receita":
        received_amount_text = "0,00"
        tipo_receita = None
        tipo_receita_outros = None
    else:
        expense_nature_id = None
        if tipo_receita != "OUTROS":
            tipo_receita_outros = None
    month_date = f"{reference_month}-01"
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            cursor = connection.execute(
                """
                UPDATE monthly_budget_items
                SET reference_month = %s,
                    item_type = %s,
                    tipo_receita = %s,
                    tipo_receita_outros = %s,
                    expense_nature_id = %s,
                    description = %s,
                    observation = %s,
                    amount_text = %s,
                    received_amount_text = %s,
                    due_date = %s,
                    payment_date = %s,
                    settled = %s
                WHERE id = %s AND owner_key = %s
                """,
                (
                    month_date,
                    item_type,
                    tipo_receita,
                    tipo_receita_outros,
                    expense_nature_id,
                    description,
                    observation,
                    amount_text,
                    received_amount_text,
                    due_date,
                    payment_date,
                    bool(settled),
                    int(item_id),
                    owner_key,
                ),
            )
            if cursor.rowcount > 0:
                _sync_postgres_cash_entry(connection, int(item_id), owner_key)
        return cursor.rowcount > 0

    with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
        cursor = connection.execute(
            """
            UPDATE monthly_budget_items
            SET reference_month = ?,
                item_type = ?,
                tipo_receita = ?,
                tipo_receita_outros = ?,
                expense_nature_id = ?,
                description = ?,
                observation = ?,
                amount_text = ?,
                received_amount_text = ?,
                due_date = ?,
                payment_date = ?,
                settled = ?
            WHERE id = ? AND owner_key = ?
            """,
            (
                month_date,
                item_type,
                tipo_receita,
                tipo_receita_outros,
                expense_nature_id,
                description,
                observation,
                amount_text,
                received_amount_text,
                due_date,
                payment_date,
                1 if settled else 0,
                int(item_id),
                owner_key,
            ),
        )
        if cursor.rowcount > 0:
            _sync_sqlite_cash_entry(connection, int(item_id), owner_key)
    return cursor.rowcount > 0


def delete_monthly_budget_item(
    item_id: str,
    owner_key: str = DEFAULT_BUDGET_OWNER_KEY,
) -> bool:
    ensure_monthly_budget_db()
    if use_postgres_investment_db():
        with investment_db_connection() as connection:
            connection.execute(
                "DELETE FROM caixa WHERE source_budget_item_id = %s AND owner_key = %s",
                (int(item_id), owner_key),
            )
            cursor = connection.execute(
                "DELETE FROM monthly_budget_items WHERE id = %s AND owner_key = %s",
                (int(item_id), owner_key),
            )
        return cursor.rowcount > 0

    with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
        connection.execute(
            "DELETE FROM caixa WHERE source_budget_item_id = ? AND owner_key = ?",
            (int(item_id), owner_key),
        )
        cursor = connection.execute(
            "DELETE FROM monthly_budget_items WHERE id = ? AND owner_key = ?",
            (int(item_id), owner_key),
        )
    return cursor.rowcount > 0


def investment_db_status() -> dict[str, object]:
    database_url_configured = bool(investment_database_url())
    backend = "postgresql" if use_postgres_investment_db() else "sqlite"
    database_url_source = investment_database_url_source()
    database_host = investment_database_host()
    try:
        ensure_monthly_budget_db()
        if use_postgres_investment_db():
            with investment_db_connection() as connection:
                count = connection.execute("SELECT COUNT(*) FROM investments").fetchone()[0]
                budget_count = connection.execute("SELECT COUNT(*) FROM monthly_budget_items").fetchone()[0]
                caixa_count = connection.execute("SELECT COUNT(*) FROM caixa").fetchone()[0]
        else:
            with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
                count = connection.execute("SELECT COUNT(*) FROM investments").fetchone()[0]
                budget_count = connection.execute("SELECT COUNT(*) FROM monthly_budget_items").fetchone()[0]
                caixa_count = connection.execute("SELECT COUNT(*) FROM caixa").fetchone()[0]
        return {
            "ok": True,
            "backend": backend,
            "database_url_configured": database_url_configured,
            "database_url_source": database_url_source,
            "database_host": database_host,
            "investment_count": int(count),
            "monthly_budget_count": int(budget_count),
            "caixa_count": int(caixa_count),
        }
    except Exception as exc:
        return {
            "ok": False,
            "backend": backend,
            "database_url_configured": database_url_configured,
            "database_url_source": database_url_source,
            "database_host": database_host,
            "investment_count": None,
            "monthly_budget_count": None,
            "caixa_count": None,
            "error": exc.__class__.__name__,
        }


def format_report_currency(value: float) -> str:
    formatted = f"{value:,.2f}"
    return f"R$ {formatted.replace(',', 'X').replace('.', ',').replace('X', '.')}"


def parse_report_currency(value: object) -> float:
    cleaned = str(value).strip().replace("R$", "").replace(" ", "")
    if not cleaned:
        return 0.0
    if "," in cleaned:
        cleaned = cleaned.replace(".", "").replace(",", ".")
    try:
        return max(float(cleaned), 0.0)
    except ValueError:
        return 0.0


def cleanup_budget_report_tokens() -> None:
    now = time.time()
    expired_tokens = [
        token
        for token, (expires_at, _html_content) in BUDGET_REPORT_PRINT_TOKENS.items()
        if expires_at < now
    ]
    for token in expired_tokens:
        BUDGET_REPORT_PRINT_TOKENS.pop(token, None)


def create_budget_report_print_token(html_content: str) -> str:
    cleanup_budget_report_tokens()
    token = secrets.token_urlsafe(24)
    BUDGET_REPORT_PRINT_TOKENS[token] = (
        time.time() + BUDGET_REPORT_TOKEN_TTL_SECONDS,
        html_content,
    )
    return token


def budget_report_print_html(token: str) -> str | None:
    cleanup_budget_report_tokens()
    record = BUDGET_REPORT_PRINT_TOKENS.get(token)
    if not record:
        return None
    return record[1]


def build_budget_report_print_html(
    title: str,
    subtitle: str,
    filter_summary: list[str],
    items: list[dict[str, object]],
    totals: dict[str, str],
) -> str:
    def escape(value: object) -> str:
        return html.escape(str(value), quote=True)

    rows = "\n".join(
        "<tr>"
        f"<td>{escape(item.get('reference_month_display', ''))}</td>"
        f"<td>{escape(item.get('item_type', ''))}</td>"
        f"<td>{escape(item.get('description', ''))}</td>"
        f"<td class=\"money\">{escape(item.get('amount_display', ''))}</td>"
        f"<td>{escape(item.get('due_date_display', ''))}</td>"
        f"<td>{escape(item.get('payment_date_display', ''))}</td>"
        f"<td>{escape(item.get('status_display', ''))}"
        f"{' <span class=\"paid-check\">&#10003;</span>' if item.get('settled') else ''}</td>"
        "</tr>"
        for item in items
    )
    if not rows:
        rows = "<tr><td colspan=\"7\" class=\"empty\">Nenhum lancamento encontrado.</td></tr>"

    filter_items = "\n".join(f"<li>{escape(filter_item)}</li>" for filter_item in filter_summary)
    generated_at = datetime.now(ZoneInfo("America/Sao_Paulo")).strftime("%d/%m/%Y %H:%M")
    return f"""<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <title>{escape(title)}</title>
  <style>
    body {{
      background: #ffffff;
      color: #20242b;
      font-family: Arial, Helvetica, sans-serif;
      margin: 28px;
    }}
    header {{
      border-bottom: 2px solid #d97706;
      margin-bottom: 18px;
      padding-bottom: 10px;
    }}
    h1 {{
      font-size: 24px;
      margin: 0 0 4px;
    }}
    .subtitle, .generated {{
      color: #5f6873;
      font-size: 12px;
    }}
    .summary {{
      display: grid;
      gap: 8px;
      grid-template-columns: repeat(4, 1fr);
      margin: 18px 0;
    }}
    .metric {{
      border: 1px solid #d7d0c4;
      border-left: 4px solid #d97706;
      border-radius: 8px;
      padding: 10px;
    }}
    .metric span {{
      color: #5f6873;
      display: block;
      font-size: 11px;
    }}
    .metric strong {{
      display: block;
      font-size: 17px;
      margin-top: 4px;
    }}
    .filters {{
      background: #f7f3eb;
      border: 1px solid #d7d0c4;
      border-radius: 8px;
      margin-bottom: 18px;
      padding: 10px 14px;
    }}
    .filters ul {{
      margin: 6px 0 0 18px;
      padding: 0;
    }}
    table {{
      border-collapse: collapse;
      font-size: 12px;
      width: 100%;
    }}
    th {{
      background: #20242b;
      color: #ffffff;
      text-align: left;
    }}
    th, td {{
      border: 1px solid #d7d0c4;
      padding: 8px;
      vertical-align: top;
    }}
    tr:nth-child(even) td {{
      background: #fbfaf7;
    }}
    .money {{
      font-weight: 700;
      text-align: right;
      white-space: nowrap;
    }}
    .empty {{
      color: #5f6873;
      text-align: center;
    }}
    .paid-check {{
      color: #167a4b;
      font-weight: 800;
      margin-left: 4px;
    }}
    .actions {{
      margin-bottom: 16px;
    }}
    button {{
      background: #d97706;
      border: 0;
      border-radius: 7px;
      color: #fff;
      cursor: pointer;
      font-weight: 700;
      padding: 10px 14px;
    }}
    @media print {{
      body {{ margin: 12mm; }}
      .actions {{ display: none; }}
    }}
  </style>
</head>
<body>
  <div class="actions"><button onclick="window.print()">Imprimir</button></div>
  <header>
    <h1>{escape(title)}</h1>
    <div class="subtitle">{escape(subtitle)}</div>
    <div class="generated">Gerado em {escape(generated_at)}</div>
  </header>
  <section class="summary">
    <div class="metric"><span>Receitas</span><strong>{escape(totals.get('revenue', 'R$ 0,00'))}</strong></div>
    <div class="metric"><span>Despesas</span><strong>{escape(totals.get('expense', 'R$ 0,00'))}</strong></div>
    <div class="metric"><span>Saldo</span><strong>{escape(totals.get('balance', 'R$ 0,00'))}</strong></div>
    <div class="metric"><span>Falta pagar</span><strong>{escape(totals.get('pending', 'R$ 0,00'))}</strong></div>
  </section>
  <section class="filters">
    <strong>Filtros aplicados</strong>
    <ul>{filter_items}</ul>
  </section>
  <table>
    <thead>
      <tr>
        <th>Mes</th>
        <th>Tipo</th>
        <th>Descricao</th>
        <th>Valor</th>
        <th>Vencimento/data</th>
        <th>Pagamento</th>
        <th>Status</th>
      </tr>
    </thead>
    <tbody>{rows}</tbody>
  </table>
  <script>window.addEventListener("load", () => setTimeout(() => window.print(), 350));</script>
</body>
</html>"""


def main(page: ft.Page) -> None:
    page.title = f"EKT IA Systems | {APP_VERSION}"
    page.theme_mode = ft.ThemeMode.LIGHT
    page.bgcolor = "#F3EFE6"
    page.padding = 0
    page.window.min_width = 280
    page.window.min_height = 460

    ibov_status = ft.Text("Carregando ativos do Ibovespa...", color="#5F6873", size=12)
    ai_status = ft.Text("Carregando ativos de IA dos EUA...", color="#5F6873", size=12)
    index_status = ft.Text("Carregando S&P 500, ES, EWZ, Nikkei e Xangai...", color="#5F6873", size=12)
    rare_earth_status = ft.Text("Carregando ativos globais de terras raras...", color="#5F6873", size=12)
    ibov_quotes_list = ft.ResponsiveRow(spacing=8, run_spacing=8)
    ibov_grid_scroll = ft.ListView(
        controls=[ibov_quotes_list],
        expand=True,
        spacing=0,
        padding=ft.Padding(left=0, top=6, right=0, bottom=2),
    )
    ibov_search_input = ft.TextField(
        hint_text="Busque por empresa ou ticker",
        prefix_icon=ft.Icons.SEARCH,
        dense=True,
        height=42,
        text_size=12,
        border_radius=8,
        border_color="#D7D0C4",
        focused_border_color="#4F8CFF",
        bgcolor="#FFFFFF",
        color="#20242B",
        cursor_color="#4F8CFF",
        content_padding=ft.Padding(left=10, top=0, right=10, bottom=0),
    )
    ibov_sector_filter = ft.Dropdown(
        value="Todos os setores",
        options=[
            ft.DropdownOption(key="Todos os setores", text="Todos os setores"),
            *[
                ft.DropdownOption(key=sector, text=sector)
                for sector in sorted(IBOV_SECTORS)
            ],
        ],
        leading_icon=ft.Icons.CATEGORY_OUTLINED,
        dense=True,
        text_size=12,
        border_radius=8,
        border_color="#D7D0C4",
        focused_border_color="#4F8CFF",
        fill_color="#FFFFFF",
        filled=True,
        color="#20242B",
        content_padding=ft.Padding(left=10, top=0, right=8, bottom=0),
        menu_height=420,
        enable_search=True,
    )
    ibov_search_suggestions = ft.Column(spacing=3, visible=False)
    ibov_search_status = ft.Text("", size=10, color="#5F6873")
    ibov_search_catalog: dict[str, dict[str, str]] = {}
    selected_ibov_symbol = {"value": ""}
    ai_quotes_list = ft.Column(spacing=4)
    index_quotes_list = ft.Column(spacing=4)
    rare_earth_quotes_list = ft.Column(spacing=4)
    search_input = ft.TextField(
        hint_text="Buscar ticker",
        dense=True,
        width=170,
        height=38,
        text_size=12,
        border_color="#C7BEAF",
        focused_border_color="#3E8E7E",
        bgcolor="#FFFFFF",
        color="#20242B",
        cursor_color="#3E8E7E",
        content_padding=ft.Padding(left=10, top=0, right=10, bottom=0),
    )
    search_status = ft.Text("Digite um ticker e pressione Enter.", color="#5F6873", size=11)
    search_suggestions = ft.Column(spacing=2)
    search_results = ft.Column(spacing=6)
    dashboard_status = ft.Text("Carregando indicadores...", color="#5F6873", size=12)
    dashboard_quotes = ft.Column(spacing=6)
    ibov_live_price = ft.Text("IBOV --", size=12, weight=ft.FontWeight.BOLD, color="#20242B")
    ibov_live_change = ft.Text("Atualizando...", size=10, weight=ft.FontWeight.BOLD, color="#667085")
    ibov_live_time = ft.Text("B3 tempo real", size=8, color="#7A6F61")
    ibov_live_badge = ft.Container(
        width=148,
        bgcolor="#FFFFFF",
        border=ft.Border(
            top=ft.BorderSide(1, "#D7D0C4"),
            right=ft.BorderSide(1, "#D7D0C4"),
            bottom=ft.BorderSide(1, "#D7D0C4"),
            left=ft.BorderSide(1, "#D7D0C4"),
        ),
        border_radius=10,
        padding=ft.Padding(left=9, top=6, right=9, bottom=6),
        shadow=ft.BoxShadow(
            spread_radius=0,
            blur_radius=12,
            color="#1A20242B",
            offset=ft.Offset(0, 4),
        ),
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.Text("IBOV", size=9, color="#667085", weight=ft.FontWeight.BOLD),
                        ibov_live_time,
                    ],
                    spacing=4,
                    alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                ),
                ibov_live_price,
                ibov_live_change,
            ],
            spacing=0,
        ),
    )
    body = ft.Container(expand=True)
    refresh_version = 0
    active_screen = {"name": "home"}
    jex_return = {"callback": None}
    last_ibov_prices: dict[str, float | None] = {}
    last_ibov_change_seen: dict[str, bool] = {}
    ibov_refresh_state = {"running": False}
    last_dashboard_prices: dict[str, float | None] = {}
    last_search_details: dict[str, tuple[list, str]] = {}
    first_load_done = {
        "ibov": False,
        "ai": False,
        "indexes": False,
        "rare_earths": False,
        "dashboard": False,
    }

    def is_current(version: int) -> bool:
        return version == refresh_version

    search_options = [
        ("IBOVESPA", "Indice Ibovespa"),
        ("IBOV", "Indice Ibovespa"),
        ("USD/BRL", "Dolar americano"),
        ("SPX", "S&P 500"),
        ("EWZ", "ETF Brasil"),
        ("ES", "E-mini S&P 500"),
        ("NIKKEI", "Nikkei 225"),
        ("SSE", "SSE Composite"),
        ("EMBJ3", "Embraer"),
        *[(ticker, "Ativo B3") for ticker in IBOVESPA_FALLBACK_TICKERS.split(",")],
        *[(ticker, "IA - EUA") for ticker in US_AI_TICKERS.split(",")],
        *[(ticker, "Terras raras - Global") for ticker in RARE_EARTH_TICKERS.split(",")],
    ]

    def ibov_search_matches(query: str) -> list[tuple[str, str]]:
        def normalize_search_text(value: str) -> str:
            decomposed = unicodedata.normalize("NFKD", value)
            return "".join(character for character in decomposed if not unicodedata.combining(character)).casefold()

        normalized = normalize_search_text(query.strip())
        if not normalized:
            return []
        matches = []
        selected_sector = ibov_sector_filter.value or "Todos os setores"
        for symbol, item in ibov_search_catalog.items():
            name = item.get("name", symbol)
            aliases = item.get("aliases", "")
            sector = item.get("sector", "Outros")
            if selected_sector != "Todos os setores" and sector != selected_sector:
                continue
            normalized_symbol = normalize_search_text(symbol)
            normalized_name = normalize_search_text(name)
            normalized_aliases = normalize_search_text(aliases)
            if normalized in normalized_symbol or normalized in normalized_name or normalized in normalized_aliases:
                priority = 0 if normalized_symbol.startswith(normalized) else 1 if normalized_name.startswith(normalized) else 2
                matches.append((priority, symbol, name))
        matches.sort(key=lambda item: (item[0], item[1]))
        return [(symbol, name) for _priority, symbol, name in matches[:6]]

    def choose_ibov_search_result(symbol: str) -> None:
        item = ibov_search_catalog.get(symbol, {})
        ibov_search_input.value = symbol
        ibov_search_suggestions.controls = []
        ibov_search_suggestions.visible = False
        ibov_search_status.value = f"{symbol} | {item.get('name', symbol)}"
        selected_ibov_symbol["value"] = symbol
        highlight_ibov_card(symbol)
        page.update()

    def update_ibov_search_suggestions(_event=None) -> None:
        query = ibov_search_input.value.strip()
        matches = ibov_search_matches(query)
        ibov_search_suggestions.controls = [
            ft.TextButton(
                content=ft.Row(
                    [
                        ft.Text(symbol, size=12, weight=ft.FontWeight.BOLD, color="#20242B"),
                        ft.Text(
                            name,
                            size=10,
                            color="#5F6873",
                            expand=True,
                            max_lines=1,
                            overflow=ft.TextOverflow.ELLIPSIS,
                        ),
                        ft.Icon(ft.Icons.NORTH_EAST, size=13, color="#4F8CFF"),
                    ],
                    spacing=8,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                style=ft.ButtonStyle(
                    bgcolor={"": "#FFFFFF", "hovered": "#EEF4FF"},
                    padding=ft.Padding(left=10, top=6, right=10, bottom=6),
                    shape=ft.RoundedRectangleBorder(radius=7),
                ),
                on_click=lambda _event, selected=symbol: choose_ibov_search_result(selected),
            )
            for symbol, name in matches
        ]
        ibov_search_suggestions.visible = bool(matches and query)
        ibov_search_status.value = (
            "" if not query else ("Selecione um ativo sugerido." if matches else "Nenhum ativo localizado.")
        )
        page.update()

    def submit_ibov_search(_event=None) -> None:
        matches = ibov_search_matches(ibov_search_input.value)
        if matches:
            choose_ibov_search_result(matches[0][0])
        else:
            ibov_search_status.value = "Nenhum ativo localizado."
            page.update()

    def card_matches_ibov_sector(card: ft.Control, selected_sector: str) -> bool:
        if selected_sector == "Todos os setores":
            return True
        if not isinstance(card.data, dict):
            return False
        return card.data.get("sector", "Outros") == selected_sector

    def apply_ibov_sector_visibility() -> int:
        selected_sector = ibov_sector_filter.value or "Todos os setores"
        visible_count = 0
        for card in ibov_quotes_list.controls:
            card.visible = card_matches_ibov_sector(card, selected_sector)
            if card.visible:
                visible_count += 1
        return visible_count

    def filter_ibov_by_sector(_event=None) -> None:
        selected_sector = ibov_sector_filter.value or "Todos os setores"
        selected_ibov_symbol["value"] = ""
        ibov_search_input.value = ""
        ibov_search_suggestions.controls = []
        ibov_search_suggestions.visible = False
        for card in ibov_quotes_list.controls:
            if not isinstance(card.data, dict):
                continue
            card.data["base_bg"] = card.data.get("normal_bg")
            card.bgcolor = card.data["base_bg"]
            card.border = ft.Border(
                top=ft.BorderSide(1, card.data.get("base_border", "#D7D0C4")),
                right=ft.BorderSide(1, card.data.get("base_border", "#D7D0C4")),
                bottom=ft.BorderSide(1, card.data.get("base_border", "#D7D0C4")),
                left=ft.BorderSide(1, card.data.get("base_border", "#D7D0C4")),
            )
            card.shadow = None
            card.scale = 1.0
        visible_count = apply_ibov_sector_visibility()
        ibov_search_status.value = (
            f"{visible_count} ativos em {selected_sector}"
            if selected_sector != "Todos os setores"
            else f"{visible_count} ativos do Ibovespa"
        )
        ibov_quotes_list.update()
        ibov_grid_scroll.scroll_to(offset=0, duration=300, curve=ft.AnimationCurve.EASE_IN_OUT)
        page.update()

    def highlight_ibov_card(symbol: str) -> None:
        found = False
        for card in ibov_quotes_list.controls:
            if not isinstance(card.data, dict):
                continue
            base_border = card.data.get("base_border", "#D7D0C4")
            is_selected = card.data.get("key") == symbol
            card.border = ft.Border(
                top=ft.BorderSide(2 if is_selected else 1, "#4F8CFF" if is_selected else base_border),
                right=ft.BorderSide(2 if is_selected else 1, "#4F8CFF" if is_selected else base_border),
                bottom=ft.BorderSide(2 if is_selected else 1, "#4F8CFF" if is_selected else base_border),
                left=ft.BorderSide(2 if is_selected else 1, "#4F8CFF" if is_selected else base_border),
            )
            card.data["base_bg"] = "#EEF4FF" if is_selected else card.data.get("normal_bg")
            card.bgcolor = card.data["base_bg"]
            card.shadow = (
                ft.BoxShadow(
                    blur_radius=16,
                    spread_radius=1,
                    color="#4F8CFF44",
                    offset=ft.Offset(0, 3),
                )
                if is_selected
                else None
            )
            card.scale = 1.01 if is_selected else 1.0
            found = found or is_selected
        if found:
            ibov_quotes_list.update()
            ibov_grid_scroll.scroll_to(
                scroll_key=f"ibov-card-{symbol}",
                duration=450,
                curve=ft.AnimationCurve.EASE_IN_OUT,
            )

    ibov_search_input.on_change = update_ibov_search_suggestions
    ibov_search_input.on_submit = submit_ibov_search
    ibov_sector_filter.on_change = filter_ibov_by_sector

    def choose_search_suggestion(symbol: str) -> None:
        search_input.value = symbol
        search_suggestions.controls = []
        page.update()
        run_search()

    def update_search_suggestions() -> None:
        query = search_input.value.strip()
        if not query:
            search_suggestions.controls = []
            return
        matches = [
            (symbol, description)
            for symbol, description in search_options
            if symbol.startswith(query) or query in symbol or query in description.upper()
        ][:6]
        search_suggestions.controls = [
            ft.TextButton(
                content=ft.Row(
                    [
                        ft.Text(symbol, size=11, weight=ft.FontWeight.BOLD, color="#20242B"),
                        ft.Text(description, size=9, color="#5F6873"),
                    ],
                    alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                ),
                style=ft.ButtonStyle(
                    bgcolor={"": "#E4DED2", "hovered": "#E5F2EC"},
                    padding=ft.Padding(left=7, top=2, right=7, bottom=2),
                    shape=ft.RoundedRectangleBorder(radius=4),
                ),
                on_click=lambda _event, selected=symbol: choose_search_suggestion(selected),
            )
            for symbol, description in matches
        ]

    def uppercase_search(_event=None) -> None:
        upper_value = search_input.value.upper()
        if search_input.value != upper_value:
            search_input.value = upper_value
        update_search_suggestions()
        page.update()

    def set_status(target: ft.Text, message: str, version: int) -> None:
        if not is_current(version):
            return
        target.value = message
        page.update()

    def ibov_time_label_sao_paulo(market_time: str | None) -> str:
        sao_paulo_tz = ZoneInfo("America/Sao_Paulo")
        utc_tz = ZoneInfo("UTC")
        fallback = datetime.now(sao_paulo_tz).strftime("%H:%M")
        raw_time = str(market_time or "").strip()
        if not raw_time:
            return f"Atualizado {fallback} BRT"

        cleaned = (
            raw_time.upper()
            .replace("BRT", "")
            .replace("UTC", "")
            .replace("GMT", "")
            .replace("H", "")
            .strip()
        )
        try:
            if "T" in cleaned or "-" in cleaned:
                parsed = datetime.fromisoformat(cleaned.replace("Z", "+00:00"))
                if parsed.tzinfo is None:
                    parsed = parsed.replace(tzinfo=utc_tz)
                sao_paulo_time = parsed.astimezone(sao_paulo_tz)
            else:
                hour, minute, *_rest = cleaned.split(":")
                source_time = datetime.now(utc_tz).replace(
                    hour=int(hour),
                    minute=int(minute),
                    second=0,
                    microsecond=0,
                )
                sao_paulo_time = source_time.astimezone(sao_paulo_tz)
            return f"Atualizado {sao_paulo_time.strftime('%H:%M')} BRT"
        except Exception:
            return f"Atualizado {fallback} BRT"

    def update_b3_market_header() -> None:
        if active_screen["name"] != "market":
            try:
                market_header.visible = False
            except NameError:
                pass
            try:
                compact_footer = active_screen["name"] == "monthly_budget"
                app_footer.padding = ft.Padding(
                    left=8,
                    top=2 if compact_footer else 7,
                    right=8,
                    bottom=2 if compact_footer else 8,
                )
                footer_label.size = 8 if compact_footer else 10
                footer_logo.width = 142 if compact_footer else 220
                footer_logo.height = 32 if compact_footer else 52
                app_footer.content.spacing = 4 if compact_footer else 6
            except NameError:
                pass
            return
        try:
            market_header.visible = True
        except NameError:
            pass
        try:
            app_footer.padding = ft.Padding(left=12, top=7, right=12, bottom=8)
            footer_label.size = 10
            footer_logo.width = 220
            footer_logo.height = 52
            app_footer.content.spacing = 6
        except NameError:
            pass
        try:
            quote = fetch_ibov_dashboard_quote()
        except Exception:
            ibov_live_price.value = "IBOV indisponivel"
            ibov_live_change.value = "Nova tentativa em instantes"
            ibov_live_change.color = "#B54708"
            ibov_live_time.value = f"Atualizado {datetime.now(ZoneInfo('America/Sao_Paulo')).strftime('%H:%M')} BRT"
            page.update()
            return

        ibov_live_price.value = f"IBOV {price_text(quote.price)}"
        if quote.change_percent is None:
            ibov_live_change.value = "Variacao indisponivel"
            ibov_live_change.color = "#667085"
        else:
            sign = "+" if quote.change_percent >= 0 else ""
            ibov_live_change.value = f"{sign}{quote.change_percent:.2f}% no dia"
            ibov_live_change.color = "#198754" if quote.change_percent >= 0 else "#C2413A"
        ibov_live_time.value = ibov_time_label_sao_paulo(quote.market_time)
        page.update()

    def load_ibovespa_market(version: int) -> None:
        if ibov_refresh_state["running"]:
            return
        if first_load_done["ibov"] and not is_brazil_market_open():
            set_status(ibov_status, "Mercado fechado. Cotacoes pausadas.", version)
            update_b3_market_header()
            return
        ibov_refresh_state["running"] = True
        update_b3_market_header()
        tickers = IBOVESPA_FALLBACK_TICKERS

        try:
            if not is_current(version):
                return
            try:
                ibov_portfolio = fetch_ibovespa_portfolio()
            except Exception:
                ibov_portfolio = {}
            if ibov_portfolio:
                tickers = ",".join(ibov_portfolio)
            initial_load = not first_load_done["ibov"]
            total = len(tickers.split(","))
            if initial_load:
                ibov_quotes_list.controls = []
            else:
                ibov_quotes_list.controls = [
                    card
                    for card in ibov_quotes_list.controls
                    if not isinstance(card.data, dict) or card.data.get("key") != "EMBR3"
                ]
            last_ibov_prices.pop("EMBR3", None)
            last_ibov_change_seen.pop("EMBR3", None)
            if initial_load:
                set_status(ibov_status, f"{total} ativos locais. Sincronizando cotacoes da B3...", version)
            loaded = 0
            changed_quotes = 0

            def add_quote(quote) -> None:
                nonlocal loaded, changed_quotes
                if not is_current(version):
                    return
                portfolio_item = ibov_portfolio.get(quote.symbol) or {}
                quote.ibov_weight = portfolio_item.get("weight")
                official_name = str(portfolio_item.get("asset") or "").strip()
                display_name = official_name or quote.name or quote.symbol
                sector = IBOV_SECTOR_BY_SYMBOL.get(quote.symbol, "Outros")
                ibov_search_catalog[quote.symbol] = {
                    "name": display_name,
                    "aliases": f"{quote.name or ''} {official_name}",
                    "sector": sector,
                }
                loaded += 1
                previous_price = last_ibov_prices.get(quote.symbol)
                price_changed = (
                    previous_price is not None
                    and quote.price is not None
                    and round(float(quote.price), 4) != round(float(previous_price), 4)
                )
                last_ibov_prices[quote.symbol] = quote.price
                last_ibov_change_seen[quote.symbol] = price_changed
                if not initial_load and not price_changed:
                    return
                if price_changed:
                    changed_quotes += 1
                card = market_card(
                    quote,
                    show_market_state=True,
                    on_click=open_ibovespa_analysis,
                    blink=price_changed,
                    apple_style=True,
                    highlighted=selected_ibov_symbol["value"] == quote.symbol,
                )
                card.data["sector"] = sector
                card.visible = card_matches_ibov_sector(
                    card,
                    ibov_sector_filter.value or "Todos os setores",
                )
                responsive_item(card, xs=12, sm=6, md=4, lg=3)
                upsert_card(ibov_quotes_list, card, quote.symbol)
                if initial_load and (loaded == 1 or loaded % 8 == 0):
                    page.update()
                    if price_changed:
                        blink_card(card, page)

            def show_progress(done: int, expected: int) -> None:
                if not is_current(version) or not initial_load:
                    return
                ibov_status.value = f"Sincronizando cotacoes da B3... {done}/{expected}"
                if done == expected or done % 12 == 0:
                    page.update()

            total_quotes, quote_source = stream_brazil_market_quotes(tickers, add_quote, show_progress)
        except Exception as exc:
            set_status(ibov_status, f"Erro ao buscar cotacoes: {exc}", version)
            return
        finally:
            ibov_refresh_state["running"] = False

        if not is_current(version):
            return
        first_load_done["ibov"] = True
        apply_ibov_sector_visibility()
        updated_at = datetime.now(ZoneInfo("America/Sao_Paulo")).strftime("%H:%M:%S")
        set_status(
            ibov_status,
            f"{total_quotes} cotacoes | {quote_source} | leitura {updated_at} | "
            f"{changed_quotes} variacoes | ciclo {IBOV_REFRESH_SECONDS}s",
            version,
        )

    def load_ai_market(version: int) -> None:
        if not is_current(version):
            return
        if first_load_done["ai"] and not is_us_stock_market_open():
            set_status(ai_status, "Mercado fechado. Cotacoes pausadas.", version)
            return
        if not first_load_done["ai"]:
            ai_quotes_list.controls = []
        tickers = US_AI_TICKERS
        set_status(ai_status, "Buscando cotacoes de IA dos EUA...", version)
        loaded = 0

        def add_quote(quote) -> None:
            nonlocal loaded
            if not is_current(version):
                return
            loaded += 1
            card = market_card(quote, show_market_state=True, blink=True)
            upsert_card(ai_quotes_list, card, quote.symbol)
            if loaded == 1 or loaded % 5 == 0:
                page.update()
                blink_card(card, page)

        def show_progress(done: int, expected: int) -> None:
            if not is_current(version):
                return
            ai_status.value = f"Buscando cotacoes... {done}/{expected}"
            if done == expected or done % 5 == 0:
                page.update()

        try:
            total_quotes = stream_us_market_quotes(tickers, add_quote, show_progress)
        except Exception as exc:
            set_status(ai_status, f"Erro ao buscar cotacoes: {exc}", version)
            return

        first_load_done["ai"] = True
        set_status(ai_status, f"{total_quotes} cotacoes atualizadas. Dados podem ter atraso.", version)

    def load_index_market(version: int) -> None:
        if not is_current(version):
            return
        if first_load_done["indexes"] and not is_any_index_market_open():
            set_status(index_status, "Mercados fechados. Cotacoes pausadas.", version)
            return
        if not first_load_done["indexes"]:
            index_quotes_list.controls = []
        set_status(
            index_status,
            f"Buscando S&P 500, ES, EWZ, Nikkei e Xangai... auto {FAST_REFRESH_SECONDS}s",
            version,
        )
        loaded = 0

        def add_quote(quote) -> None:
            nonlocal loaded
            if not is_current(version):
                return
            loaded += 1
            card = market_card(quote, show_market_state=True, on_click=open_sse_chart, blink=True)
            upsert_card(index_quotes_list, card, quote.symbol)
            page.update()
            blink_card(card, page)

        def show_progress(done: int, expected: int) -> None:
            if not is_current(version):
                return
            index_status.value = f"Buscando cotacoes... {done}/{expected}"
            page.update()

        try:
            total_quotes = 0
            if is_us_stock_market_open() or not first_load_done["indexes"]:
                total_quotes += stream_tradingview_quotes(US_INDEX_TICKERS, add_quote, show_progress)
            if is_cme_equity_futures_market_open() or not first_load_done["indexes"]:
                total_quotes += stream_emini_sp500_quote(add_quote, show_progress)
            if is_japan_market_open() or not first_load_done["indexes"]:
                total_quotes += stream_nikkei_quote(add_quote, show_progress)
            if is_shanghai_market_open() or not first_load_done["indexes"]:
                total_quotes += stream_shanghai_quote(add_quote, show_progress)
        except Exception as exc:
            set_status(index_status, f"Erro ao buscar cotacoes: {exc}", version)
            return

        first_load_done["indexes"] = True
        set_status(
            index_status,
            f"{total_quotes} cotacoes atualizadas. Auto {FAST_REFRESH_SECONDS}s. Dados podem ter atraso.",
            version,
        )

    def load_rare_earth_market(version: int) -> None:
        if not is_current(version):
            return
        if not first_load_done["rare_earths"]:
            rare_earth_quotes_list.controls = []
        set_status(rare_earth_status, "Buscando terras raras globais...", version)
        loaded = 0

        def add_quote(quote) -> None:
            nonlocal loaded
            if not is_current(version):
                return
            loaded += 1
            card = market_card(quote, show_market_state=True, blink=True)
            upsert_card(rare_earth_quotes_list, card, quote.symbol)
            if loaded == 1 or loaded % 4 == 0:
                page.update()
                blink_card(card, page)

        def show_progress(done: int, expected: int) -> None:
            if not is_current(version):
                return
            rare_earth_status.value = f"Buscando cotacoes globais... {done}/{expected}"
            if done == expected or done % 4 == 0:
                page.update()

        try:
            total_quotes = stream_rare_earth_quotes(RARE_EARTH_TICKERS, add_quote, show_progress)
        except Exception as exc:
            set_status(rare_earth_status, f"Erro ao buscar terras raras: {exc}", version)
            return

        first_load_done["rare_earths"] = True
        set_status(rare_earth_status, f"{total_quotes} ativos globais atualizados.", version)

    def auto_refresh_indexes(version: int) -> None:
        while is_current(version):
            time.sleep(FAST_REFRESH_SECONDS)
            if not is_current(version):
                return
            update_b3_market_header()
            load_index_market(version)

    def auto_refresh_ibovespa(version: int) -> None:
        while is_current(version):
            time.sleep(IBOV_REFRESH_SECONDS)
            if not is_current(version):
                return
            update_b3_market_header()
            load_ibovespa_market(version)

    def auto_refresh_full(version: int) -> None:
        while is_current(version):
            time.sleep(FULL_REFRESH_SECONDS)
            if not is_current(version):
                return
            page.run_thread(lambda: load_ai_market(version))
            page.run_thread(lambda: load_rare_earth_market(version))
            page.run_thread(lambda: load_dashboard(version))

    def delayed_initial_full_refresh(version: int) -> None:
        time.sleep(INITIAL_FULL_REFRESH_DELAY_SECONDS)
        if not is_current(version):
            return
        page.run_thread(lambda: load_ai_market(version))
        page.run_thread(lambda: load_rare_earth_market(version))

    def load_dashboard(version: int) -> None:
        if not is_current(version):
            return
        if first_load_done["dashboard"] and not is_brazil_market_open() and not is_forex_market_open():
            set_status(dashboard_status, "Mercados fechados. Indicadores pausados.", version)
            return
        if not first_load_done["dashboard"]:
            dashboard_quotes.controls = []
        set_status(dashboard_status, "Carregando indicadores...", version)
        updated_cards = []
        errors = []
        if is_brazil_market_open() or not first_load_done["dashboard"]:
            try:
                ibov_quote = fetch_ibov_dashboard_quote()
                previous_price = last_dashboard_prices.get("IBOV")
                direction = price_direction(previous_price, ibov_quote.price)
                last_dashboard_prices["IBOV"] = ibov_quote.price
                ibov_card = compact_quote_card(
                    ibov_quote,
                    "IBOV atualizado",
                    blink=direction is not None,
                    blink_bg=direction_blink_color(direction),
                )
                upsert_card(dashboard_quotes, ibov_card, "IBOV")
                if direction is not None:
                    updated_cards.append(ibov_card)
            except Exception as exc:
                errors.append(f"IBOV: {exc}")
        if is_forex_market_open() or not first_load_done["dashboard"]:
            try:
                dollar_card = compact_quote_card(fetch_dollar_brl_quote(), "Cotacao online", blink=True)
                upsert_card(dashboard_quotes, dollar_card, "USD/BRL")
                updated_cards.append(dollar_card)
            except Exception as exc:
                errors.append(f"USD/BRL: {exc}")

        if not is_current(version):
            return
        first_load_done["dashboard"] = True
        status = "Fonte: TradingView"
        if errors:
            status = f"{status}. Falhas: {'; '.join(errors[:2])}"
        set_status(dashboard_status, status, version)
        for card in updated_cards:
            blink_card(card, page)

    def refresh_all(_event=None) -> None:
        nonlocal refresh_version
        refresh_version += 1
        version = refresh_version
        update_b3_market_header()
        ibov_status.value = "Iniciando Ibovespa..."
        ai_status.value = "Aguardando carregamento leve inicial..."
        rare_earth_status.value = "Aguardando carregamento leve inicial..."
        page.update()
        page.run_thread(lambda: load_ibovespa_market(version))
        page.run_thread(lambda: load_index_market(version))
        page.run_thread(lambda: load_dashboard(version))
        page.run_thread(lambda: delayed_initial_full_refresh(version))
        page.run_thread(lambda: auto_refresh_ibovespa(version))
        page.run_thread(lambda: auto_refresh_indexes(version))
        page.run_thread(lambda: auto_refresh_full(version))

    def refresh_ibovespa_only(_event=None) -> None:
        nonlocal refresh_version
        refresh_version += 1
        version = refresh_version
        update_b3_market_header()
        ibov_status.value = "Iniciando ativos do Ibovespa..."
        page.update()
        page.run_thread(lambda: load_ibovespa_market(version))
        page.run_thread(lambda: auto_refresh_ibovespa(version))

    def render_home_screen() -> None:
        nonlocal refresh_version
        refresh_version += 1
        active_screen["name"] = "home"
        page.route = "/"
        update_b3_market_header()
        body.content = home_menu_view(
            open_market_screen,
            open_investments_screen,
            open_jex_from_home,
        )
        page.update()

    def open_market_screen(_event=None) -> None:
        active_screen["name"] = "market"
        render_market_screen()
        refresh_ibovespa_only()

    def return_to_market_screen() -> None:
        active_screen["name"] = "market"
        render_market_screen()
        refresh_ibovespa_only()

    def open_jex_from_home(_event=None) -> None:
        jex_return["callback"] = render_home_screen
        open_jex_company_screen()

    def open_jex_from_market(_event=None) -> None:
        jex_return["callback"] = return_to_market_screen
        open_jex_company_screen()

    def open_investments_screen(_event=None) -> None:
        active_screen["name"] = "investments_login"
        update_b3_market_header()
        body.content = investments_login_view(render_home_screen, open_investments_menu_screen)
        page.update()

    def open_investments_menu_screen(_event=None) -> None:
        active_screen["name"] = "investments_menu"
        update_b3_market_header()
        body.content = investments_menu_view(
            render_home_screen,
            open_my_investments_screen,
            open_monthly_budget_screen,
            open_day_trade_operations_screen,
        )
        page.update()

    def open_investments_form_screen(_event=None) -> None:
        active_screen["name"] = "investments_form"
        update_b3_market_header()
        body.content = investments_form_view(
            render_home_screen,
            page,
            open_fixed_income_detail_screen,
            open_my_investments_screen,
            open_monthly_budget_screen,
        )
        page.update()

    def open_my_investments_screen(_event=None) -> None:
        active_screen["name"] = "my_investments"
        update_b3_market_header()
        body.content = my_investments_view(open_investments_menu_screen, page)
        page.update()

    def open_monthly_budget_screen(_event=None) -> None:
        active_screen["name"] = "monthly_budget"
        update_b3_market_header()
        try:
            body.content = monthly_budget_simple_view(open_investments_menu_screen, page)
        except Exception as exc:
            body.content = monthly_budget_error_view(str(exc), open_investments_menu_screen)
        page.update()

    def open_day_trade_operations_screen(_event=None) -> None:
        active_screen["name"] = "day_trade_operations"
        update_b3_market_header()
        body.content = day_trade_operations_view(open_investments_menu_screen)
        page.update()

    def open_fixed_income_detail_screen(product_name: str, category: str = "Renda fixa") -> None:
        active_screen["name"] = "investments_detail"
        update_b3_market_header()
        body.content = fixed_income_detail_view(product_name, category, open_investments_form_screen)
        page.update()

    def open_jex_company_screen(_event=None) -> None:
        active_screen["name"] = "jex"
        on_back = jex_return["callback"] or render_home_screen
        body.content = jex_company_view(on_back, open_jex_analytics_screen)
        page.update()

    def open_jex_analytics_screen(_event=None) -> None:
        active_screen["name"] = "jex"
        body.content = jex_analytics_view(open_jex_company_screen, open_jex_financial_snapshot)
        page.update()

    def open_jex_financial_snapshot(_event=None) -> None:
        active_screen["name"] = "jex"
        body.content = jex_financial_snapshot_view(open_jex_analytics_screen)
        page.update()

    def run_search(_event=None) -> None:
        nonlocal refresh_version
        query = search_input.value.strip()
        if not query:
            search_status.value = "Informe um ticker para buscar."
            page.update()
            return
        refresh_version += 1
        search_suggestions.controls = []
        search_status.value = f"Buscando {query.upper()}..."
        body.content = line_chart_loading_view(query.upper())
        page.update()
        page.run_thread(lambda: load_search_quote(query))

    def load_search_quote(query: str) -> None:
        try:
            quote, candles = daily_quote_for_search(query)
            explanation = trend_explanation(candles, quote)
        except Exception as exc:
            search_status.value = f"Erro na busca: {exc}"
            body.content = chart_error_view(str(exc), return_to_market_screen)
            page.update()
            return
        last_search_details[quote.symbol] = (candles, explanation)
        card = compact_quote_card(quote, "Busca manual", blink=True, on_click=open_cached_quote_detail)
        upsert_card(search_results, card, quote.symbol)
        search_status.value = f"{quote.symbol} atualizado."
        page.update()
        blink_card(card, page)
        body.content = line_chart_view(quote, candles, explanation, return_to_market_screen)
        page.update()

    def render_market_screen() -> None:
        active_screen["name"] = "market"
        total_assets = len(IBOVESPA_FALLBACK_TICKERS.split(","))
        body.content = ft.Container(
            bgcolor="#EFE9DC",
            padding=ft.Padding(left=12, top=6, right=12, bottom=10),
            expand=True,
            content=ft.Column(
                [
                    ft.Container(
                        bgcolor="#FAF7F0",
                        border=ft.Border(
                            top=ft.BorderSide(1, "#D7D0C4"),
                            right=ft.BorderSide(1, "#D7D0C4"),
                            bottom=ft.BorderSide(1, "#D7D0C4"),
                            left=ft.BorderSide(1, "#D7D0C4"),
                        ),
                        border_radius=8,
                        padding=ft.Padding(left=8, top=8, right=8, bottom=8),
                        content=ft.Row(
                            [
                                ft.IconButton(
                                    icon=ft.Icons.ARROW_BACK,
                                    tooltip="Voltar ao inicio",
                                    icon_color="#20242B",
                                    bgcolor="#E3DCCF",
                                    on_click=lambda _event: render_home_screen(),
                                ),
                                ft.Column(
                                    [
                                        ft.Text("Ibovespa", size=20, weight=ft.FontWeight.BOLD, color="#20242B"),
                                        ft.Text(
                                            f"{total_assets} ativos do indice",
                                            size=12,
                                            color="#667085",
                                        ),
                                    ],
                                    spacing=1,
                                    expand=True,
                                ),
                                ibov_live_badge,
                            ],
                            spacing=8,
                            vertical_alignment=ft.CrossAxisAlignment.CENTER,
                            alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                        ),
                    ),
                    ibovespa_grid_panel(ibov_status, ibov_quotes_list),
                ],
                spacing=10,
            ),
        )
        page.update()

    def ibovespa_grid_panel(status: ft.Text, quotes: ft.ResponsiveRow) -> ft.Control:
        return ft.Container(
            expand=True,
            bgcolor="#F6F2EA",
            border=ft.Border(
                top=ft.BorderSide(1, "#D7D0C4"),
                right=ft.BorderSide(1, "#D7D0C4"),
                bottom=ft.BorderSide(1, "#D7D0C4"),
                left=ft.BorderSide(1, "#D7D0C4"),
            ),
            border_radius=8,
            padding=ft.Padding(left=12, top=10, right=12, bottom=12),
            content=ft.Column(
                [
                    ft.Row(
                        [
                            ft.Text("Cota��es", size=15, weight=ft.FontWeight.BOLD, color="#20242B"),
                            ft.Container(expand=True),
                            status,
                        ],
                        spacing=10,
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                    ft.ResponsiveRow(
                        [
                            responsive_item(ibov_search_input, xs=12, sm=6, md=5, lg=4),
                            responsive_item(ibov_sector_filter, xs=12, sm=6, md=4, lg=4),
                            responsive_item(
                                ft.Container(
                                    alignment=ft.Alignment(1, 0),
                                    content=ibov_search_status,
                                ),
                                xs=12,
                                sm=12,
                                md=3,
                                lg=4,
                            ),
                        ],
                        spacing=8,
                        run_spacing=5,
                    ),
                    ibov_search_suggestions,
                    ibov_grid_scroll,
                ],
                spacing=8,
            ),
        )

    def open_sse_chart(quote) -> None:
        if quote.symbol != "SSE Composite":
            return
        body.content = chart_loading_view()
        page.update()
        page.run_thread(load_sse_chart)

    def load_sse_chart() -> None:
        try:
            candles = fetch_yahoo_candles(SHANGHAI_TICKER, interval="5m", range_="1d")
            chart_path = Path(__file__).with_name("assets") / "sse-composite-5m.svg"
            save_candlestick_svg(candles, chart_path, "SSE Composite - Candles 5m | MA 9 / MA 20")
        except Exception as exc:
            body.content = chart_error_view(str(exc), return_to_market_screen)
            page.update()
            return
        body.content = chart_view(chart_path, return_to_market_screen)
        page.update()

    def open_quote_detail(quote, query: str | None = None) -> None:
        body.content = line_chart_loading_view(quote)
        page.update()
        page.run_thread(lambda: load_quote_detail(quote, query or quote.symbol))

    def open_cached_quote_detail(quote) -> None:
        cached = last_search_details.get(quote.symbol)
        if cached:
            candles, explanation = cached
            body.content = line_chart_view(quote, candles, explanation, return_to_market_screen)
            page.update()
            return
        open_quote_detail(quote)

    def open_ibovespa_analysis(quote) -> None:
        active_screen["name"] = "ibovespa_analysis"
        body.content = ibovespa_analysis_loading_view(quote)
        page.update()
        page.run_thread(lambda: load_ibovespa_analysis(quote))

    def load_ibovespa_analysis(quote) -> None:
        try:
            yahoo_symbol = yahoo_symbol_for_search(quote.symbol, quote)
            candles = fetch_yahoo_candles_cached(yahoo_symbol, interval="1d", range_="1y")
            horizons = multi_horizon_trend(candles)
        except Exception as exc:
            body.content = chart_error_view(str(exc), return_to_market_screen)
            page.update()
            return
        try:
            fundamentals = fetch_brazil_fundamentals(quote.symbol)
            valuation = fundamental_valuation(fundamentals)
        except Exception as exc:
            fundamentals = {"source": "Dados indisponiveis", "error": str(exc)}
            valuation = {
                "label": "Dados insuficientes",
                "color": "#667085",
                "explanation": "A fonte nao retornou indicadores suficientes.",
            }
        body.content = ibovespa_analysis_view(
            quote,
            horizons,
            fundamentals,
            valuation,
            return_to_market_screen,
        )
        page.update()

    def load_quote_detail(quote, query: str) -> None:
        try:
            yahoo_symbol = yahoo_symbol_for_search(query, quote)
            candles = fetch_yahoo_candles_cached(yahoo_symbol, interval="1d", range_="6mo")
            explanation = trend_explanation(candles, quote)
        except Exception as exc:
            body.content = chart_error_view(str(exc), return_to_market_screen)
            page.update()
            return
        last_search_details[quote.symbol] = (candles, explanation)
        body.content = line_chart_view(quote, candles, explanation, return_to_market_screen)
        page.update()

    market_header = ft.Container(
        padding=ft.Padding(left=7, top=5, right=7, bottom=4),
        content=ft.ResponsiveRow(
            [
                responsive_item(ft.Text("Mercado", size=18, weight=ft.FontWeight.BOLD), xs=12, sm=3, md=2, lg=2),
                responsive_item(ft.Text(
                    f"Atualizacao automatica: Ibovespa {IBOV_REFRESH_SECONDS}s, mercados globais {FAST_REFRESH_SECONDS}s, indicadores {FULL_REFRESH_SECONDS}s. Fonte gratuita pode ter atraso.",
                    size=11,
                    color="#5F6873",
                ), xs=12, sm=9, md=10, lg=10),
            ],
            spacing=12,
            run_spacing=5,
        ),
    )
    footer_label = ft.Text("DESENVOLVIDO POR", size=10, color="#5F6873", weight=ft.FontWeight.BOLD)
    footer_logo = ft.Image(
        src="/ekt-ia-systems-logo.png",
        width=220,
        height=52,
    )
    app_footer = ft.Container(
        border=ft.Border(
            top=ft.BorderSide(1, "#D7D0C4"),
            right=ft.BorderSide(0, "#D7D0C4"),
            bottom=ft.BorderSide(0, "#D7D0C4"),
            left=ft.BorderSide(0, "#D7D0C4"),
        ),
        padding=ft.Padding(left=12, top=7, right=12, bottom=8),
        content=ft.Row(
            [
                footer_label,
                footer_logo,
            ],
            alignment=ft.MainAxisAlignment.CENTER,
            vertical_alignment=ft.CrossAxisAlignment.CENTER,
            spacing=6,
        ),
    )

    page.add(
        ft.SafeArea(
            ft.Column(
                [
                    market_header,
                    body,
                    app_footer,
                ],
                expand=True,
                spacing=0,
            ),
            expand=True,
        )
    )
    page.route = "/"
    render_home_screen()
    search_input.on_change = uppercase_search
    search_input.on_submit = run_search
    page.on_route_change = lambda _event: render_home_screen()
    page.on_resize = lambda _event: render_market_screen() if active_screen["name"] == "market" else None


def home_menu_view(on_market, on_investments, on_jex) -> ft.Control:
    return ft.Container(
        expand=True,
        padding=ft.Padding(left=14, top=14, right=14, bottom=18),
        content=ft.Column(
            [
                ft.Column(
                    [
                        ft.Text("EKT-IA SYSTEMS", size=22, weight=ft.FontWeight.BOLD),
                        ft.Text("Central de acompanhamento financeiro", size=12, color="#5F6873"),
                    ],
                    spacing=2,
                ),
                ft.Row(
                    [
                        ft.Text("Modulos", size=14, weight=ft.FontWeight.BOLD),
                        ft.Container(height=1, bgcolor="#D7D0C4", expand=True),
                        ft.Text("Selecione uma area", size=10, color="#5F6873"),
                    ],
                    spacing=10,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.ResponsiveRow(
                    [
                        responsive_item(
                            home_menu_card(
                                "Ibovespa",
                                "Ativos integrantes do indice com acompanhamento de cotacoes e leitura recorrente.",
                                ft.Icons.SHOW_CHART,
                                "#3E8E7E",
                                "Acompanhar Ibovespa",
                                on_market,
                            ),
                            xs=12,
                            sm=6,
                            md=6,
                            lg=4,
                        ),
                        responsive_item(
                            home_menu_card(
                                "Investimentos",
                                "Area protegida para organizar oportunidades, estrategias e acompanhamento de carteira.",
                                ft.Icons.ACCOUNT_BALANCE_WALLET,
                                "#4F8CFF",
                                "Login Investimentos",
                                on_investments,
                            ),
                            xs=12,
                            sm=6,
                            md=6,
                            lg=4,
                        ),
                        responsive_item(
                            home_menu_card(
                                "JEX",
                                "Perfil publico, fontes verificaveis e fotografia financeira executiva.",
                                ft.Icons.BUSINESS,
                                "#8B5CF6",
                                "Acompanhar JEX",
                                on_jex,
                            ),
                            xs=12,
                            sm=6,
                            md=6,
                            lg=4,
                        ),
                    ],
                    spacing=12,
                    run_spacing=12,
                ),
            ],
            spacing=14,
            scroll=ft.ScrollMode.AUTO,
        ),
    )


def home_menu_card(title: str, description: str, icon, accent: str, action_label: str, on_click) -> ft.Control:
    return ft.Container(
        height=218,
        bgcolor="#FFFFFF",
        border=ft.Border(
            top=ft.BorderSide(3, accent),
            right=ft.BorderSide(1, "#D7D0C4"),
            bottom=ft.BorderSide(1, "#D7D0C4"),
            left=ft.BorderSide(1, "#D7D0C4"),
        ),
        border_radius=10,
        padding=ft.Padding(left=15, top=14, right=15, bottom=14),
        shadow=ft.BoxShadow(
            blur_radius=12,
            spread_radius=0,
            color="#10000000",
            offset=ft.Offset(0, 4),
        ),
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.Container(
                            width=40,
                            height=40,
                            border_radius=9,
                            bgcolor="#F7F3EB",
                            alignment=ft.Alignment(0, 0),
                            content=ft.Icon(icon, size=21, color=accent),
                        ),
                        ft.Container(
                            bgcolor="#F7F3EB",
                            border_radius=10,
                            padding=ft.Padding(left=8, top=3, right=8, bottom=3),
                            content=ft.Text(
                                "MODULO",
                                size=8,
                                color="#6B7280",
                                weight=ft.FontWeight.BOLD,
                            ),
                        ),
                    ],
                    alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Column(
                    [
                        ft.Text(title, size=16, weight=ft.FontWeight.BOLD),
                        ft.Text(
                            description,
                            size=11,
                            color="#5F6873",
                            max_lines=3,
                            overflow=ft.TextOverflow.ELLIPSIS,
                        ),
                    ],
                    spacing=5,
                    expand=True,
                ),
                ft.FilledButton(
                    action_label,
                    icon=ft.Icons.ARROW_FORWARD,
                    height=40,
                    on_click=on_click,
                    style=ft.ButtonStyle(
                        bgcolor=accent,
                        color="#F8FAFC",
                        shape=ft.RoundedRectangleBorder(radius=8),
                    ),
                ),
            ],
            spacing=10,
            horizontal_alignment=ft.CrossAxisAlignment.STRETCH,
        ),
    )


def investments_login_view(on_back, on_success) -> ft.Control:
    login_input = ft.TextField(
        label="Login",
        prefix_icon=ft.Icons.PERSON_OUTLINE,
        dense=True,
        height=44,
        text_size=13,
        border_color="#C7BEAF",
        focused_border_color="#4F8CFF",
        border_radius=8,
        bgcolor="#FFFFFF",
        color="#20242B",
        cursor_color="#4F8CFF",
        content_padding=ft.Padding(left=12, top=0, right=12, bottom=0),
    )
    password_input = ft.TextField(
        label="Senha",
        prefix_icon=ft.Icons.LOCK_OUTLINE,
        dense=True,
        height=44,
        text_size=13,
        password=True,
        can_reveal_password=True,
        border_color="#C7BEAF",
        focused_border_color="#4F8CFF",
        border_radius=8,
        bgcolor="#FFFFFF",
        color="#20242B",
        cursor_color="#4F8CFF",
        content_padding=ft.Padding(left=12, top=0, right=12, bottom=0),
    )
    login_status = ft.Text("", size=11, color="#B42332", text_align=ft.TextAlign.CENTER)

    def validate_login(_event=None) -> None:
        if not investments_credentials_configured():
            login_status.value = "Credenciais de investimentos nao configuradas."
            login_status.update()
            return
        if validate_investments_credentials(
            login_input.value or "",
            password_input.value or "",
        ):
            try:
                prepare_budget_storage_after_login()
            except Exception:
                login_status.value = "Nao foi possivel preparar o banco do orcamento."
                login_status.update()
                return
            login_status.value = ""
            on_success()
            return
        login_status.value = "Login ou senha invalidos."
        login_status.update()

    password_input.on_submit = validate_login
    return ft.Container(
        expand=True,
        padding=ft.Padding(left=16, top=14, right=16, bottom=20),
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.IconButton(
                            icon=ft.Icons.ARROW_BACK,
                            tooltip="Voltar ao inicio",
                            icon_color="#20242B",
                            bgcolor="#E4DED2",
                            on_click=lambda _event: on_back(),
                        ),
                        ft.Column(
                            [
                                ft.Text("Investimentos", size=20, weight=ft.FontWeight.BOLD),
                                ft.Text("Acesso ao controle da carteira", size=11, color="#5F6873"),
                            ],
                            spacing=1,
                        ),
                    ],
                    spacing=10,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Container(
                    expand=True,
                    alignment=ft.Alignment(0, -0.2),
                    content=ft.Container(
                        width=420,
                        bgcolor="#FFFFFF",
                        border=ft.Border(
                            top=ft.BorderSide(1, "#D7D0C4"),
                            right=ft.BorderSide(1, "#D7D0C4"),
                            bottom=ft.BorderSide(1, "#D7D0C4"),
                            left=ft.BorderSide(1, "#D7D0C4"),
                        ),
                        border_radius=12,
                        padding=ft.Padding(left=26, top=24, right=26, bottom=24),
                        shadow=ft.BoxShadow(
                            blur_radius=18,
                            spread_radius=0,
                            color="#18000000",
                            offset=ft.Offset(0, 6),
                        ),
                        content=ft.Column(
                            [
                                ft.Container(
                                    width=46,
                                    height=46,
                                    border_radius=12,
                                    bgcolor="#EEF4FF",
                                    alignment=ft.Alignment(0, 0),
                                    content=ft.Icon(ft.Icons.LOCK_PERSON, size=24, color="#4F8CFF"),
                                ),
                                ft.Text("Acesso restrito", size=18, weight=ft.FontWeight.BOLD),
                                ft.Text(
                                    "Entre com suas credenciais para gerenciar investimentos.",
                                    size=11,
                                    color="#5F6873",
                                    text_align=ft.TextAlign.CENTER,
                                ),
                                ft.Container(height=2),
                                login_input,
                                password_input,
                                login_status,
                                ft.FilledButton(
                                    "Entrar",
                                    icon=ft.Icons.LOGIN,
                                    height=42,
                                    on_click=validate_login,
                                    style=ft.ButtonStyle(
                                        bgcolor="#4F8CFF",
                                        color="#F8FAFC",
                                        shape=ft.RoundedRectangleBorder(radius=8),
                                    ),
                                ),
                            ],
                            spacing=10,
                            horizontal_alignment=ft.CrossAxisAlignment.STRETCH,
                        ),
                    ),
                ),
            ],
            spacing=12,
            scroll=ft.ScrollMode.AUTO,
        ),
    )


def investments_menu_view(on_back, on_my_investments, on_monthly_budget, on_day_trade) -> ft.Control:
    def menu_button(label: str, icon, on_click, accent: str, filled: bool = False) -> ft.Control:
        if filled:
            button = ft.FilledButton(
                label,
                icon=icon,
                height=48,
                on_click=on_click,
                style=ft.ButtonStyle(
                    bgcolor=accent,
                    color="#FFFFFF",
                    shape=ft.RoundedRectangleBorder(radius=8),
                ),
            )
        else:
            button = ft.OutlinedButton(
                label,
                icon=icon,
                height=48,
                on_click=on_click,
                style=ft.ButtonStyle(
                    color=accent,
                    shape=ft.RoundedRectangleBorder(radius=8),
                ),
            )
        return responsive_item(button, xs=12, sm=12, md=12, lg=12)

    return ft.Container(
        expand=True,
        padding=ft.Padding(left=16, top=14, right=16, bottom=20),
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.IconButton(
                            icon=ft.Icons.ARROW_BACK,
                            tooltip="Voltar ao inicio",
                            icon_color="#20242B",
                            bgcolor="#E4DED2",
                            on_click=lambda _event: on_back(),
                        ),
                        ft.Column(
                            [
                                ft.Text("Controle de investimentos", size=22, weight=ft.FontWeight.BOLD),
                                ft.Text("Area logada", size=12, color="#5F6873"),
                            ],
                            spacing=1,
                        ),
                    ],
                    spacing=10,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Container(
                    bgcolor="#FFFFFF",
                    border=ft.Border(
                        top=ft.BorderSide(1, "#D7D0C4"),
                        right=ft.BorderSide(1, "#D7D0C4"),
                        bottom=ft.BorderSide(1, "#D7D0C4"),
                        left=ft.BorderSide(1, "#D7D0C4"),
                    ),
                    border_radius=8,
                    padding=16,
                    content=ft.ResponsiveRow(
                        [
                            menu_button(
                                "Meus investimentos",
                                ft.Icons.ACCOUNT_BALANCE_WALLET,
                                on_my_investments,
                                "#20242B",
                            ),
                            menu_button(
                                "Meu orcamento",
                                ft.Icons.ACCOUNT_BALANCE,
                                on_monthly_budget,
                                "#D97706",
                                filled=True,
                            ),
                            menu_button(
                                "Operacoes day trade",
                                ft.Icons.SHOW_CHART,
                                on_day_trade,
                                "#20242B",
                            ),
                        ],
                        spacing=8,
                        run_spacing=8,
                    ),
                ),
            ],
            spacing=16,
            scroll=ft.ScrollMode.AUTO,
        ),
    )


def fixed_income_product_snapshot(product_name: str, category: str) -> dict[str, str]:
    normalized_name = product_name.casefold()
    normalized_category = category.casefold()
    source_cdb = "Santander - CDB e Renda Fixa / CDB DI"
    source_lci = "Santander - LCI (Letra de Credito Imobiliario)"
    source_funds = "Santander - Oferta de Fundos DI e Renda Fixa"
    source_poupanca = "Santander - CDB ou Poupanca"

    if "poup" in normalized_name:
        return {
            "title": "Caderneta de poupanca Santander",
            "profile": "Produto conservador, simples e com liquidez elevada.",
            "return": "Retorno vinculado a regra da poupanca, com TR e percentual mensal conforme a Selic vigente.",
            "liquidity": "Liquidez diaria, com rendimento creditado pela data de aniversario da aplicacao.",
            "risk": "Baixo risco operacional, indicado para reserva muito conservadora, mas tende a ter retorno menor que alternativas de renda fixa em muitos cenarios.",
            "attention": "Compare com CDBs e fundos DI quando o objetivo for retorno maior mantendo perfil conservador.",
            "source": source_poupanca,
        }
    if "lci" in normalized_name or "lci" in normalized_category:
        return {
            "title": product_name,
            "profile": "Titulo de renda fixa emitido pelo Santander e lastreado em credito imobiliario.",
            "return": "Pode ser prefixado ou pos-fixado. A taxa final deve ser confirmada no momento da aplicacao.",
            "liquidity": "Normalmente exige permanencia ate o vencimento ou prazo minimo de carencia.",
            "risk": "Conta com protecao do FGC dentro dos limites aplicaveis; o principal risco pratico e precisar do dinheiro antes do prazo.",
            "attention": "Para pessoa fisica, a LCI costuma ter isencao de Imposto de Renda, o que melhora a comparacao contra CDBs tributados.",
            "source": source_lci,
        }
    if "lig" in normalized_name or "ipca" in normalized_name:
        return {
            "title": product_name,
            "profile": "Titulo de renda fixa ligado ao mercado imobiliario, adequado para objetivos de prazo maior.",
            "return": "Em produtos IPCA, o retorno tende a combinar inflacao mais taxa contratada, protegendo poder de compra no tempo.",
            "liquidity": "Perfil de medio/longo prazo; liquidez e vencimento devem ser confirmados na oferta vigente.",
            "risk": "Pode sofrer marcacao a mercado antes do vencimento. O investidor deve avaliar prazo, emissor e necessidade de liquidez.",
            "attention": "Bom candidato para objetivos futuros, desde que o prazo combine com a carteira do usuario.",
            "source": "Santander - Renda Fixa e informacoes de investimentos",
        }
    if "referenciado di" in normalized_name or "di" in normalized_name and "fundo" in normalized_category:
        return {
            "title": product_name,
            "profile": "Fundo de renda fixa referenciado DI, voltado a acompanhar a tendencia dos juros de mercado.",
            "return": "Retorno busca acompanhar CDI/Selic, descontadas taxas e tributacao aplicaveis ao fundo.",
            "liquidity": "Liquidez depende do regulamento do fundo e da data de conversao/resgate.",
            "risk": "Fundos nao contam com garantia do FGC. Avalie taxa de administracao, come-cotas e prazo de resgate.",
            "attention": "Serve como alternativa para caixa conservador, mas a rentabilidade liquida deve ser comparada com CDB/LCI.",
            "source": source_funds,
        }
    if "infra" in normalized_name or "inflacao" in normalized_name:
        return {
            "title": product_name,
            "profile": "Fundo de renda fixa/infraestrutura com exposicao a ativos ligados a inflacao.",
            "return": "Retorno tende a depender de juros reais, inflacao e precificacao dos ativos da carteira.",
            "liquidity": "Liquidez e prazo de resgate dependem do regulamento do fundo.",
            "risk": "Pode oscilar mais que um DI simples por efeito de mercado, duration e credito dos emissores.",
            "attention": "Mais adequado para diversificacao e objetivos de prazo maior, nao para caixa imediato.",
            "source": source_funds,
        }
    if "cdb" in normalized_name or "cdb" in normalized_category:
        return {
            "title": product_name,
            "profile": "Titulo de renda fixa emitido pelo Santander para captar recursos do banco.",
            "return": "Pode ser pos-fixado ao CDI, prefixado ou progressivo. A taxa e definida conforme prazo e valor da aplicacao.",
            "liquidity": "No CDB DI, o Santander informa liquidez diaria; em CDB Pre ou outros, confirme prazo e carencia.",
            "risk": "Conta com protecao do FGC dentro dos limites aplicaveis, mas ha risco de mercado em resgate antecipado conforme o produto.",
            "attention": "Boa opcao para perfil conservador quando a taxa liquida supera alternativas como poupanca e fundos DI.",
            "source": source_cdb,
        }
    return {
        "title": product_name,
        "profile": "Investimento de renda fixa cadastrado manualmente.",
        "return": "O retorno depende do indexador, taxa contratada, impostos e prazo informados no documento do produto.",
        "liquidity": "Confirme vencimento, carencia e regras de resgate antes de considerar o ativo como caixa disponivel.",
        "risk": "Avalie emissor, garantia aplicavel, tributacao e possibilidade de marcacao a mercado.",
        "attention": "Cadastre taxa, valor aplicado e vencimento nas proximas etapas para permitir analise de carteira.",
        "source": "Cadastro do usuario e criterios gerais de renda fixa",
    }


def fixed_income_detail_view(product_name: str, category: str, on_back) -> ft.Control:
    snapshot = fixed_income_product_snapshot(product_name, category)

    def info_line(label: str, value: str, icon: str) -> ft.Control:
        return ft.Container(
            bgcolor="#F7F3EB",
            border_radius=8,
            padding=ft.Padding(left=10, top=9, right=10, bottom=9),
            content=ft.Row(
                [
                    ft.Icon(icon, size=18, color="#4F8CFF"),
                    ft.Column(
                        [
                            ft.Text(label, size=10, color="#5F6873", weight=ft.FontWeight.BOLD),
                            ft.Text(value, size=12, color="#20242B"),
                        ],
                        spacing=2,
                        expand=True,
                    ),
                ],
                spacing=8,
                vertical_alignment=ft.CrossAxisAlignment.START,
            ),
        )

    return ft.Container(
        expand=True,
        padding=ft.Padding(left=14, top=14, right=14, bottom=18),
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.IconButton(
                            icon=ft.Icons.ARROW_BACK,
                            tooltip="Voltar aos investimentos",
                            icon_color="#20242B",
                            bgcolor="#E4DED2",
                            on_click=lambda _event: on_back(),
                        ),
                        ft.Column(
                            [
                                ft.Text("Informacoes do ativo", size=20, weight=ft.FontWeight.BOLD),
                                ft.Text("Renda fixa Santander - tela provisoria", size=12, color="#5F6873"),
                            ],
                            spacing=1,
                            expand=True,
                        ),
                    ],
                    spacing=10,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Container(
                    bgcolor="#FFFFFF",
                    border=ft.Border(
                        top=ft.BorderSide(1, "#D7D0C4"),
                        right=ft.BorderSide(1, "#D7D0C4"),
                        bottom=ft.BorderSide(1, "#D7D0C4"),
                        left=ft.BorderSide(1, "#D7D0C4"),
                    ),
                    border_radius=8,
                    padding=16,
                    content=ft.Column(
                        [
                            ft.Row(
                                [
                                    ft.Icon(ft.Icons.ACCOUNT_BALANCE, size=24, color="#167A4B"),
                                    ft.Column(
                                        [
                                            ft.Text(snapshot["title"], size=18, weight=ft.FontWeight.BOLD),
                                            ft.Text(category, size=11, color="#5F6873"),
                                        ],
                                        spacing=2,
                                        expand=True,
                                    ),
                                ],
                                spacing=10,
                                vertical_alignment=ft.CrossAxisAlignment.CENTER,
                            ),
                            info_line("Perfil do produto", snapshot["profile"], ft.Icons.BADGE),
                            info_line("Retorno esperado", snapshot["return"], ft.Icons.TRENDING_UP),
                            info_line("Liquidez e prazo", snapshot["liquidity"], ft.Icons.EVENT_AVAILABLE),
                            info_line("Risco principal", snapshot["risk"], ft.Icons.SHIELD),
                            info_line("Leitura objetiva", snapshot["attention"], ft.Icons.INSIGHTS),
                            ft.Text(
                                f"Fonte-base: {snapshot['source']}. Taxas, disponibilidade e regulamentos devem ser confirmados no Santander antes da decisao de investimento.",
                                size=10,
                                color="#5F6873",
                            ),
                        ],
                        spacing=10,
                    ),
                ),
            ],
            spacing=14,
            scroll=ft.ScrollMode.AUTO,
        ),
    )


def investments_form_view(on_back, page: ft.Page, on_detail, on_my_investments, on_monthly_budget) -> ft.Control:
    ensure_investment_db()
    saved_column = ft.Column(spacing=6)
    save_status = ft.Text("Selecione um ativo da lista para cadastrar no banco de dados.", size=11, color="#5F6873")
    manual_form = ft.Column(visible=False, spacing=7)
    manual_name = investment_text_field("Nome do investimento")
    manual_issuer = investment_text_field("Instituicao")
    manual_category = investment_text_field("Categoria")
    manual_indexer = investment_text_field("Indexador")
    manual_maturity = investment_text_field("Vencimento ou liquidez")
    pending_delete = {"name": ""}

    def current_timestamp() -> str:
        return datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds")

    def normalize_client_record(record: dict[str, str]) -> dict[str, str]:
        name = str(record.get("name", "")).strip()
        return {
            "name": name,
            "issuer": str(record.get("issuer", "Nao informado")).strip() or "Nao informado",
            "category": str(record.get("category", "Investimento")).strip() or "Investimento",
            "indexer": str(record.get("indexer", "Nao informado")).strip() or "Nao informado",
            "maturity": str(record.get("maturity", "Nao informado")).strip() or "Nao informado",
            "source": str(record.get("source", "Cadastro local")).strip() or "Cadastro local",
            "created_at": str(record.get("created_at", current_timestamp())).strip() or current_timestamp(),
        }

    def load_client_investments() -> list[dict[str, str]]:
        try:
            raw_data = page.client_storage.get(CLIENT_INVESTMENTS_KEY)
        except Exception:
            return []
        if not raw_data:
            return []
        try:
            data = json.loads(raw_data) if isinstance(raw_data, str) else raw_data
        except (TypeError, ValueError):
            return []
        if not isinstance(data, list):
            return []
        records: list[dict[str, str]] = []
        for item in data:
            if isinstance(item, dict):
                record = normalize_client_record(item)
                if record["name"]:
                    records.append(record)
        return records

    def write_client_investments(records: list[dict[str, str]]) -> None:
        try:
            page.client_storage.set(CLIENT_INVESTMENTS_KEY, json.dumps(records, ensure_ascii=True))
        except Exception:
            pass

    def save_client_investment(option: dict[str, str]) -> bool:
        records = load_client_investments()
        names = {record["name"].casefold() for record in records}
        if option["name"].casefold() in names:
            return False
        records.insert(
            0,
            normalize_client_record(
                {
                    "name": option["name"],
                    "issuer": option.get("issuer", "Nao informado"),
                    "category": option.get("category", "Investimento"),
                    "indexer": option.get("indexer", "Nao informado"),
                    "maturity": option.get("maturity", "Nao informado"),
                    "source": option.get("source", "Cadastro local"),
                    "created_at": current_timestamp(),
                }
            ),
        )
        write_client_investments(records)
        return True

    def delete_client_investment(product_name: str) -> bool:
        records = load_client_investments()
        remaining = [record for record in records if record["name"].casefold() != product_name.casefold()]
        if len(remaining) == len(records):
            return False
        write_client_investments(remaining)
        return True

    def merged_saved_investments() -> list[tuple[str, str, str]]:
        rows_by_name: dict[str, tuple[str, str, str]] = {}
        for name, category, created_at in load_saved_investments():
            rows_by_name[name.casefold()] = (name, category, created_at)
        for record in reversed(load_client_investments()):
            rows_by_name[record["name"].casefold()] = (
                record["name"],
                record["category"],
                record["created_at"],
            )
        return list(reversed(list(rows_by_name.values())))

    def confirm_delete_investment(product_name: str) -> None:
        removed_from_db = delete_saved_investment(product_name)
        removed_from_browser = delete_client_investment(product_name)
        removed = removed_from_db or removed_from_browser
        pending_delete["name"] = ""
        save_status.value = (
            f"{product_name} excluido com sucesso."
            if removed
            else f"{product_name} nao foi encontrado na lista."
        )
        save_status.color = "#167A4B" if removed else "#8A5B00"
        refresh_saved_list()
        save_status.update()
        saved_column.update()

    def request_delete_investment(product_name: str) -> None:
        pending_delete["name"] = product_name
        save_status.value = f"Confirme a exclusao de {product_name}."
        save_status.color = "#8A5B00"
        refresh_saved_list()
        save_status.update()
        saved_column.update()

    def cancel_delete_investment() -> None:
        pending_delete["name"] = ""
        save_status.value = "Exclusao cancelada."
        save_status.color = "#5F6873"
        refresh_saved_list()
        save_status.update()
        saved_column.update()

    def saved_investment_card(name: str, category: str, created_at: str) -> ft.Control:
        return ft.Container(
            bgcolor="#F7F3EB",
            border=ft.Border(
                top=ft.BorderSide(1, "#D7D0C4"),
                right=ft.BorderSide(1, "#D7D0C4"),
                bottom=ft.BorderSide(1, "#D7D0C4"),
                left=ft.BorderSide(1, "#D7D0C4"),
            ),
            border_radius=8,
            padding=ft.Padding(left=10, top=7, right=10, bottom=7),
            content=ft.Column(
                [
                    ft.Row(
                        [
                            ft.Icon(ft.Icons.CHECK_CIRCLE, size=16, color="#167A4B"),
                            ft.Column(
                                [
                                    ft.Text(name, size=12, weight=ft.FontWeight.BOLD),
                                    ft.Text(f"{category} | cadastrado em {created_at[:10]}", size=10, color="#5F6873"),
                                ],
                                spacing=1,
                                expand=True,
                            ),
                            ft.IconButton(
                                icon=ft.Icons.DELETE_OUTLINE,
                                tooltip="Excluir investimento",
                                icon_color="#B42332",
                                on_click=lambda _event, selected=name: request_delete_investment(selected),
                            ),
                        ],
                        spacing=8,
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                    ft.Container(
                        visible=pending_delete["name"].casefold() == name.casefold(),
                        bgcolor="#FCE8E9",
                        border_radius=8,
                        padding=ft.Padding(left=10, top=8, right=10, bottom=8),
                        content=ft.Column(
                            [
                                ft.Text("Confirmar exclusao deste investimento?", size=11, color="#8A5B00"),
                                ft.Row(
                                    [
                                        ft.TextButton(
                                            "Cancelar",
                                            on_click=lambda _event: cancel_delete_investment(),
                                        ),
                                        ft.FilledButton(
                                            "Excluir",
                                            icon=ft.Icons.DELETE,
                                            on_click=lambda _event, selected=name: confirm_delete_investment(selected),
                                            style=ft.ButtonStyle(bgcolor="#B94A48", color="#F8FAFC"),
                                        ),
                                    ],
                                    spacing=8,
                                    alignment=ft.MainAxisAlignment.END,
                                ),
                            ],
                            spacing=6,
                        ),
                    ),
                ],
                spacing=8,
            ),
        )

    def refresh_saved_list() -> None:
        rows = merged_saved_investments()
        if not rows:
            saved_column.controls = [
                ft.Text("Nenhum investimento cadastrado ainda.", size=11, color="#5F6873")
            ]
            return
        saved_column.controls = [saved_investment_card(name, category, created_at) for name, category, created_at in rows]

    def register_investment(option: dict[str, str]) -> None:
        inserted_in_db = save_investment_option(option)
        inserted_in_browser = save_client_investment(option)
        inserted = inserted_in_db or inserted_in_browser
        save_status.value = (
            f"{option['name']} cadastrado com sucesso."
            if inserted
            else f"{option['name']} ja estava cadastrado."
        )
        save_status.color = "#167A4B" if inserted else "#8A5B00"
        refresh_saved_list()
        save_status.update()
        saved_column.update()

    def focus_investment_list(_event=None) -> None:
        manual_form.visible = True
        save_status.value = "Preencha os dados do novo investimento e clique em salvar."
        save_status.color = "#4F8CFF"
        save_status.update()
        manual_form.update()

    def show_day_trade_operations(_event=None) -> None:
        save_status.value = "Modulo de operacoes day trade em preparacao."
        save_status.color = "#8A5B00"
        save_status.update()

    def clear_manual_form() -> None:
        manual_name.value = ""
        manual_issuer.value = ""
        manual_category.value = ""
        manual_indexer.value = ""
        manual_maturity.value = ""

    def save_manual_investment(_event=None) -> None:
        name = manual_name.value.strip()
        if not name:
            save_status.value = "Informe o nome do investimento."
            save_status.color = "#B42332"
            save_status.update()
            return
        option = {
            "name": name,
            "issuer": manual_issuer.value.strip() or "Nao informado",
            "category": manual_category.value.strip() or "Investimento",
            "indexer": manual_indexer.value.strip() or "Nao informado",
            "maturity": manual_maturity.value.strip() or "Nao informado",
            "source": "Cadastro manual",
        }
        inserted_in_db = save_investment_option(option)
        inserted_in_browser = save_client_investment(option)
        inserted = inserted_in_db or inserted_in_browser
        save_status.value = "Salvo com sucesso" if inserted else f"{option['name']} ja estava cadastrado."
        save_status.color = "#167A4B" if inserted else "#8A5B00"
        if inserted:
            clear_manual_form()
            manual_form.visible = False
        refresh_saved_list()
        save_status.update()
        saved_column.update()
        manual_form.update()

    def santander_option_card(option: dict[str, str]) -> ft.Control:
        return ft.Container(
            bgcolor="#FFFFFF",
            border=ft.Border(
                top=ft.BorderSide(1, "#D7D0C4"),
                right=ft.BorderSide(1, "#D7D0C4"),
                bottom=ft.BorderSide(1, "#D7D0C4"),
                left=ft.BorderSide(1, "#D7D0C4"),
            ),
            border_radius=8,
            padding=12,
            ink=True,
            on_click=lambda _event, selected=option: register_investment(selected),
            content=ft.Column(
                [
                    ft.Row(
                        [
                            ft.Icon(ft.Icons.ADD_CIRCLE, size=18, color="#4F8CFF"),
                            ft.Text(option["name"], size=13, weight=ft.FontWeight.BOLD, expand=True),
                            ft.IconButton(
                                icon=ft.Icons.INFO_OUTLINE,
                                tooltip="Ver informacoes do ativo",
                                icon_color="#4F8CFF",
                                on_click=lambda _event, selected=option: on_detail(
                                    selected["name"],
                                    selected["category"],
                                ),
                            ),
                        ],
                        spacing=8,
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                    ft.Text(
                        f"{option['category']} | {option['indexer']} | {option['maturity']}",
                        size=11,
                        color="#374151",
                    ),
                    ft.Text(option["issuer"], size=10, color="#5F6873"),
                ],
                spacing=4,
            ),
        )

    manual_form.controls = [
        manual_name,
        manual_issuer,
        manual_category,
        manual_indexer,
        manual_maturity,
        ft.FilledButton(
            "Salvar investimento",
            icon=ft.Icons.SAVE,
            on_click=save_manual_investment,
            style=ft.ButtonStyle(bgcolor="#3E8E7E", color="#F8FAFC"),
        ),
    ]

    refresh_saved_list()
    return ft.Container(
        expand=True,
        padding=ft.Padding(left=14, top=14, right=14, bottom=18),
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.IconButton(
                            icon=ft.Icons.ARROW_BACK,
                            tooltip="Voltar ao inicio",
                            icon_color="#20242B",
                            bgcolor="#E4DED2",
                            on_click=lambda _event: on_back(),
                        ),
                        ft.Column(
                            [
                                ft.Text("Controle de investimentos", size=22, weight=ft.FontWeight.BOLD),
                                ft.Text("Formulario inicial", size=12, color="#5F6873"),
                            ],
                            spacing=1,
                        ),
                    ],
                    spacing=10,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Container(
                    bgcolor="#FFFFFF",
                    border=ft.Border(
                        top=ft.BorderSide(1, "#D7D0C4"),
                        right=ft.BorderSide(1, "#D7D0C4"),
                        bottom=ft.BorderSide(1, "#D7D0C4"),
                        left=ft.BorderSide(1, "#D7D0C4"),
                    ),
                    border_radius=8,
                    padding=16,
                    content=ft.Column(
                        [
                            ft.Text("ok . passou", size=14, color="#167A4B", weight=ft.FontWeight.BOLD),
                            ft.ResponsiveRow(
                                [
                                    responsive_item(
                                        ft.OutlinedButton(
                                            "Meus investimentos",
                                            icon=ft.Icons.ACCOUNT_BALANCE_WALLET,
                                            on_click=on_my_investments,
                                            style=ft.ButtonStyle(color="#20242B"),
                                        ),
                                        xs=12,
                                        sm=4,
                                        md=4,
                                        lg=4,
                                    ),
                                    responsive_item(
                                        ft.FilledButton(
                                            "Meu orcamento",
                                            icon=ft.Icons.ACCOUNT_BALANCE,
                                            on_click=on_monthly_budget,
                                            style=ft.ButtonStyle(
                                                bgcolor="#D97706",
                                                color="#FFFFFF",
                                                shape=ft.RoundedRectangleBorder(radius=8),
                                            ),
                                        ),
                                        xs=12,
                                        sm=4,
                                        md=4,
                                        lg=4,
                                    ),
                                    responsive_item(
                                        ft.OutlinedButton(
                                            "Operacoes day trade",
                                            icon=ft.Icons.SHOW_CHART,
                                            on_click=show_day_trade_operations,
                                            style=ft.ButtonStyle(color="#20242B"),
                                        ),
                                        xs=12,
                                        sm=4,
                                        md=4,
                                        lg=4,
                                    ),
                                ],
                                spacing=8,
                                run_spacing=8,
                            ),
                            ft.ResponsiveRow(
                                [
                                    responsive_item(
                                        ft.Container(
                                            bgcolor="#F7F3EB",
                                            border_radius=8,
                                            padding=12,
                                            content=ft.Column(
                                                [
                                                    ft.FilledButton(
                                                        "Adicionar ativo",
                                                        icon=ft.Icons.ADD,
                                                        on_click=focus_investment_list,
                                                        style=ft.ButtonStyle(bgcolor="#4F8CFF", color="#F8FAFC"),
                                                    ),
                                                    manual_form,
                                                    save_status,
                                                    ft.Text("Renda fixa Santander", size=15, weight=ft.FontWeight.BOLD),
                                                    ft.Text(
                                                        "Clique em um ativo para cadastrar. Taxas e disponibilidade devem ser confirmadas no Santander.",
                                                        size=11,
                                                        color="#5F6873",
                                                    ),
                                                    ft.Column(
                                                        [santander_option_card(option) for option in SANTANDER_FIXED_INCOME_OPTIONS],
                                                        spacing=8,
                                                    ),
                                                ],
                                                spacing=10,
                                            ),
                                        ),
                                        xs=12,
                                        sm=12,
                                        md=6,
                                        lg=6,
                                    ),
                                    responsive_item(
                                        ft.Container(
                                            bgcolor="#F7F3EB",
                                            border_radius=8,
                                            padding=12,
                                            content=ft.Column(
                                                [
                                                    ft.Text("Minha Carteira", size=15, weight=ft.FontWeight.BOLD),
                                                    saved_column,
                                                ],
                                                spacing=10,
                                            ),
                                        ),
                                        xs=12,
                                        sm=12,
                                        md=6,
                                        lg=6,
                                    ),
                                ],
                                spacing=10,
                                run_spacing=10,
                            ),
                        ],
                        spacing=11,
                    ),
                ),
            ],
            spacing=16,
            scroll=ft.ScrollMode.AUTO,
        ),
    )


def my_investments_view(on_back, page: ft.Page) -> ft.Control:
    amount_fields: dict[str, ft.TextField] = {}
    status = ft.Text(
        "Informe o valor aplicado em cada ativo e clique em salvar.",
        size=10,
        color="#5F6873",
    )
    total_text = ft.Text("R$ 0,00", size=20, weight=ft.FontWeight.BOLD, color="#167A4B")

    def current_timestamp() -> str:
        return datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds")

    def normalize_client_record(record: dict[str, str]) -> dict[str, str]:
        return {
            "name": str(record.get("name", "")).strip(),
            "category": str(record.get("category", "Investimento")).strip() or "Investimento",
            "created_at": str(record.get("created_at", current_timestamp())).strip() or current_timestamp(),
        }

    def load_client_investments() -> list[dict[str, str]]:
        try:
            raw_data = page.client_storage.get(CLIENT_INVESTMENTS_KEY)
        except Exception:
            return []
        if not raw_data:
            return []
        try:
            data = json.loads(raw_data) if isinstance(raw_data, str) else raw_data
        except (TypeError, ValueError):
            return []
        if not isinstance(data, list):
            return []
        return [
            normalize_client_record(item)
            for item in data
            if isinstance(item, dict) and str(item.get("name", "")).strip()
        ]

    def merged_investments() -> list[tuple[str, str, str]]:
        rows_by_name: dict[str, tuple[str, str, str]] = {}
        for name, category, created_at in load_saved_investments():
            rows_by_name[name.casefold()] = (name, category, created_at)
        for record in reversed(load_client_investments()):
            rows_by_name[record["name"].casefold()] = (
                record["name"],
                record["category"],
                record["created_at"],
            )
        return list(reversed(list(rows_by_name.values())))

    def parse_currency(value: str) -> float:
        cleaned = value.strip().replace("R$", "").replace(" ", "")
        if not cleaned:
            return 0.0
        if "," in cleaned:
            cleaned = cleaned.replace(".", "").replace(",", ".")
        try:
            return max(float(cleaned), 0.0)
        except ValueError:
            raise ValueError("Valor invalido")

    def format_currency(value: float) -> str:
        formatted = f"{value:,.2f}"
        return f"R$ {formatted.replace(',', 'X').replace('.', ',').replace('X', '.')}"

    def load_amounts() -> dict[str, float]:
        try:
            raw_data = page.client_storage.get(CLIENT_INVESTMENT_AMOUNTS_KEY)
        except Exception:
            return {}
        if not raw_data:
            return {}
        try:
            data = json.loads(raw_data) if isinstance(raw_data, str) else raw_data
        except (TypeError, ValueError):
            return {}
        if not isinstance(data, dict):
            return {}
        amounts: dict[str, float] = {}
        for name, amount in data.items():
            try:
                amounts[str(name).casefold()] = max(float(amount), 0.0)
            except (TypeError, ValueError):
                continue
        return amounts

    def update_total(amounts: dict[str, float]) -> None:
        total_text.value = format_currency(sum(amounts.values()))

    saved_amounts = load_amounts()

    def save_amounts(_event=None) -> None:
        amounts: dict[str, float] = {}
        invalid_names: list[str] = []
        for name, field in amount_fields.items():
            try:
                amounts[name.casefold()] = parse_currency(field.value or "")
            except ValueError:
                invalid_names.append(name)
        if invalid_names:
            status.value = f"Revise o valor informado para: {', '.join(invalid_names)}."
            status.color = "#B42332"
            status.update()
            return
        try:
            page.client_storage.set(
                CLIENT_INVESTMENT_AMOUNTS_KEY,
                json.dumps(amounts, ensure_ascii=True),
            )
        except Exception:
            status.value = "Nao foi possivel salvar os valores neste dispositivo."
            status.color = "#B42332"
            status.update()
            return
        update_total(amounts)
        status.value = "Valores aplicados salvos com sucesso."
        status.color = "#167A4B"
        total_text.update()
        status.update()

    def investment_amount_card(name: str, category: str, created_at: str) -> ft.Control:
        amount = saved_amounts.get(name.casefold(), 0.0)
        amount_field = ft.TextField(
            value="" if amount == 0 else format_currency(amount).replace("R$ ", ""),
            prefix_text="R$ ",
            hint_text="0,00",
            dense=True,
            height=40,
            text_size=12,
            keyboard_type=ft.KeyboardType.NUMBER,
            border_color="#C7BEAF",
            focused_border_color="#4F8CFF",
            border_radius=7,
            bgcolor="#FFFFFF",
            color="#20242B",
            cursor_color="#4F8CFF",
            content_padding=ft.Padding(left=10, top=0, right=10, bottom=0),
            on_submit=save_amounts,
        )
        amount_fields[name] = amount_field
        return ft.Container(
            col={"xs": 12, "sm": 6, "md": 6, "lg": 6},
            bgcolor="#FFFFFF",
            border=ft.Border(
                top=ft.BorderSide(1, "#D7D0C4"),
                right=ft.BorderSide(1, "#D7D0C4"),
                bottom=ft.BorderSide(1, "#D7D0C4"),
                left=ft.BorderSide(1, "#D7D0C4"),
            ),
            border_radius=8,
            padding=ft.Padding(left=11, top=10, right=11, bottom=10),
            content=ft.Column(
                [
                    ft.Row(
                        [
                            ft.Container(
                                width=28,
                                height=28,
                                border_radius=7,
                                bgcolor="#EEF4FF",
                                alignment=ft.Alignment(0, 0),
                                content=ft.Icon(
                                    ft.Icons.ACCOUNT_BALANCE_WALLET_OUTLINED,
                                    size=15,
                                    color="#4F8CFF",
                                ),
                            ),
                            ft.Column(
                                [
                                    ft.Text(
                                        name,
                                        size=12,
                                        weight=ft.FontWeight.BOLD,
                                        max_lines=1,
                                        overflow=ft.TextOverflow.ELLIPSIS,
                                    ),
                                    ft.Text(
                                        f"{category} | {created_at[:10]}",
                                        size=9,
                                        color="#5F6873",
                                    ),
                                ],
                                spacing=1,
                                expand=True,
                            ),
                        ],
                        spacing=8,
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                    ft.Column(
                        [
                            ft.Text("Valor aplicado", size=9, color="#5F6873"),
                            amount_field,
                        ],
                        spacing=3,
                    ),
                ],
                spacing=7,
            ),
        )

    rows = merged_investments()
    update_total(saved_amounts)
    portfolio_controls = (
        [investment_amount_card(name, category, created_at) for name, category, created_at in rows]
        if rows
        else [
            ft.Container(
                col=12,
                bgcolor="#F7F3EB",
                border_radius=8,
                padding=16,
                content=ft.Column(
                    [
                        ft.Icon(ft.Icons.INBOX_OUTLINED, size=26, color="#5F6873"),
                        ft.Text("Nenhum ativo cadastrado em Minha Carteira.", size=11, color="#5F6873"),
                    ],
                    horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                    spacing=6,
                ),
            )
        ]
    )

    portfolio_panel = ft.Container(
        bgcolor="#F7F3EB",
        border_radius=10,
        padding=12,
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.Column(
                            [
                                ft.Text("Ativos da carteira", size=14, weight=ft.FontWeight.BOLD),
                                ft.Text(
                                    f"{len(rows)} ativo{'s' if len(rows) != 1 else ''} cadastrado{'s' if len(rows) != 1 else ''}",
                                    size=9,
                                    color="#5F6873",
                                ),
                            ],
                            spacing=1,
                            expand=True,
                        ),
                        ft.Icon(ft.Icons.ACCOUNT_BALANCE_WALLET_OUTLINED, size=19, color="#4F8CFF"),
                    ],
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.ResponsiveRow(
                    portfolio_controls,
                    spacing=8,
                    run_spacing=8,
                ),
                ft.ResponsiveRow(
                    [
                        responsive_item(status, xs=12, sm=7, md=7, lg=7),
                        responsive_item(
                            ft.FilledButton(
                                "Salvar valores",
                                icon=ft.Icons.SAVE_OUTLINED,
                                height=38,
                                disabled=not rows,
                                on_click=save_amounts,
                                style=ft.ButtonStyle(
                                    bgcolor="#4F8CFF",
                                    color="#F8FAFC",
                                    shape=ft.RoundedRectangleBorder(radius=7),
                                ),
                            ),
                            xs=12,
                            sm=5,
                            md=5,
                            lg=5,
                        ),
                    ],
                    spacing=8,
                    run_spacing=8,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
            ],
            spacing=10,
        ),
    )

    future_panel = ft.Container(
        bgcolor="#FFFFFF",
        border=ft.Border(
            top=ft.BorderSide(1, "#D7D0C4"),
            right=ft.BorderSide(1, "#D7D0C4"),
            bottom=ft.BorderSide(1, "#D7D0C4"),
            left=ft.BorderSide(1, "#D7D0C4"),
        ),
        border_radius=10,
        padding=14,
        content=ft.Column(
            [
                ft.Container(
                    width=34,
                    height=34,
                    border_radius=8,
                    bgcolor="#F2ECFF",
                    alignment=ft.Alignment(0, 0),
                    content=ft.Icon(ft.Icons.INSIGHTS_OUTLINED, size=18, color="#8B5CF6"),
                ),
                ft.Text("Proximos recursos", size=13, weight=ft.FontWeight.BOLD),
                ft.Text(
                    "Area reservada para rentabilidade, distribuicao da carteira e acompanhamento de metas.",
                    size=10,
                    color="#5F6873",
                ),
                ft.Container(
                    height=70,
                    border_radius=8,
                    bgcolor="#F7F3EB",
                    alignment=ft.Alignment(0, 0),
                    content=ft.Text("Em desenvolvimento", size=10, color="#8A8175"),
                ),
            ],
            spacing=9,
        ),
    )

    return ft.Container(
        expand=True,
        padding=ft.Padding(left=14, top=14, right=14, bottom=18),
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.IconButton(
                            icon=ft.Icons.ARROW_BACK,
                            tooltip="Voltar ao controle de investimentos",
                            icon_color="#20242B",
                            bgcolor="#E4DED2",
                            on_click=lambda _event: on_back(),
                        ),
                        ft.Column(
                            [
                                ft.Text("Meus investimentos", size=20, weight=ft.FontWeight.BOLD),
                                ft.Text(
                                    "Valores aplicados nos ativos da Minha Carteira",
                                    size=11,
                                    color="#5F6873",
                                ),
                            ],
                            spacing=1,
                        ),
                    ],
                    spacing=10,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.ResponsiveRow(
                    [
                        responsive_item(
                            ft.Container(
                                bgcolor="#FFFFFF",
                                border=ft.Border(
                                    top=ft.BorderSide(1, "#D7D0C4"),
                                    right=ft.BorderSide(1, "#D7D0C4"),
                                    bottom=ft.BorderSide(1, "#D7D0C4"),
                                    left=ft.BorderSide(4, "#167A4B"),
                                ),
                                border_radius=9,
                                padding=ft.Padding(left=14, top=10, right=14, bottom=10),
                                content=ft.Row(
                                    [
                                        ft.Column(
                                            [
                                                ft.Text("Total aplicado", size=9, color="#5F6873"),
                                                total_text,
                                            ],
                                            spacing=0,
                                            expand=True,
                                        ),
                                        ft.Icon(ft.Icons.PAID_OUTLINED, size=22, color="#167A4B"),
                                    ],
                                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                                ),
                            ),
                            xs=12,
                            sm=6,
                            md=4,
                            lg=3,
                        ),
                        responsive_item(
                            ft.Container(
                                bgcolor="#FFFFFF",
                                border=ft.Border(
                                    top=ft.BorderSide(1, "#D7D0C4"),
                                    right=ft.BorderSide(1, "#D7D0C4"),
                                    bottom=ft.BorderSide(1, "#D7D0C4"),
                                    left=ft.BorderSide(1, "#D7D0C4"),
                                ),
                                border_radius=9,
                                padding=ft.Padding(left=14, top=10, right=14, bottom=10),
                                content=ft.Row(
                                    [
                                        ft.Column(
                                            [
                                                ft.Text("Ativos cadastrados", size=9, color="#5F6873"),
                                                ft.Text(
                                                    str(len(rows)),
                                                    size=20,
                                                    weight=ft.FontWeight.BOLD,
                                                    color="#20242B",
                                                ),
                                            ],
                                            spacing=0,
                                            expand=True,
                                        ),
                                        ft.Icon(ft.Icons.INVENTORY_2_OUTLINED, size=21, color="#4F8CFF"),
                                    ],
                                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                                ),
                            ),
                            xs=12,
                            sm=6,
                            md=4,
                            lg=3,
                        ),
                    ],
                    spacing=8,
                    run_spacing=8,
                ),
                ft.ResponsiveRow(
                    [
                        responsive_item(portfolio_panel, xs=12, sm=12, md=8, lg=8),
                        responsive_item(future_panel, xs=12, sm=12, md=4, lg=4),
                    ],
                    spacing=10,
                    run_spacing=10,
                    vertical_alignment=ft.CrossAxisAlignment.START,
                ),
            ],
            spacing=10,
            scroll=ft.ScrollMode.AUTO,
        ),
    )


def day_trade_operations_view(on_back) -> ft.Control:
    return ft.Container(
        expand=True,
        padding=ft.Padding(left=16, top=14, right=16, bottom=20),
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.IconButton(
                            icon=ft.Icons.ARROW_BACK,
                            tooltip="Voltar ao menu de investimentos",
                            icon_color="#20242B",
                            bgcolor="#E4DED2",
                            on_click=lambda _event: on_back(),
                        ),
                        ft.Column(
                            [
                                ft.Text("Operacoes day trade", size=22, weight=ft.FontWeight.BOLD),
                                ft.Text("Modulo separado da area logada", size=12, color="#5F6873"),
                            ],
                            spacing=1,
                        ),
                    ],
                    spacing=10,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Container(
                    bgcolor="#FFFFFF",
                    border=ft.Border(
                        top=ft.BorderSide(1, "#D7D0C4"),
                        right=ft.BorderSide(1, "#D7D0C4"),
                        bottom=ft.BorderSide(1, "#D7D0C4"),
                        left=ft.BorderSide(4, "#D97706"),
                    ),
                    border_radius=8,
                    padding=16,
                    content=ft.Column(
                        [
                            ft.Icon(ft.Icons.SHOW_CHART, size=30, color="#D97706"),
                            ft.Text("Modulo de operacoes day trade em preparacao.", size=14, weight=ft.FontWeight.BOLD),
                        ],
                        spacing=8,
                    ),
                ),
            ],
            spacing=16,
            scroll=ft.ScrollMode.AUTO,
        ),
    )


def monthly_budget_simple_view(on_back, page: ft.Page) -> ft.Control:
    ensure_monthly_budget_db()
    now = datetime.now(ZoneInfo("America/Sao_Paulo"))
    current_year = now.year
    current_month = now.strftime("%Y-%m")
    month_names = [
        "Janeiro",
        "Fevereiro",
        "Marco",
        "Abril",
        "Maio",
        "Junho",
        "Julho",
        "Agosto",
        "Setembro",
        "Outubro",
        "Novembro",
        "Dezembro",
    ]
    month_values = [f"{current_year}-{month_number:02d}" for month_number in range(1, 13)]

    month_field = ft.Dropdown(
        label="Mes de referencia",
        value=current_month,
        dense=True,
        text_size=10,
        border_color="#C7BEAF",
        focused_border_color="#D97706",
        fill_color="#FFFFFF",
        filled=True,
        color="#20242B",
        border_radius=6,
        content_padding=ft.Padding(left=7, top=0, right=7, bottom=0),
        options=[
            ft.DropdownOption(key=month_value, text=month_name)
            for month_value, month_name in zip(month_values, month_names)
        ],
    )
    type_dropdown = ft.Dropdown(
        label="Tipo",
        value="Despesa",
        dense=True,
        text_size=10,
        border_color="#C7BEAF",
        focused_border_color="#D97706",
        fill_color="#FFFFFF",
        filled=True,
        color="#20242B",
        border_radius=6,
        content_padding=ft.Padding(left=7, top=0, right=7, bottom=0),
        options=[
            ft.DropdownOption(key="Receita", text="Receita"),
            ft.DropdownOption(key="Despesa", text="Despesa"),
        ],
    )
    description_field = investment_text_field("Descricao")
    amount_field = investment_text_field("Valor")
    amount_field.prefix_text = "R$ "
    amount_field.hint_text = "0,00"
    amount_field.keyboard_type = ft.KeyboardType.TEXT
    due_date_field = investment_text_field("Vencimento / data")
    due_date_field.hint_text = "dd/mm/aaaa"
    due_date_field.keyboard_type = ft.KeyboardType.NUMBER
    payment_date_field = investment_text_field("Data do pagamento")
    payment_date_field.hint_text = "dd/mm/aaaa"
    payment_date_field.keyboard_type = ft.KeyboardType.NUMBER
    settled_checkbox = ft.Checkbox(label="Pago", value=False)
    for budget_text_field in [description_field, amount_field, due_date_field, payment_date_field]:
        budget_text_field.height = 32
        budget_text_field.text_size = 10
        budget_text_field.content_padding = ft.Padding(left=7, top=0, right=7, bottom=0)
    form_title = ft.Text("Novo lancamento", size=11, weight=ft.FontWeight.BOLD)
    status = ft.Text("Cadastre receita ou despesa.", size=10, color="#5F6873")
    items_column = ft.ListView(spacing=6, expand=True, padding=0)
    editing_item_id: int | None = None
    editing_original_month: str | None = None

    revenue_total_text = ft.Text("R$ 0,00", size=14, weight=ft.FontWeight.BOLD, color="#167A4B")
    expense_total_text = ft.Text("R$ 0,00", size=14, weight=ft.FontWeight.BOLD, color="#B42332")
    balance_total_text = ft.Text("R$ 0,00", size=14, weight=ft.FontWeight.BOLD, color="#20242B")
    pending_total_text = ft.Text("R$ 0,00", size=14, weight=ft.FontWeight.BOLD, color="#D97706")
    report_month_field = ft.Dropdown(
        value=current_month,
        dense=True,
        text_size=9,
        border_color="#C7BEAF",
        focused_border_color="#D97706",
        fill_color="#FFFFFF",
        filled=True,
        color="#20242B",
        border_radius=5,
        content_padding=ft.Padding(left=6, top=0, right=6, bottom=0),
        options=[
            ft.DropdownOption(key="__all__", text="Todos")
        ]
        + [
            ft.DropdownOption(key=month_value, text=month_name)
            for month_value, month_name in zip(month_values, month_names)
        ],
    )
    report_description_field = investment_text_field("Buscar")
    report_description_field.height = 28
    report_description_field.text_size = 9
    report_description_field.content_padding = ft.Padding(left=6, top=0, right=6, bottom=0)
    report_status_dropdown = ft.Dropdown(
        value="Todos",
        dense=True,
        text_size=9,
        border_color="#C7BEAF",
        focused_border_color="#D97706",
        fill_color="#FFFFFF",
        filled=True,
        color="#20242B",
        border_radius=5,
        content_padding=ft.Padding(left=6, top=0, right=6, bottom=0),
        options=[
            ft.DropdownOption(key="Todos", text="Todos"),
            ft.DropdownOption(key="Pago", text="Pago / recebido"),
            ft.DropdownOption(key="Nao pago", text="Nao pago / nao recebido"),
        ],
    )
    report_type_dropdown = ft.Dropdown(
        value="Todos",
        dense=True,
        text_size=9,
        border_color="#C7BEAF",
        focused_border_color="#D97706",
        fill_color="#FFFFFF",
        filled=True,
        color="#20242B",
        border_radius=5,
        content_padding=ft.Padding(left=6, top=0, right=6, bottom=0),
        options=[
            ft.DropdownOption(key="Todos", text="Receitas e despesas"),
            ft.DropdownOption(key="Despesa", text="Apenas despesas"),
            ft.DropdownOption(key="Receita", text="Apenas receitas"),
        ],
    )
    report_status_text = ft.Text("", size=10, color="#5F6873")

    def compact_report_filter(control: ft.Control) -> ft.Control:
        return ft.Container(height=28, content=control)

    def report_filter_group(title: str, control: ft.Control, accent: str = "#4F8CFF") -> ft.Control:
        return ft.Container(
            bgcolor="#F8FAFC",
            border=ft.Border(
                top=ft.BorderSide(1, "#D7D0C4"),
                right=ft.BorderSide(1, "#D7D0C4"),
                bottom=ft.BorderSide(1, "#D7D0C4"),
                left=ft.BorderSide(2, accent),
            ),
            border_radius=5,
            padding=ft.Padding(left=5, top=2, right=5, bottom=3),
            content=ft.Column(
                [
                    ft.Text(title.upper(), size=7, weight=ft.FontWeight.BOLD, color="#5F6873"),
                    compact_report_filter(control),
                ],
                spacing=1,
            ),
        )

    def format_currency(value: float) -> str:
        formatted = f"{value:,.2f}"
        return f"R$ {formatted.replace(',', 'X').replace('.', ',').replace('X', '.')}"

    def parse_currency(value: str) -> float:
        cleaned = value.strip().replace("R$", "").replace(" ", "")
        if not cleaned:
            return 0.0
        if "," in cleaned:
            cleaned = cleaned.replace(".", "").replace(",", ".")
        try:
            return max(float(cleaned), 0.0)
        except ValueError as exc:
            raise ValueError("Informe um valor valido.") from exc

    def normalize_date(value: str) -> str:
        cleaned = value.strip()
        try:
            parsed = datetime.strptime(cleaned, "%d/%m/%Y")
        except ValueError as exc:
            raise ValueError("Informe a data no formato dd/mm/aaaa.") from exc
        return parsed.strftime("%Y-%m-%d")

    def format_brazilian_date(value: str) -> str:
        digits = "".join(character for character in value if character.isdigit())[:8]
        if len(digits) <= 2:
            return digits
        if len(digits) <= 4:
            return f"{digits[:2]}/{digits[2:]}"
        return f"{digits[:2]}/{digits[2:4]}/{digits[4:]}"

    def apply_due_date_mask(event=None) -> None:
        formatted = format_brazilian_date(due_date_field.value or "")
        if due_date_field.value != formatted:
            due_date_field.value = formatted
            due_date_field.update()

    def apply_payment_date_mask(event=None) -> None:
        formatted = format_brazilian_date(payment_date_field.value or "")
        if payment_date_field.value != formatted:
            payment_date_field.value = formatted
            payment_date_field.update()

    def apply_amount_limit(event=None) -> None:
        raw_value = amount_field.value or ""
        allowed_value = "".join(
            character for character in raw_value if character.isdigit() or character in {",", "."}
        )
        last_separator = max(allowed_value.rfind(","), allowed_value.rfind("."))
        if last_separator >= 0:
            whole_digits = "".join(character for character in allowed_value[:last_separator] if character.isdigit())
            decimal_digits = "".join(character for character in allowed_value[last_separator + 1 :] if character.isdigit())[:2]
            formatted = f"{whole_digits},{decimal_digits}" if whole_digits or decimal_digits else ""
        else:
            formatted = "".join(character for character in allowed_value if character.isdigit())
        if amount_field.value != formatted:
            amount_field.value = formatted
            amount_field.update()

    def finalize_amount_field(event=None) -> None:
        try:
            amount = parse_currency(amount_field.value or "")
        except ValueError:
            return
        if amount <= 0:
            return
        formatted = format_currency(amount).replace("R$ ", "")
        if amount_field.value != formatted:
            amount_field.value = formatted
            amount_field.update()

    def uppercase_description(event=None) -> None:
        upper_value = (description_field.value or "").upper()[:15]
        if description_field.value != upper_value:
            description_field.value = upper_value
            description_field.update()

    def uppercase_report_description(event=None) -> None:
        upper_value = (report_description_field.value or "").upper()[:15]
        if report_description_field.value != upper_value:
            report_description_field.value = upper_value
            report_description_field.update()

    def selected_month() -> str:
        value = month_field.value or current_month
        if value not in month_values:
            raise ValueError("Escolha um mes de referencia.")
        return value

    def month_display(value: str) -> str:
        try:
            month_number = int(value.split("-")[1])
        except (IndexError, ValueError):
            return value
        if 1 <= month_number <= len(month_names):
            return f"{month_names[month_number - 1]} {value[:4]}"
        return value

    def date_display(value: object) -> str:
        text = str(value)
        try:
            return datetime.strptime(text, "%Y-%m-%d").strftime("%d/%m/%Y")
        except ValueError:
            return text

    def status_label(item: dict[str, object]) -> str:
        if item["item_type"] == "Receita":
            return "Recebido" if item["settled"] else "Nao recebido"
        return "Pago" if item["settled"] else "Falta pagar"

    def set_status(message: str, color: str = "#5F6873") -> None:
        status.value = message
        status.color = color

    def clear_budget_form() -> None:
        nonlocal editing_item_id, editing_original_month
        editing_item_id = None
        editing_original_month = None
        form_title.value = "Novo lancamento"
        description_field.value = ""
        amount_field.value = ""
        due_date_field.value = ""
        payment_date_field.value = ""
        settled_checkbox.value = False
        save_button.text = "Salvar"
        save_button.icon = ft.Icons.SAVE_OUTLINED
        cancel_edit_button.visible = False

    def client_budget_storage_key(month: str) -> str:
        return f"{CLIENT_MONTHLY_BUDGET_KEY}.{month}"

    def normalize_budget_record(item: dict[str, object]) -> dict[str, object]:
        return {
            "id": int(item.get("id") or 0),
            "item_type": str(item.get("item_type") or "Despesa"),
            "description": str(item.get("description") or "").strip().upper()[:15],
            "amount_text": str(item.get("amount_text") or "0,00"),
            "due_date": str(item.get("due_date") or "")[:10],
            "payment_date": str(item.get("payment_date") or "")[:10],
            "settled": bool(item.get("settled")),
            "created_at": str(item.get("created_at") or current_timestamp()),
        }

    def load_client_budget_items(month: str) -> list[dict[str, object]]:
        try:
            raw_data = page.client_storage.get(client_budget_storage_key(month))
        except Exception:
            return []
        if not raw_data:
            return []
        try:
            records = json.loads(str(raw_data))
        except (TypeError, ValueError):
            return []
        if not isinstance(records, list):
            return []
        return [
            normalize_budget_record(record)
            for record in records
            if isinstance(record, dict)
            and str(record.get("description") or "").strip()
            and str(record.get("due_date") or "").strip()
        ]

    def save_client_budget_items(month: str, items: list[dict[str, object]]) -> None:
        try:
            page.client_storage.set(
                client_budget_storage_key(month),
                json.dumps(
                    [normalize_budget_record(item) for item in items],
                    ensure_ascii=True,
                ),
            )
        except Exception:
            return

    def restore_client_budget_items(month: str, items: list[dict[str, object]]) -> list[dict[str, object]]:
        for item in items:
            save_monthly_budget_item(
                month,
                str(item["item_type"]),
                str(item["description"]),
                str(item["amount_text"]),
                str(item["due_date"]),
                str(item.get("payment_date") or "") or None,
                bool(item["settled"]),
            )
        restored_items = load_monthly_budget_items(month)
        save_client_budget_items(month, restored_items)
        return restored_items

    def load_budget_items_for_screen(month: str) -> tuple[list[dict[str, object]], bool]:
        server_items = load_monthly_budget_items(month)
        if server_items:
            save_client_budget_items(month, server_items)
            return server_items, False
        client_items = load_client_budget_items(month)
        if client_items:
            return restore_client_budget_items(month, client_items), True
        return [], False

    def budget_metric_card(title: str, value_control: ft.Text, icon, accent: str) -> ft.Control:
        return ft.Container(
            bgcolor="#FFFFFF",
            border=ft.Border(
                top=ft.BorderSide(1, "#D7D0C4"),
                right=ft.BorderSide(1, "#D7D0C4"),
                bottom=ft.BorderSide(1, "#D7D0C4"),
                left=ft.BorderSide(3, accent),
            ),
            border_radius=6,
            padding=ft.Padding(left=8, top=4, right=8, bottom=4),
            content=ft.Row(
                [
                    ft.Column(
                        [
                            ft.Text(title, size=8, color="#5F6873"),
                            value_control,
                        ],
                        spacing=0,
                        expand=True,
                    ),
                    ft.Icon(icon, size=15, color=accent),
                ],
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
        )

    def refresh_budget(update_page: bool = False) -> None:
        try:
            month = selected_month()
            items, restored_from_client = load_budget_items_for_screen(month)
        except Exception as exc:
            items_column.controls = []
            set_status(str(exc), "#B42332")
            if update_page:
                page.update()
            return

        revenue_total = sum(parse_currency(str(item["amount_text"])) for item in items if item["item_type"] == "Receita")
        expense_total = sum(parse_currency(str(item["amount_text"])) for item in items if item["item_type"] == "Despesa")
        pending_total = sum(
            parse_currency(str(item["amount_text"]))
            for item in items
            if item["item_type"] == "Despesa" and not item["settled"]
        )
        revenue_total_text.value = format_currency(revenue_total)
        expense_total_text.value = format_currency(expense_total)
        balance_total_text.value = format_currency(revenue_total - expense_total)
        balance_total_text.color = "#167A4B" if revenue_total >= expense_total else "#B42332"
        pending_total_text.value = format_currency(pending_total)

        if items:
            items_column.controls = [budget_item_card(item) for item in items]
        else:
            items_column.controls = [
                ft.Container(
                    bgcolor="#F7F3EB",
                    border_radius=9,
                    padding=18,
                    content=ft.Column(
                        [
                            ft.Icon(ft.Icons.INBOX_OUTLINED, size=28, color="#8A8175"),
                            ft.Text("Nenhum lancamento neste mes.", size=12, color="#5F6873"),
                        ],
                        horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                        spacing=6,
                    ),
                )
            ]
        if restored_from_client:
            set_status(
                f"{len(items)} lancamento{'s' if len(items) != 1 else ''} recuperado"
                f"{'s' if len(items) != 1 else ''} do navegador.",
                "#167A4B",
            )
        else:
            set_status(f"{len(items)} lancamento{'s' if len(items) != 1 else ''} em {month_display(month)}.")
        if update_page:
            page.update()

    def validated_budget_form() -> tuple[str, str, str, str, str, str | None, bool]:
        month = selected_month()
        due_date = normalize_date(due_date_field.value or "")
        payment_date = normalize_date(payment_date_field.value) if (payment_date_field.value or "").strip() else None
        amount = parse_currency(amount_field.value or "")
        normalized_amount_text = format_currency(amount).replace("R$ ", "")
        if amount_field.value != normalized_amount_text:
            amount_field.value = normalized_amount_text
        description = (description_field.value or "").strip().upper()[:15]
        item_type = type_dropdown.value or "Despesa"
        if item_type not in {"Receita", "Despesa"}:
            raise ValueError("Selecione receita ou despesa.")
        if not description:
            raise ValueError("Informe a descricao.")
        if amount <= 0:
            raise ValueError("Informe um valor maior que zero.")
        if item_type == "Despesa" and bool(settled_checkbox.value) and not payment_date:
            raise ValueError("Informe a data do pagamento.")
        return (
            month,
            item_type,
            description,
            normalized_amount_text,
            due_date,
            payment_date,
            bool(settled_checkbox.value),
        )

    def save_item(_event=None) -> bool:
        nonlocal editing_item_id
        try:
            month, item_type, description, amount_text, due_date, payment_date, settled = validated_budget_form()
            if editing_item_id is None:
                save_monthly_budget_item(
                    month,
                    item_type,
                    description,
                    amount_text,
                    due_date,
                    payment_date,
                    settled,
                )
                success_message = "Lancamento salvo com sucesso."
            else:
                if not update_monthly_budget_item(
                    str(editing_item_id),
                    month,
                    item_type,
                    description,
                    amount_text,
                    due_date,
                    payment_date,
                    settled,
                ):
                    raise ValueError("Nao foi possivel alterar o lancamento.")
                success_message = "Lancamento alterado com sucesso."
            save_client_budget_items(month, load_monthly_budget_items(month))
            if editing_original_month and editing_original_month != month:
                save_client_budget_items(editing_original_month, load_monthly_budget_items(editing_original_month))
        except Exception as exc:
            set_status(str(exc), "#B42332")
            page.update()
            return False
        clear_budget_form()
        set_status(success_message, "#167A4B")
        refresh_budget(update_page=True)
        return True

    def has_unsaved_budget_input() -> bool:
        return bool(
            (description_field.value or "").strip()
            or (amount_field.value or "").strip()
            or (due_date_field.value or "").strip()
            or (payment_date_field.value or "").strip()
        )

    def exit_budget_screen(_event=None) -> None:
        if has_unsaved_budget_input() and not save_item():
            set_status("Corrija ou limpe o lancamento antes de sair.", "#B42332")
            page.update()
            return
        try:
            ensure_monthly_budget_db()
            refresh_budget(update_page=False)
        except Exception as exc:
            set_status(str(exc), "#B42332")
            page.update()
            return
        on_back()

    def update_type_label(_event=None) -> None:
        settled_checkbox.label = "Recebido" if type_dropdown.value == "Receita" else "Pago"
        page.update()

    def start_edit_item(item: dict[str, object]) -> None:
        nonlocal editing_item_id, editing_original_month
        editing_item_id = int(item["id"])
        editing_original_month = selected_month()
        form_title.value = "Alterar lancamento"
        type_dropdown.value = str(item["item_type"])
        description_field.value = str(item["description"])
        amount_field.value = str(item["amount_text"])
        due_date_field.value = date_display(item["due_date"])
        payment_date_field.value = date_display(item["payment_date"]) if item.get("payment_date") else ""
        settled_checkbox.value = bool(item["settled"])
        settled_checkbox.label = "Recebido" if type_dropdown.value == "Receita" else "Pago"
        save_button.text = "Salvar alteracoes"
        save_button.icon = ft.Icons.CHECK
        cancel_edit_button.visible = True
        set_status("Altere os campos e salve, ou cancele para desistir.", "#D97706")
        page.update()

    def cancel_edit(_event=None) -> None:
        clear_budget_form()
        set_status("Alteracao cancelada.", "#5F6873")
        page.update()

    def set_item_status(item_id: int, settled: bool) -> None:
        try:
            update_monthly_budget_item_status(str(item_id), settled)
        except Exception as exc:
            set_status(str(exc), "#B42332")
        refresh_budget(update_page=True)

    def remove_item(item_id: int) -> None:
        try:
            delete_monthly_budget_item(str(item_id))
            month = selected_month()
            remaining_items = load_monthly_budget_items(month)
            save_client_budget_items(month, remaining_items)
            set_status("Lancamento excluido.", "#167A4B")
        except Exception as exc:
            set_status(str(exc), "#B42332")
        refresh_budget(update_page=True)

    def normalize_search_text(value: object) -> str:
        normalized = unicodedata.normalize("NFKD", str(value or ""))
        without_accents = "".join(character for character in normalized if not unicodedata.combining(character))
        return without_accents.casefold().strip()

    def selected_report_months() -> list[str]:
        if report_month_field.value == "__all__":
            return list_monthly_budget_months()
        return [str(report_month_field.value or current_month)]

    def report_filter_summary() -> list[str]:
        summary = []
        if report_month_field.value == "__all__":
            summary.append("Mes: todos os meses com lancamentos")
        else:
            summary.append(f"Mes: {month_display(str(report_month_field.value or current_month))}")
        description = (report_description_field.value or "").strip().upper()
        summary.append(f"Descricao: {description}" if description else "Descricao: todas")
        summary.append(f"Tipo: {report_type_dropdown.value or 'Todos'}")
        summary.append(f"Status: {report_status_dropdown.value or 'Todos'}")
        return summary

    def report_item_status(item: dict[str, object]) -> str:
        if item["item_type"] == "Receita":
            return "Recebido" if item["settled"] else "Nao recebido"
        return "Pago" if item["settled"] else "Falta pagar"

    def build_report_data() -> tuple[list[dict[str, object]], dict[str, str], list[str]]:
        description_filter = normalize_search_text(report_description_field.value)
        type_filter = str(report_type_dropdown.value or "Todos")
        status_filter = str(report_status_dropdown.value or "Todos")
        report_items: list[dict[str, object]] = []

        for month in selected_report_months():
            for item in load_monthly_budget_items(month):
                item_description = normalize_search_text(item.get("description"))
                if description_filter and description_filter not in item_description:
                    continue
                if type_filter != "Todos" and str(item.get("item_type")) != type_filter:
                    continue
                if status_filter == "Pago" and not bool(item.get("settled")):
                    continue
                if status_filter == "Nao pago" and bool(item.get("settled")):
                    continue

                amount = parse_currency(str(item.get("amount_text") or "0,00"))
                report_items.append(
                    {
                        **item,
                        "reference_month": month,
                        "reference_month_display": month_display(month),
                        "amount_value": amount,
                        "amount_display": format_currency(amount),
                        "due_date_display": date_display(item.get("due_date")),
                        "payment_date_display": date_display(item.get("payment_date")) if item.get("payment_date") else "",
                        "status_display": report_item_status(item),
                    }
                )

        revenue_total = sum(
            float(item["amount_value"])
            for item in report_items
            if item["item_type"] == "Receita"
        )
        expense_total = sum(
            float(item["amount_value"])
            for item in report_items
            if item["item_type"] == "Despesa"
        )
        pending_total = sum(
            float(item["amount_value"])
            for item in report_items
            if item["item_type"] == "Despesa" and not item["settled"]
        )
        totals = {
            "revenue": format_currency(revenue_total),
            "expense": format_currency(expense_total),
            "balance": format_currency(revenue_total - expense_total),
            "pending": format_currency(pending_total),
        }
        return report_items, totals, report_filter_summary()

    def report_metric(title: str, value: str, accent: str) -> ft.Control:
        return ft.Container(
            bgcolor="#FFFFFF",
            border=ft.Border(
                top=ft.BorderSide(1, "#D7D0C4"),
                right=ft.BorderSide(1, "#D7D0C4"),
                bottom=ft.BorderSide(1, "#D7D0C4"),
                left=ft.BorderSide(4, accent),
            ),
            border_radius=8,
            padding=10,
            content=ft.Column(
                [
                    ft.Text(title, size=9, color="#5F6873"),
                    ft.Text(value, size=17, weight=ft.FontWeight.BOLD, color="#20242B"),
                ],
                spacing=1,
            ),
        )

    def report_row(item: dict[str, object]) -> ft.Control:
        is_revenue = item["item_type"] == "Receita"
        accent = "#167A4B" if is_revenue else "#B42332"
        status_controls: list[ft.Control] = [
            ft.Text(str(item["status_display"]), size=11, color="#20242B")
        ]
        if bool(item.get("settled")):
            status_controls.append(ft.Icon(ft.Icons.CHECK_CIRCLE, size=16, color="#167A4B"))
        return ft.Container(
            bgcolor="#FFFFFF",
            border=ft.Border(
                top=ft.BorderSide(1, "#D7D0C4"),
                right=ft.BorderSide(1, "#D7D0C4"),
                bottom=ft.BorderSide(1, "#D7D0C4"),
                left=ft.BorderSide(4, accent),
            ),
            border_radius=8,
            padding=10,
            content=ft.ResponsiveRow(
                [
                    responsive_item(ft.Text(str(item["reference_month_display"]), size=11, color="#5F6873"), xs=6, sm=2, md=2, lg=2),
                    responsive_item(ft.Text(str(item["item_type"]), size=11, color=accent, weight=ft.FontWeight.BOLD), xs=6, sm=2, md=2, lg=2),
                    responsive_item(ft.Text(str(item["description"]), size=12, weight=ft.FontWeight.BOLD), xs=12, sm=2, md=2, lg=2),
                    responsive_item(ft.Text(str(item["amount_display"]), size=12, weight=ft.FontWeight.BOLD, color=accent), xs=6, sm=2, md=2, lg=2),
                    responsive_item(ft.Text(str(item["due_date_display"]), size=11, color="#5F6873"), xs=6, sm=2, md=2, lg=2),
                    responsive_item(
                        ft.Row(status_controls, spacing=4, vertical_alignment=ft.CrossAxisAlignment.CENTER),
                        xs=12,
                        sm=2,
                        md=2,
                        lg=2,
                    ),
                ],
                spacing=6,
                run_spacing=5,
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
        )

    def printable_report_url(html_content: str) -> str:
        token = create_budget_report_print_token(html_content)
        page_url = str(page.url or "").split("?")[0].rstrip("/")
        if page_url.startswith("http"):
            return f"{page_url}/_budget-report-print?token={token}"
        return f"/_budget-report-print?token={token}"

    def print_report(report_items: list[dict[str, object]], totals: dict[str, str], filters: list[str]) -> None:
        html_content = build_budget_report_print_html(
            "Relatorio de orcamento",
            "Lancamentos filtrados do Meu orcamento",
            filters,
            report_items,
            totals,
        )
        page.launch_url(
            printable_report_url(html_content),
            web_window_name="_blank",
            web_popup_window=True,
            window_width=980,
            window_height=720,
        )

    def show_budget_screen(_event=None) -> None:
        refresh_budget(update_page=False)
        screen_container.content = budget_content
        page.update()

    def open_report_screen(_event=None) -> None:
        try:
            report_items, totals, filters = build_report_data()
        except Exception as exc:
            report_status_text.value = str(exc)
            report_status_text.color = "#B42332"
            page.update()
            return

        report_status_text.value = f"Relatorio gerado com {len(report_items)} lancamento{'s' if len(report_items) != 1 else ''}."
        report_status_text.color = "#167A4B"
        rows = [report_row(item) for item in report_items]
        if not rows:
            rows = [
                ft.Container(
                    bgcolor="#F7F3EB",
                    border_radius=8,
                    padding=18,
                    content=ft.Text("Nenhum lancamento encontrado para os filtros selecionados.", size=12, color="#5F6873"),
                )
            ]

        screen_container.content = ft.Column(
            [
                ft.Row(
                    [
                        ft.IconButton(
                            icon=ft.Icons.ARROW_BACK,
                            tooltip="Voltar ao orcamento",
                            icon_color="#20242B",
                            bgcolor="#E4DED2",
                            on_click=show_budget_screen,
                        ),
                        ft.Column(
                            [
                                ft.Text("Relatorio de orcamento", size=20, weight=ft.FontWeight.BOLD),
                                ft.Text("Consulta somente leitura dos lancamentos filtrados.", size=11, color="#5F6873"),
                            ],
                            spacing=1,
                            expand=True,
                        ),
                        ft.FilledButton(
                            "Imprimir",
                            icon=ft.Icons.PRINT,
                            on_click=lambda _event: print_report(report_items, totals, filters),
                            style=ft.ButtonStyle(
                                bgcolor="#D97706",
                                color="#FFFFFF",
                                shape=ft.RoundedRectangleBorder(radius=8),
                            ),
                        ),
                    ],
                    spacing=10,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.ResponsiveRow(
                    [
                        responsive_item(report_metric("Receitas", totals["revenue"], "#167A4B"), xs=12, sm=6, md=3, lg=3),
                        responsive_item(report_metric("Despesas", totals["expense"], "#B42332"), xs=12, sm=6, md=3, lg=3),
                        responsive_item(report_metric("Saldo", totals["balance"], "#4F8CFF"), xs=12, sm=6, md=3, lg=3),
                        responsive_item(report_metric("Falta pagar", totals["pending"], "#D97706"), xs=12, sm=6, md=3, lg=3),
                    ],
                    spacing=8,
                    run_spacing=8,
                ),
                ft.Container(
                    bgcolor="#F7F3EB",
                    border_radius=8,
                    padding=10,
                    content=ft.Column(
                        [ft.Text("Filtros aplicados", size=12, weight=ft.FontWeight.BOLD)]
                        + [ft.Text(filter_text, size=11, color="#5F6873") for filter_text in filters],
                        spacing=3,
                    ),
                ),
                ft.Row(
                    [
                        ft.Text("Lancamentos", size=15, weight=ft.FontWeight.BOLD),
                        ft.Container(expand=True),
                        ft.Text(f"{len(report_items)} registro{'s' if len(report_items) != 1 else ''}", size=10, color="#5F6873"),
                    ],
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Column(rows, spacing=8),
            ],
            spacing=8,
            scroll=ft.ScrollMode.AUTO,
        )
        page.update()

    def budget_table_header() -> ft.Control:
        return ft.Container(
            visible=(page.width or 1024) >= 760,
            bgcolor="#ECE6DA",
            border_radius=5,
            padding=ft.Padding(left=9, top=5, right=8, bottom=5),
            content=ft.Row(
                [
                    ft.Text("Descricao", size=9, weight=ft.FontWeight.BOLD, color="#5F6873", expand=True),
                    ft.Container(content=ft.Text("Vencimento", size=9, weight=ft.FontWeight.BOLD, color="#5F6873"), width=86),
                    ft.Container(content=ft.Text("Pagamento", size=9, weight=ft.FontWeight.BOLD, color="#5F6873"), width=86),
                    ft.Container(content=ft.Text("Valor", size=9, weight=ft.FontWeight.BOLD, color="#5F6873", text_align=ft.TextAlign.RIGHT), width=96),
                    ft.Container(content=ft.Text("Status", size=9, weight=ft.FontWeight.BOLD, color="#5F6873"), width=112),
                    ft.Container(content=ft.Text("Acoes", size=9, weight=ft.FontWeight.BOLD, color="#5F6873", text_align=ft.TextAlign.CENTER), width=70),
                ],
                spacing=8,
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
        )

    def budget_item_card(item: dict[str, object]) -> ft.Control:
        is_revenue = item["item_type"] == "Receita"
        accent = "#167A4B" if is_revenue else "#B42332"
        settled = bool(item["settled"])
        status_text = status_label(item)
        value_text = format_currency(parse_currency(str(item["amount_text"])))
        edit_button = ft.IconButton(
            icon=ft.Icons.EDIT_OUTLINED,
            tooltip="Editar lancamento",
            icon_color="#20242B",
            icon_size=17,
            width=28,
            height=28,
            on_click=lambda _event, selected_item=dict(item): start_edit_item(selected_item),
        )
        delete_button = ft.IconButton(
            icon=ft.Icons.DELETE_OUTLINE,
            tooltip="Excluir lancamento",
            icon_color="#B42332",
            icon_size=17,
            width=28,
            height=28,
            on_click=lambda _event, item_id=int(item["id"]): remove_item(item_id),
        )
        if (page.width or 1024) >= 760:
            return ft.Container(
                bgcolor="#FFFFFF",
                border=ft.Border(
                    top=ft.BorderSide(1, "#D7D0C4"),
                    right=ft.BorderSide(1, "#D7D0C4"),
                    bottom=ft.BorderSide(1, "#D7D0C4"),
                    left=ft.BorderSide(3, accent if not settled else "#667085"),
                ),
                border_radius=5,
                padding=ft.Padding(left=9, top=5, right=8, bottom=5),
                content=ft.Row(
                    [
                        ft.Column(
                            [
                                ft.Text(str(item["description"]), size=12, weight=ft.FontWeight.BOLD, color="#20242B", max_lines=1, overflow=ft.TextOverflow.ELLIPSIS),
                                ft.Text(str(item["item_type"]), size=9, color=accent, weight=ft.FontWeight.BOLD),
                            ],
                            spacing=0,
                            expand=True,
                        ),
                        ft.Container(content=ft.Text(date_display(item["due_date"]), size=10, color="#20242B"), width=86),
                        ft.Container(content=ft.Text(date_display(item["payment_date"]) if item.get("payment_date") else "-", size=10, color="#20242B"), width=86),
                        ft.Container(content=ft.Text(value_text, size=12, weight=ft.FontWeight.BOLD, color=accent, text_align=ft.TextAlign.RIGHT), width=96),
                        ft.Container(
                            content=ft.Row(
                                [
                                    ft.Checkbox(
                                        value=settled,
                                        on_change=lambda event, item_id=int(item["id"]): set_item_status(item_id, bool(event.control.value)),
                                    ),
                                    ft.Text(status_text, size=10, color="#20242B", max_lines=1, overflow=ft.TextOverflow.ELLIPSIS),
                                ],
                                spacing=2,
                                vertical_alignment=ft.CrossAxisAlignment.CENTER,
                            ),
                            width=112,
                        ),
                        ft.Container(
                            content=ft.Row([edit_button, delete_button], spacing=2, alignment=ft.MainAxisAlignment.CENTER),
                            width=70,
                        ),
                    ],
                    spacing=8,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
            )

        return ft.Container(
            bgcolor="#FFFFFF",
            border=ft.Border(
                top=ft.BorderSide(1, "#D7D0C4"),
                right=ft.BorderSide(1, "#D7D0C4"),
                bottom=ft.BorderSide(1, "#D7D0C4"),
                left=ft.BorderSide(3, accent if not settled else "#667085"),
            ),
            border_radius=6,
            padding=ft.Padding(left=9, top=6, right=8, bottom=6),
            content=ft.ResponsiveRow(
                [
                    responsive_item(
                        ft.Column(
                            [
                                ft.Row(
                                    [
                                        ft.Text(str(item["description"]), size=12, weight=ft.FontWeight.BOLD, color="#20242B"),
                                        ft.Text(str(item["item_type"]), size=9, color=accent, weight=ft.FontWeight.BOLD),
                                    ],
                                    spacing=6,
                                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                                ),
                                ft.Text(
                                    f"Vencimento/data: {date_display(item['due_date'])}"
                                    f"{' | Pagamento: ' + date_display(item['payment_date']) if item.get('payment_date') else ''}"
                                    f" | {status_text}",
                                    size=9,
                                    color="#5F6873",
                                ),
                            ],
                            spacing=1,
                        ),
                        xs=12,
                        sm=5,
                        md=5,
                        lg=5,
                    ),
                    responsive_item(
                        ft.Text(
                            value_text,
                            size=13,
                            weight=ft.FontWeight.BOLD,
                            color=accent,
                        ),
                        xs=6,
                        sm=2,
                        md=2,
                        lg=2,
                    ),
                    responsive_item(
                        ft.Checkbox(
                            label="Recebido" if is_revenue else "Pago",
                            value=settled,
                            on_change=lambda event, item_id=int(item["id"]): set_item_status(item_id, bool(event.control.value)),
                        ),
                        xs=6,
                        sm=3,
                        md=3,
                        lg=3,
                    ),
                    responsive_item(
                        edit_button,
                        xs=6,
                        sm=1,
                        md=1,
                        lg=1,
                    ),
                    responsive_item(
                        delete_button,
                        xs=6,
                        sm=1,
                        md=1,
                        lg=1,
                    ),
                ],
                spacing=6,
                run_spacing=4,
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
        )

    type_dropdown.on_change = update_type_label
    month_field.on_change = lambda _event: refresh_budget(update_page=True)
    description_field.on_change = uppercase_description
    amount_field.on_change = apply_amount_limit
    amount_field.on_blur = finalize_amount_field
    due_date_field.on_change = apply_due_date_mask
    payment_date_field.on_change = apply_payment_date_mask
    report_description_field.on_change = uppercase_report_description
    save_button = ft.FilledButton(
        "Salvar",
        icon=ft.Icons.SAVE_OUTLINED,
        on_click=save_item,
        height=32,
        style=ft.ButtonStyle(
            bgcolor="#D97706",
            color="#FFFFFF",
            padding=ft.Padding(left=8, top=0, right=9, bottom=0),
            shape=ft.RoundedRectangleBorder(radius=6),
        ),
    )
    cancel_edit_button = ft.OutlinedButton(
        "Cancelar",
        icon=ft.Icons.CLOSE,
        on_click=cancel_edit,
        height=32,
        visible=False,
        style=ft.ButtonStyle(
            color="#20242B",
            padding=ft.Padding(left=8, top=0, right=9, bottom=0),
            shape=ft.RoundedRectangleBorder(radius=6),
        ),
    )
    refresh_budget(update_page=False)

    report_filter_card = ft.Container(
        bgcolor="#FDFBF7",
        border=ft.Border(
            top=ft.BorderSide(2, "#B8AFA1"),
            right=ft.BorderSide(2, "#B8AFA1"),
            bottom=ft.BorderSide(2, "#B8AFA1"),
            left=ft.BorderSide(2, "#4F8CFF"),
        ),
        border_radius=7,
        padding=ft.Padding(left=7, top=5, right=7, bottom=5),
        content=ft.Column(
            [
                ft.ResponsiveRow(
                    [
                        responsive_item(
                            ft.Row(
                                [
                                    ft.Icon(ft.Icons.FILTER_ALT_OUTLINED, size=13, color="#4F8CFF"),
                                    ft.Text("Filtros", size=10, weight=ft.FontWeight.BOLD, color="#20242B"),
                                ],
                                spacing=4,
                                vertical_alignment=ft.CrossAxisAlignment.CENTER,
                            ),
                            xs=12,
                            sm=2,
                            md=1,
                            lg=1,
                        ),
                        responsive_item(report_filter_group("Mes do relatorio", report_month_field), xs=12, sm=3, md=2, lg=2),
                        responsive_item(report_filter_group("Descricao", report_description_field), xs=12, sm=4, md=3, lg=3),
                        responsive_item(report_filter_group("Status", report_status_dropdown, "#167A4B"), xs=12, sm=3, md=2, lg=2),
                        responsive_item(report_filter_group("Tipo", report_type_dropdown, "#D97706"), xs=12, sm=3, md=2, lg=2),
                        responsive_item(
                            ft.Container(
                                bgcolor="#EEF4FF",
                                border=ft.Border(
                                    top=ft.BorderSide(1, "#BBD1FF"),
                                    right=ft.BorderSide(1, "#BBD1FF"),
                                    bottom=ft.BorderSide(1, "#BBD1FF"),
                                    left=ft.BorderSide(2, "#4F8CFF"),
                                ),
                                border_radius=5,
                                padding=ft.Padding(left=5, top=2, right=5, bottom=3),
                                content=ft.Column(
                                    [
                                        ft.Text("ACAO", size=7, weight=ft.FontWeight.BOLD, color="#5F6873"),
                                        ft.FilledButton(
                                            "Gerar relatorio",
                                            icon=ft.Icons.DESCRIPTION_OUTLINED,
                                            on_click=open_report_screen,
                                            height=28,
                                            style=ft.ButtonStyle(
                                                bgcolor="#4F8CFF",
                                                color="#FFFFFF",
                                                padding=ft.Padding(left=6, top=0, right=7, bottom=0),
                                                shape=ft.RoundedRectangleBorder(radius=5),
                                            ),
                                        ),
                                    ],
                                    spacing=1,
                                ),
                            ),
                            xs=12,
                            sm=3,
                            md=2,
                            lg=2,
                        ),
                    ],
                    spacing=4,
                    run_spacing=4,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
            ],
            spacing=0,
        ),
    )

    budget_header = ft.Row(
        [
            ft.IconButton(
                icon=ft.Icons.ARROW_BACK,
                tooltip="Voltar ao controle de investimentos",
                icon_color="#20242B",
                bgcolor="#E4DED2",
                icon_size=18,
                width=34,
                height=34,
                on_click=exit_budget_screen,
            ),
            ft.Column(
                [
                    ft.ResponsiveRow(
                        [
                            responsive_item(
                                ft.Text("Meu orcamento", size=14, weight=ft.FontWeight.BOLD),
                                xs=12,
                                sm=5,
                                md=4,
                                lg=3,
                            ),
                            responsive_item(
                                ft.Container(
                                    bgcolor="#F7F3EB",
                                    border=ft.Border(
                                        top=ft.BorderSide(1, "#D7D0C4"),
                                        right=ft.BorderSide(1, "#D7D0C4"),
                                        bottom=ft.BorderSide(1, "#D7D0C4"),
                                        left=ft.BorderSide(4, "#D97706"),
                                    ),
                                    border_radius=7,
                                    padding=ft.Padding(left=7, top=3, right=7, bottom=3),
                                    content=ft.Row(
                                        [
                                            ft.Icon(ft.Icons.PUSH_PIN_OUTLINED, size=12, color="#D97706"),
                                            ft.Text("Despesas fixas", size=10, weight=ft.FontWeight.BOLD, color="#20242B"),
                                        ],
                                        spacing=5,
                                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                                    ),
                                ),
                                xs=12,
                                sm=7,
                                md=5,
                                lg=4,
                            ),
                        ],
                        spacing=6,
                        run_spacing=4,
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                ],
                spacing=0,
                expand=True,
            ),
            ft.OutlinedButton(
                "Sair",
                icon=ft.Icons.LOGOUT,
                on_click=exit_budget_screen,
                height=32,
                style=ft.ButtonStyle(
                    color="#20242B",
                    padding=ft.Padding(left=9, top=0, right=10, bottom=0),
                    shape=ft.RoundedRectangleBorder(radius=6),
                ),
            ),
        ],
        spacing=8,
        vertical_alignment=ft.CrossAxisAlignment.CENTER,
    )
    budget_metrics = ft.ResponsiveRow(
        [
            responsive_item(budget_metric_card("Receitas", revenue_total_text, ft.Icons.TRENDING_UP, "#167A4B"), xs=12, sm=6, md=3, lg=3),
            responsive_item(budget_metric_card("Despesas", expense_total_text, ft.Icons.TRENDING_DOWN, "#B42332"), xs=12, sm=6, md=3, lg=3),
            responsive_item(budget_metric_card("Saldo previsto", balance_total_text, ft.Icons.ACCOUNT_BALANCE_WALLET_OUTLINED, "#4F8CFF"), xs=12, sm=6, md=3, lg=3),
            responsive_item(budget_metric_card("Falta pagar", pending_total_text, ft.Icons.EVENT_AVAILABLE, "#D97706"), xs=12, sm=6, md=3, lg=3),
        ],
        spacing=6,
        run_spacing=6,
    )
    budget_form_card = ft.Container(
        bgcolor="#FFFFFF",
        border=ft.Border(
            top=ft.BorderSide(1, "#D7D0C4"),
            right=ft.BorderSide(1, "#D7D0C4"),
            bottom=ft.BorderSide(1, "#D7D0C4"),
            left=ft.BorderSide(3, "#D97706"),
        ),
        border_radius=6,
        padding=ft.Padding(left=8, top=6, right=8, bottom=6),
        content=ft.Column(
            [
                form_title,
                ft.ResponsiveRow(
                    [
                        responsive_item(compact_report_filter(month_field), xs=12, sm=6, md=6, lg=6),
                        responsive_item(compact_report_filter(type_dropdown), xs=12, sm=6, md=6, lg=6),
                        responsive_item(description_field, xs=12, sm=12, md=12, lg=12),
                        responsive_item(amount_field, xs=12, sm=6, md=6, lg=6),
                        responsive_item(due_date_field, xs=12, sm=6, md=6, lg=6),
                        responsive_item(payment_date_field, xs=12, sm=6, md=6, lg=6),
                        responsive_item(settled_checkbox, xs=12, sm=12, md=12, lg=12),
                    ],
                    spacing=6,
                    run_spacing=6,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.ResponsiveRow(
                    [
                        responsive_item(status, xs=12, sm=12, md=12, lg=12),
                        responsive_item(cancel_edit_button, xs=12, sm=6, md=6, lg=6),
                        responsive_item(save_button, xs=12, sm=6, md=6, lg=6),
                    ],
                    spacing=6,
                    run_spacing=6,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
            ],
            spacing=5,
        ),
    )
    monthly_entries_card = ft.Container(
        expand=True,
        bgcolor="#F7F3EB",
        border_radius=6,
        padding=ft.Padding(left=8, top=6, right=8, bottom=6),
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.Text("Lancamentos do mes", size=13, weight=ft.FontWeight.BOLD),
                        ft.Container(expand=True),
                        ft.Text("Salvo no banco", size=9, color="#5F6873"),
                    ],
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                budget_table_header(),
                items_column,
            ],
            spacing=4,
            expand=True,
        ),
    )
    if (page.width or 1024) >= 900:
        budget_workspace = ft.Row(
            [
                ft.Container(content=budget_form_card, width=318),
                ft.Container(content=monthly_entries_card, expand=True),
            ],
            spacing=6,
            expand=True,
            vertical_alignment=ft.CrossAxisAlignment.START,
        )
    else:
        budget_workspace = ft.Column(
            [
                budget_form_card,
                ft.Container(content=monthly_entries_card, expand=True),
            ],
            spacing=6,
            expand=True,
        )

    budget_content = ft.Column(
        [
            budget_header,
            budget_metrics,
            report_filter_card,
            budget_workspace,
        ],
        spacing=6,
        expand=True,
    )
    screen_container = ft.Container(
        expand=True,
        padding=ft.Padding(left=8, top=5, right=8, bottom=6),
        content=budget_content,
    )
    return screen_container


def investment_text_field(label: str) -> ft.TextField:
    return ft.TextField(
        label=label,
        dense=True,
        height=38,
        text_size=12,
        border_color="#C7BEAF",
        focused_border_color="#4F8CFF",
        bgcolor="#FFFFFF",
        color="#20242B",
        cursor_color="#4F8CFF",
        content_padding=ft.Padding(left=9, top=0, right=9, bottom=0),
    )


def monthly_budget_error_view(message: str, on_back) -> ft.Control:
    return ft.Container(
        expand=True,
        padding=ft.Padding(left=18, top=18, right=18, bottom=18),
        content=ft.Column(
            [
                ft.IconButton(
                    icon=ft.Icons.ARROW_BACK,
                    tooltip="Voltar ao controle de investimentos",
                    icon_color="#20242B",
                    bgcolor="#E4DED2",
                    on_click=lambda _event: on_back(),
                ),
                ft.Container(
                    bgcolor="#FFFFFF",
                    border=ft.Border(
                        top=ft.BorderSide(1, "#D7D0C4"),
                        right=ft.BorderSide(1, "#D7D0C4"),
                        bottom=ft.BorderSide(1, "#D7D0C4"),
                        left=ft.BorderSide(4, "#B42332"),
                    ),
                    border_radius=10,
                    padding=16,
                    content=ft.Column(
                        [
                            ft.Text("Nao foi possivel abrir Meu orcamento.", size=18, weight=ft.FontWeight.BOLD),
                            ft.Text(message, size=12, color="#B42332"),
                        ],
                        spacing=8,
                    ),
                ),
            ],
            spacing=12,
        ),
    )


def responsive_column_width(page_width: float) -> float:
    available = max(page_width - 18, 260)
    if page_width >= 1320:
        return max((available - 190 - 18) / 3, 250)
    if page_width >= 980:
        return max((available - 12) / 3.35, 235)
    if page_width >= 700:
        return min(max((available - 8) / 2, 250), 320)
    return max(230, available - 6)


def responsive_item(control: ft.Control, xs: int = 12, sm: int = 12, md: int = 6, lg: int = 6) -> ft.Control:
    control.col = {"xs": xs, "sm": sm, "md": md, "lg": lg}
    return control


def market_column(title: str, status: ft.Text, quotes: ft.Column, wide_layout: bool, width: float) -> ft.Control:
    return ft.Container(
        width=width,
        expand=False,
        content=ft.Column(
            [
                column_header(title),
                ft.Container(
                    bgcolor="#F8F5EE",
                    border_radius=8,
                    padding=ft.Padding(left=7, top=5, right=7, bottom=5),
                    content=status,
                ),
                ft.ListView(
                    controls=[quotes],
                    expand=True,
                    spacing=4,
                    padding=ft.Padding(left=0, top=0, right=0, bottom=5),
                ),
            ],
            spacing=4,
        ),
    )


def dashboard_column(status: ft.Text, quotes: ft.Column, wide_layout: bool, width: float, on_jex) -> ft.Control:
    return ft.Container(
        width=width,
        expand=False,
        content=ft.Column(
            [
                column_header("Indicadores"),
                quotes,
                ft.Container(height=64),
                jex_action_button("Acompanhe a JEX", ft.Icons.BUSINESS, on_jex, width=width),
            ],
            spacing=4,
        ),
    )


def jex_action_button(label: str, icon, on_click, width: float | None = None, tooltip: str | None = None) -> ft.Control:
    return ft.Container(
        width=width,
        bgcolor="#EEE8F8",
        border=ft.Border(
            top=ft.BorderSide(1, "#8B5CF6"),
            right=ft.BorderSide(1, "#8B5CF6"),
            bottom=ft.BorderSide(1, "#8B5CF6"),
            left=ft.BorderSide(1, "#8B5CF6"),
        ),
        border_radius=6,
        padding=ft.Padding(left=11, top=9, right=11, bottom=9),
        on_click=on_click,
        ink=True,
        tooltip=tooltip or label,
        content=ft.Row(
            [
                ft.Icon(icon, size=18, color="#6D45A0"),
                ft.Text(
                    label,
                    size=13,
                    color="#4C2A73",
                    weight=ft.FontWeight.BOLD,
                    max_lines=1,
                    overflow=ft.TextOverflow.ELLIPSIS,
                ),
            ],
            spacing=6,
            alignment=ft.MainAxisAlignment.CENTER,
            vertical_alignment=ft.CrossAxisAlignment.CENTER,
        ),
    )


def search_column(
    search_input: ft.TextField,
    suggestions: ft.Column,
    status: ft.Text,
    results: ft.Column,
    on_search,
    wide_layout: bool,
    width: float,
) -> ft.Control:
    return ft.Container(
        width=width,
        expand=False,
        content=ft.Column(
            [
                column_header("Busca"),
                search_input,
                suggestions,
                status,
                results,
            ],
            spacing=5,
        ),
    )


def column_header(title: str) -> ft.Control:
    return ft.Container(
        bgcolor="#F0EBE2",
        border=ft.Border(
            top=ft.BorderSide(0, "#E4DED2"),
            right=ft.BorderSide(0, "#E4DED2"),
            bottom=ft.BorderSide(2, "#3E8E7E"),
            left=ft.BorderSide(0, "#E4DED2"),
        ),
        border_radius=8,
        padding=ft.Padding(left=9, top=7, right=9, bottom=7),
        content=ft.Text(
            title.upper(),
            size=11,
            weight=ft.FontWeight.BOLD,
            color="#20242B",
        ),
    )


def compact_quote_card(
    quote,
    source_note: str,
    blink: bool = False,
    blink_bg: str = "#E5F2EC",
    on_click=None,
) -> ft.Control:
    change = quote.change_percent
    change_color = "#167A4B" if change is not None and change >= 0 else "#B42332"
    change_text = "-" if change is None else f"{change:.2f}%"
    return ft.Container(
        bgcolor="#FFFFFF",
        data={"base_bg": "#FFFFFF", "blink_bg": blink_bg, "key": quote.symbol},
        animate=ft.Animation(180, ft.AnimationCurve.EASE_IN_OUT),
        border=ft.Border(
            top=ft.BorderSide(1, "#D7D0C4"),
            right=ft.BorderSide(1, "#D7D0C4"),
            bottom=ft.BorderSide(1, "#D7D0C4"),
            left=ft.BorderSide(1, "#D7D0C4"),
        ),
        border_radius=6,
        padding=ft.Padding(left=7, top=5, right=7, bottom=5),
        on_click=(lambda _event: on_click(quote)) if on_click else None,
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.Row(
                            [
                                ft.Text(quote.symbol, size=12, weight=ft.FontWeight.BOLD),
                                exchange_badge(quote.exchange),
                            ],
                            spacing=4,
                        ),
                        ft.Text(change_text, size=10, color=change_color, weight=ft.FontWeight.BOLD),
                    ],
                    alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                ),
                ft.Text(indicator_price_text(quote), size=14, weight=ft.FontWeight.BOLD),
                ft.Row(
                    [
                        ft.Text(source_note, size=9, color="#8A5B00"),
                        daily_change_badge(quote) if quote.symbol == "IBOV" else ft.Text(quote.market_time or "-", size=9, color="#5F6873"),
                    ],
                    alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                ),
            ],
            spacing=2,
        ),
    )


def indicator_price_text(quote) -> str:
    if quote.symbol == "IBOV":
        return price_text(quote.price)
    return price_text(quote.price, quote.currency)


def daily_change_badge(quote) -> ft.Control:
    if quote.change_percent is None:
        return ft.Text("DIA -", size=10, color="#5F6873")
    color = "#167A4B" if quote.change_percent >= 0 else "#B42332"
    sign = "+" if quote.change_percent >= 0 else ""
    return ft.Text(
        f"DIA {sign}{quote.change_percent:.2f}%",
        size=9,
        color=color,
        weight=ft.FontWeight.BOLD,
    )


def price_direction(previous: float | None, current: float | None) -> str | None:
    if previous is None or current is None:
        return None
    previous_value = round(float(previous), 4)
    current_value = round(float(current), 4)
    if current_value > previous_value:
        return "up"
    if current_value < previous_value:
        return "down"
    return None


def direction_blink_color(direction: str | None) -> str:
    if direction == "up":
        return "#DDF1E7"
    if direction == "down":
        return "#F8E2E4"
    return "#E5F2EC"


def upsert_card(column: ft.Column, card: ft.Control, key: str) -> None:
    controls = list(column.controls)
    for index, existing in enumerate(controls):
        if isinstance(existing.data, dict) and existing.data.get("key") == key:
            controls[index] = card
            column.controls = controls
            return
    controls.append(card)
    column.controls = controls


def blink_card(card: ft.Container, page: ft.Page) -> None:
    if not card.data:
        return

    def run_blink() -> None:
        for _ in range(2):
            card.bgcolor = card.data["blink_bg"]
            page.update()
            time.sleep(0.18)
            card.bgcolor = card.data["base_bg"]
            page.update()
            time.sleep(0.18)

    page.run_thread(run_blink)


def market_card(
    quote,
    show_market_state: bool = False,
    on_click=None,
    blink: bool = False,
    apple_style: bool = False,
    highlighted: bool = False,
) -> ft.Control:
    change = quote.change_percent
    change_color = "#167A4B" if change is not None and change >= 0 else "#B42332"
    change_text = "-" if change is None else f"{change:.2f}%"
    base_bg = "#FAF7F0" if apple_style else "#F8F5EE"
    display_bg = "#EEF4FF" if highlighted else base_bg
    border_color = "#D7D0C4"
    card_padding = ft.Padding(left=12, top=11, right=12, bottom=10) if apple_style else ft.Padding(left=8, top=6, right=8, bottom=6)
    return ft.Container(
        key=f"ibov-card-{quote.symbol}" if apple_style else None,
        height=136 if apple_style else None,
        bgcolor=display_bg,
        data={
            "base_bg": display_bg,
            "normal_bg": base_bg,
            "base_border": border_color,
            "blink_bg": "#DCEFE7",
            "key": quote.symbol,
        },
        animate=ft.Animation(180, ft.AnimationCurve.EASE_IN_OUT),
        border=ft.Border(
            top=ft.BorderSide(2 if highlighted else 1, "#4F8CFF" if highlighted else border_color),
            right=ft.BorderSide(2 if highlighted else 1, "#4F8CFF" if highlighted else border_color),
            bottom=ft.BorderSide(2 if highlighted else 1, "#4F8CFF" if highlighted else border_color),
            left=ft.BorderSide(2 if highlighted else 1, "#4F8CFF" if highlighted else border_color),
        ),
        border_radius=8,
        padding=card_padding,
        shadow=(
            ft.BoxShadow(
                blur_radius=16,
                spread_radius=1,
                color="#4F8CFF44",
                offset=ft.Offset(0, 3),
            )
            if highlighted
            else None
        ),
        scale=1.01 if highlighted else 1.0,
        on_click=(lambda _event: on_click(quote)) if on_click else None,
        ink=bool(on_click),
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.Row(
                            [
                                company_logo(quote, size=28 if apple_style else 22),
                                ft.Text(
                                    quote.symbol,
                                    size=14 if apple_style else 12,
                                    color="#20242B" if apple_style else None,
                                    weight=ft.FontWeight.BOLD,
                                ),
                            ],
                            spacing=8 if apple_style else 5,
                            vertical_alignment=ft.CrossAxisAlignment.CENTER,
                        ),
                        market_change_badge(change_text, change_color) if apple_style else ft.Text(
                            change_text,
                            size=10,
                            color=change_color,
                            weight=ft.FontWeight.BOLD,
                        ),
                    ],
                    alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                ),
                ft.Row(
                    [
                        ft.Text(
                            price_text(quote.price, quote.currency),
                            size=18 if apple_style else 13,
                            color="#111827" if apple_style else None,
                            weight=ft.FontWeight.BOLD,
                        ),
                        market_state_badge(quote) if show_market_state and apple_style else (
                            market_state_line(quote) if show_market_state else ft.Container(width=0, height=0)
                        ),
                    ],
                    alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                asset_name_line(quote, apple_style=apple_style),
                (
                    ft.Container(width=0, height=0)
                    if apple_style
                    else ft.Text(
                        quote.market_time or "-",
                        size=9,
                        color="#5F6873",
                    )
                ),
            ],
            spacing=5 if apple_style else 1,
        ),
    )


def market_change_badge(change_text: str, color: str) -> ft.Control:
    positive = color == "#167A4B"
    return ft.Container(
        bgcolor="#D8EEE4" if positive else "#FCE5E7",
        border_radius=7,
        padding=ft.Padding(left=7, top=3, right=7, bottom=3),
        content=ft.Text(change_text, size=11, color="#167A4B" if positive else "#B42332", weight=ft.FontWeight.BOLD),
    )


def market_state_badge(quote) -> ft.Control:
    label, color = market_state_label(quote.market_state)
    return ft.Container(
        bgcolor="#E3DCCF",
        border_radius=7,
        padding=ft.Padding(left=7, top=3, right=7, bottom=3),
        content=ft.Text(label, size=10, color=color, weight=ft.FontWeight.BOLD),
    )


def asset_name_line(quote, apple_style: bool = False) -> ft.Control:
    return ft.Row(
        [
            ft.Text(
                quote.name or "Ativo do Ibovespa",
                color="#4B5563" if apple_style else "#374151",
                size=11 if apple_style else 10,
                max_lines=1,
                overflow=ft.TextOverflow.ELLIPSIS,
                expand=True,
            ),
            ibov_weight_badge(quote.ibov_weight) if apple_style else exchange_badge(quote.exchange),
        ],
        spacing=6,
        vertical_alignment=ft.CrossAxisAlignment.CENTER,
    )


def ibov_weight_badge(weight: float | None) -> ft.Control:
    return ft.Container(
        bgcolor="#EEE8DA",
        border_radius=6,
        padding=ft.Padding(left=6, top=2, right=6, bottom=2),
        tooltip="Participacao do ativo na carteira teorica do Ibovespa",
        content=ft.Text(
            f"IBOV {format_ibov_weight(weight)}",
            size=8,
            color="#5F6873",
            weight=ft.FontWeight.BOLD,
        ),
    )


def format_ibov_weight(weight: float | None) -> str:
    if not isinstance(weight, (int, float)):
        return "N/D"
    return f"{weight:.3f}%".replace(".", ",")


def exchange_badge(exchange: str | None, apple_style: bool = False) -> ft.Control:
    if not exchange:
        return ft.Container(width=0, height=0)
    return ft.Container(
        bgcolor="#DDD5C7" if apple_style else "#E3DCCF",
        border_radius=6 if apple_style else 4,
        padding=ft.Padding(left=6, top=2, right=6, bottom=2) if apple_style else ft.Padding(left=4, top=1, right=4, bottom=1),
        content=ft.Text(
            exchange,
            size=9 if apple_style else 7,
            color="#667085" if apple_style else "#5F6873",
            weight=ft.FontWeight.BOLD,
        ),
    )


def ibovespa_analysis_loading_view(quote) -> ft.Control:
    return ft.Container(
        expand=True,
        padding=24,
        content=ft.Column(
            [
                ft.Text(quote.symbol, size=24, weight=ft.FontWeight.BOLD, color="#20242B"),
                ft.Text(
                    "Carregando tendencias e indicadores fundamentalistas...",
                    size=13,
                    color="#5F6873",
                ),
                ft.ProgressRing(color="#3E8E7E"),
            ],
            spacing=14,
        ),
    )


def ibovespa_analysis_view(quote, horizons: list[dict], fundamentals: dict, valuation: dict, on_back) -> ft.Control:
    valuation_color = str(valuation.get("color") or "#667085")
    valuation_label = str(valuation.get("label") or "Dados insuficientes")
    return ft.Container(
        expand=True,
        padding=ft.Padding(left=14, top=8, right=14, bottom=20),
        content=ft.Column(
            [
                ft.ResponsiveRow(
                    [
                        responsive_item(
                            ft.IconButton(
                                icon=ft.Icons.ARROW_BACK,
                                tooltip="Voltar ao Ibovespa",
                                icon_color="#20242B",
                                bgcolor="#E4DED2",
                                on_click=lambda _event: on_back(),
                            ),
                            xs=2,
                            sm=1,
                            md=1,
                            lg=1,
                        ),
                        responsive_item(
                            ft.Column(
                                [
                                    ft.Row(
                                        [
                                            company_logo(quote, size=34),
                                            ft.Text(quote.symbol, size=24, weight=ft.FontWeight.BOLD, color="#20242B"),
                                            exchange_badge(quote.exchange, apple_style=True),
                                        ],
                                        spacing=9,
                                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                                    ),
                                    ft.Text(
                                        quote.name or "Ativo do Ibovespa",
                                        size=13,
                                        color="#5F6873",
                                    ),
                                ],
                                spacing=3,
                            ),
                            xs=10,
                            sm=7,
                            md=8,
                            lg=8,
                        ),
                        responsive_item(
                            ft.Container(
                                bgcolor="#FFFFFF",
                                border=ft.Border(
                                    top=ft.BorderSide(1, "#D7D0C4"),
                                    right=ft.BorderSide(1, "#D7D0C4"),
                                    bottom=ft.BorderSide(1, "#D7D0C4"),
                                    left=ft.BorderSide(1, "#D7D0C4"),
                                ),
                                border_radius=8,
                                padding=ft.Padding(left=12, top=8, right=12, bottom=8),
                                content=ft.Column(
                                    [
                                        ft.Text("PRECO ATUAL", size=9, color="#5F6873", weight=ft.FontWeight.BOLD),
                                        ft.Text(
                                            price_text(quote.price, quote.currency),
                                            size=20,
                                            color="#20242B",
                                            weight=ft.FontWeight.BOLD,
                                        ),
                                        ft.Container(height=1, bgcolor="#D7D0C4"),
                                        ft.Text("PESO NO IBOV", size=9, color="#5F6873", weight=ft.FontWeight.BOLD),
                                        ft.Text(
                                            format_ibov_weight(quote.ibov_weight),
                                            size=16,
                                            color="#3E8E7E",
                                            weight=ft.FontWeight.BOLD,
                                        ),
                                    ],
                                    spacing=3,
                                ),
                            ),
                            xs=12,
                            sm=4,
                            md=3,
                            lg=3,
                        ),
                    ],
                    spacing=10,
                    run_spacing=10,
                ),
                ft.Text("Analise de tendencia", size=19, weight=ft.FontWeight.BOLD, color="#20242B"),
                ft.ResponsiveRow(
                    [
                        responsive_item(trend_horizon_card(item), xs=12, sm=4, md=4, lg=4)
                        for item in horizons
                    ],
                    spacing=10,
                    run_spacing=10,
                ),
                ft.Text("Analise fundamentalista objetiva", size=19, weight=ft.FontWeight.BOLD, color="#20242B"),
                ft.ResponsiveRow(
                    [
                        responsive_item(
                            fundamental_verdict_panel(valuation_label, valuation_color, valuation),
                            xs=12,
                            sm=12,
                            md=4,
                            lg=4,
                        ),
                        responsive_item(
                            fundamental_metrics_panel(fundamentals),
                            xs=12,
                            sm=12,
                            md=8,
                            lg=8,
                        ),
                    ],
                    spacing=10,
                    run_spacing=10,
                ),
                ft.Container(
                    bgcolor="#FFF4D8",
                    border_radius=8,
                    padding=12,
                    content=ft.Text(
                        "Leitura educacional: a classificacao usa faixas gerais de P/L, P/VP, ROE, endividamento e dividend yield. Nao substitui comparacao setorial, analise completa dos demonstrativos ou recomendacao de investimento.",
                        size=11,
                        color="#6B4B00",
                    ),
                ),
            ],
            spacing=13,
            scroll=ft.ScrollMode.AUTO,
        ),
    )


def trend_horizon_card(item: dict) -> ft.Control:
    variation = float(item.get("variation") or 0.0)
    sign = "+" if variation >= 0 else ""
    color = str(item.get("color") or "#667085")
    return ft.Container(
        bgcolor="#FFFFFF",
        border=ft.Border(
            top=ft.BorderSide(1, "#D7D0C4"),
            right=ft.BorderSide(1, "#D7D0C4"),
            bottom=ft.BorderSide(1, "#D7D0C4"),
            left=ft.BorderSide(4, color),
        ),
        border_radius=8,
        padding=14,
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.Text(str(item.get("label")), size=15, weight=ft.FontWeight.BOLD, color="#20242B"),
                        ft.Container(
                            bgcolor="#F7F3EB",
                            border_radius=7,
                            padding=ft.Padding(left=7, top=3, right=7, bottom=3),
                            content=ft.Text(
                                str(item.get("trend")),
                                size=11,
                                color=color,
                                weight=ft.FontWeight.BOLD,
                            ),
                        ),
                    ],
                    alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                ),
                ft.Text(str(item.get("period")), size=10, color="#5F6873"),
                ft.Text(f"{sign}{variation:.2f}%", size=22, color=color, weight=ft.FontWeight.BOLD),
                ft.Text(str(item.get("summary")), size=12, color="#374151"),
            ],
            spacing=6,
        ),
    )


def fundamental_verdict_panel(label: str, color: str, valuation: dict) -> ft.Control:
    return ft.Container(
        bgcolor="#FFFFFF",
        border=ft.Border(
            top=ft.BorderSide(1, "#D7D0C4"),
            right=ft.BorderSide(1, "#D7D0C4"),
            bottom=ft.BorderSide(1, "#D7D0C4"),
            left=ft.BorderSide(4, color),
        ),
        border_radius=8,
        padding=16,
        content=ft.Column(
            [
                ft.Text("Leitura de preco", size=12, color="#5F6873", weight=ft.FontWeight.BOLD),
                ft.Text(label, size=26, color=color, weight=ft.FontWeight.BOLD),
                ft.Text(
                    str(valuation.get("explanation") or "Indicadores insuficientes."),
                    size=12,
                    color="#374151",
                ),
            ],
            spacing=7,
        ),
    )


def fundamental_metrics_panel(fundamentals: dict) -> ft.Control:
    metrics = [
        ("P/L", format_fundamental_number(fundamentals.get("pe"), "x")),
        ("P/VP", format_fundamental_number(fundamentals.get("pb"), "x")),
        ("Dividend yield", format_fundamental_number(fundamentals.get("dividend_yield"), "%")),
        ("ROE", format_fundamental_number(fundamentals.get("roe"), "%")),
        ("Divida / patrimonio", format_fundamental_number(fundamentals.get("debt_to_equity"), "x")),
        ("Lucro por acao", format_fundamental_number(fundamentals.get("eps"), "")),
        ("Valor de mercado", format_market_cap(fundamentals.get("market_cap"))),
    ]
    return ft.Container(
        bgcolor="#FFFFFF",
        border=ft.Border(
            top=ft.BorderSide(1, "#D7D0C4"),
            right=ft.BorderSide(1, "#D7D0C4"),
            bottom=ft.BorderSide(1, "#D7D0C4"),
            left=ft.BorderSide(1, "#D7D0C4"),
        ),
        border_radius=8,
        padding=14,
        content=ft.Column(
            [
                ft.Text("Indicadores utilizados", size=15, weight=ft.FontWeight.BOLD, color="#20242B"),
                ft.ResponsiveRow(
                    [
                        responsive_item(fundamental_metric(label, value), xs=6, sm=4, md=4, lg=4)
                        for label, value in metrics
                    ],
                    spacing=8,
                    run_spacing=8,
                ),
                ft.Text(
                    f"Fonte: {fundamentals.get('source', 'indisponivel')}",
                    size=10,
                    color="#5F6873",
                ),
            ],
            spacing=9,
        ),
    )


def fundamental_metric(label: str, value: str) -> ft.Control:
    return ft.Container(
        bgcolor="#F7F3EB",
        border_radius=8,
        padding=10,
        content=ft.Column(
            [
                ft.Text(label.upper(), size=8, color="#5F6873", weight=ft.FontWeight.BOLD),
                ft.Text(value, size=14, color="#20242B", weight=ft.FontWeight.BOLD),
            ],
            spacing=2,
        ),
    )


def format_fundamental_number(value, suffix: str) -> str:
    if not isinstance(value, (int, float)):
        return "N/D"
    return f"{value:.2f}{suffix}"


def format_market_cap(value) -> str:
    if not isinstance(value, (int, float)):
        return "N/D"
    if value >= 1_000_000_000:
        return f"R$ {value / 1_000_000_000:.1f} bi"
    if value >= 1_000_000:
        return f"R$ {value / 1_000_000:.1f} mi"
    return f"R$ {value:,.0f}"


def chart_loading_view() -> ft.Control:
    return ft.Container(
        expand=True,
        padding=24,
        content=ft.Column(
            [
                ft.Text("SSE Composite", size=22, weight=ft.FontWeight.BOLD),
                ft.Text("Carregando grafico de candles 5m...", color="#5F6873"),
                ft.ProgressRing(),
            ],
            spacing=14,
        ),
    )


def line_chart_loading_view(quote) -> ft.Control:
    symbol = quote if isinstance(quote, str) else quote.symbol
    return ft.Container(
        expand=True,
        padding=24,
        content=ft.Column(
            [
                ft.Text(symbol, size=22, weight=ft.FontWeight.BOLD),
                ft.Text("Carregando historico diario para analise grafica...", color="#5F6873"),
                ft.ProgressRing(),
            ],
            spacing=14,
        ),
    )


def chart_view(chart_path: Path, on_back) -> ft.Control:
    return ft.Container(
        expand=True,
        padding=ft.Padding(left=14, top=0, right=14, bottom=18),
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.OutlinedButton("Voltar", icon=ft.Icons.ARROW_BACK, on_click=lambda _event: on_back()),
                        ft.Text("SSE Composite - Candlesticks 5m", size=18, weight=ft.FontWeight.BOLD),
                    ],
                    spacing=12,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Text("Medias moveis: 9 periodos e 20 periodos", color="#5F6873", size=12),
                ft.Container(
                    bgcolor="#FFFFFF",
                    border_radius=8,
                    padding=8,
                    content=ft.Image(src=f"/{chart_path.name}", width=920, height=520),
                ),
            ],
            spacing=10,
            scroll=ft.ScrollMode.AUTO,
        ),
    )


def line_chart_view(quote, candles: list, explanation: str, on_back) -> ft.Control:
    change = quote.change_percent
    change_color = "#167A4B" if change is not None and change >= 0 else "#B42332"
    change_text = "-" if change is None else f"{'+' if change >= 0 else ''}{change:.2f}%"
    zoom_state = {"value": 1.0}
    chart_canvas = ft.Container(
        width=920,
        height=420,
        content=daily_line_chart(candles),
    )
    zoom_label = ft.Text("100%", size=11, color="#5F6873", width=42, text_align=ft.TextAlign.CENTER)
    chart_subtitle = ft.Text("Ultimos 6 meses | MA 9 / MA 20", size=11, color="#5F6873")

    def update_chart_zoom(delta: float) -> None:
        next_value = max(0.8, min(1.8, zoom_state["value"] + delta))
        if next_value == zoom_state["value"]:
            return
        zoom_state["value"] = next_value
        chart_canvas.width = 920 * next_value
        chart_canvas.height = 420 * next_value
        zoom_label.value = f"{next_value * 100:.0f}%"
        chart_canvas.update()
        zoom_label.update()

    def reset_chart_zoom() -> None:
        if zoom_state["value"] == 1.0:
            return
        zoom_state["value"] = 1.0
        chart_canvas.width = 920
        chart_canvas.height = 420
        zoom_label.value = "100%"
        chart_canvas.update()
        zoom_label.update()

    metrics_panel = ft.Container(
        bgcolor="#F7F3EB",
        border=ft.Border(
            top=ft.BorderSide(1, "#D0C7B8"),
            right=ft.BorderSide(1, "#D0C7B8"),
            bottom=ft.BorderSide(1, "#D0C7B8"),
            left=ft.BorderSide(4, "#3E8E7E"),
        ),
        border_radius=8,
        padding=ft.Padding(left=14, top=12, right=14, bottom=12),
        content=ft.Column(
            [
                ft.Text("Resumo do ativo", size=14, weight=ft.FontWeight.BOLD),
                quote_metric("Preco atual", price_text(quote.price, quote.currency), "#20242B", width=None),
                quote_metric("Variacao do dia", change_text, change_color, width=None),
                quote_metric("Horario", quote.market_time or "-", "#374151", width=None),
                ft.Container(height=1, bgcolor="#D0C7B8"),
                ft.Row(
                    [
                        ft.Icon(ft.Icons.INSIGHTS, size=18, color="#3E8E7E"),
                        ft.Text("Tendencia atual", size=14, weight=ft.FontWeight.BOLD),
                    ],
                    spacing=8,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Text(explanation, color="#374151", size=12, selectable=True),
            ],
            spacing=10,
        ),
    )
    chart_panel = ft.Container(
        bgcolor="#FFFFFF",
        border=ft.Border(
            top=ft.BorderSide(1, "#D7D0C4"),
            right=ft.BorderSide(1, "#D7D0C4"),
            bottom=ft.BorderSide(1, "#D7D0C4"),
            left=ft.BorderSide(1, "#D7D0C4"),
        ),
        border_radius=8,
        padding=ft.Padding(left=10, top=10, right=10, bottom=10),
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.Column(
                            [
                                ft.Text("Grafico diario", size=15, weight=ft.FontWeight.BOLD),
                                chart_subtitle,
                            ],
                            spacing=1,
                        ),
                        ft.Row(
                            [
                                ft.IconButton(
                                    icon=ft.Icons.REMOVE,
                                    tooltip="Diminuir zoom",
                                    icon_color="#20242B",
                                    bgcolor="#E4DED2",
                                    on_click=lambda _event: update_chart_zoom(-0.1),
                                ),
                                zoom_label,
                                ft.IconButton(
                                    icon=ft.Icons.ADD,
                                    tooltip="Aumentar zoom",
                                    icon_color="#20242B",
                                    bgcolor="#E4DED2",
                                    on_click=lambda _event: update_chart_zoom(0.1),
                                ),
                                ft.IconButton(
                                    icon=ft.Icons.CENTER_FOCUS_STRONG,
                                    tooltip="Resetar zoom",
                                    icon_color="#20242B",
                                    bgcolor="#E4DED2",
                                    on_click=lambda _event: reset_chart_zoom(),
                                ),
                            ],
                            spacing=4,
                            vertical_alignment=ft.CrossAxisAlignment.CENTER,
                        ),
                    ],
                    alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Container(
                    height=430,
                    bgcolor="#F7F3EB",
                    border_radius=6,
                    clip_behavior=ft.ClipBehavior.HARD_EDGE,
                    content=ft.ListView(
                        controls=[chart_canvas],
                        horizontal=True,
                        spacing=0,
                    ),
                ),
            ],
            spacing=8,
        ),
    )
    return ft.Container(
        expand=True,
        padding=ft.Padding(left=14, top=6, right=14, bottom=18),
        content=ft.Column(
            [
                ft.ResponsiveRow(
                    [
                        responsive_item(ft.IconButton(
                            icon=ft.Icons.ARROW_BACK,
                            tooltip="Voltar",
                            icon_color="#20242B",
                            bgcolor="#E4DED2",
                            on_click=lambda _event: on_back(),
                        ), xs=2, sm=1, md=1, lg=1),
                        responsive_item(ft.Column(
                            [
                                ft.Row(
                                    [
                                        ft.Text(quote.symbol, size=20, weight=ft.FontWeight.BOLD),
                                        exchange_badge(quote.exchange),
                                        market_state_line(quote),
                                    ],
                                    spacing=8,
                                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                                ),
                                ft.Text(
                                    quote.name or "Cotacao localizada",
                                    color="#5F6873",
                                    size=12,
                                    max_lines=1,
                                    overflow=ft.TextOverflow.ELLIPSIS,
                                ),
                            ],
                            spacing=1,
                            expand=True,
                        ), xs=10, sm=11, md=11, lg=11),
                    ],
                    spacing=12,
                    run_spacing=8,
                ),
                ft.ResponsiveRow(
                    [
                        responsive_item(chart_panel, md=12, lg=9),
                        responsive_item(metrics_panel, md=12, lg=3),
                    ],
                    spacing=12,
                    run_spacing=12,
                ),
            ],
            spacing=12,
            scroll=ft.ScrollMode.AUTO,
        ),
    )


def quote_metric(label: str, value: str, color: str, width: float | None = 170) -> ft.Control:
    return ft.Container(
        width=width,
        bgcolor="#FFFFFF",
        border=ft.Border(
            top=ft.BorderSide(1, "#D7D0C4"),
            right=ft.BorderSide(1, "#D7D0C4"),
            bottom=ft.BorderSide(1, "#D7D0C4"),
            left=ft.BorderSide(1, "#D7D0C4"),
        ),
        border_radius=6,
        padding=ft.Padding(left=10, top=7, right=10, bottom=7),
        content=ft.Column(
            [
                ft.Text(label.upper(), size=9, color="#5F6873", weight=ft.FontWeight.BOLD),
                ft.Text(value, size=15, color=color, weight=ft.FontWeight.BOLD, max_lines=1, overflow=ft.TextOverflow.ELLIPSIS),
            ],
            spacing=2,
        ),
    )


def jex_company_view(on_back, on_analytics) -> ft.Control:
    return ft.Container(
        expand=True,
        padding=ft.Padding(left=16, top=8, right=16, bottom=20),
        content=ft.Column(
            [
                ft.ResponsiveRow(
                    [
                        responsive_item(ft.IconButton(
                            icon=ft.Icons.ARROW_BACK,
                            tooltip="Voltar",
                            icon_color="#20242B",
                            bgcolor="#E4DED2",
                            on_click=lambda _event: on_back(),
                        ), xs=2, sm=1, md=1, lg=1),
                        responsive_item(ft.Column(
                            [
                                ft.Text("JEX", size=24, weight=ft.FontWeight.BOLD),
                                ft.Text("Perfil institucional, historico publico e fontes verificaveis", size=14, color="#5F6873"),
                            ],
                            spacing=3,
                        ), xs=10, sm=7, md=8, lg=8),
                        responsive_item(
                            jex_action_button(
                                "JEX Analytics",
                                ft.Icons.QUERY_STATS,
                                on_analytics,
                                tooltip="Analise financeira publica da JEX",
                            ),
                            xs=12,
                            sm=4,
                            md=3,
                            lg=3,
                        ),
                    ],
                    spacing=12,
                    run_spacing=8,
                ),
                ft.ResponsiveRow(
                    [
                        responsive_item(jex_profile_panel(), md=5, lg=4),
                        responsive_item(jex_timeline_panel(), md=7, lg=8),
                    ],
                    spacing=12,
                    run_spacing=12,
                ),
                jex_sources_panel(),
            ],
            spacing=14,
            scroll=ft.ScrollMode.AUTO,
        ),
    )


def jex_profile_panel() -> ft.Control:
    return ft.Container(
        bgcolor="#FFFFFF",
        border=ft.Border(
            top=ft.BorderSide(1, "#D7D0C4"),
            right=ft.BorderSide(1, "#D7D0C4"),
            bottom=ft.BorderSide(1, "#D7D0C4"),
            left=ft.BorderSide(4, "#3E8E7E"),
        ),
        border_radius=8,
        padding=16,
        content=ft.Column(
            [
                ft.Text("Identificacao cadastral", size=18, weight=ft.FontWeight.BOLD),
                jex_info_row("Razao social", "JEX Nederland B.V."),
                jex_info_row("Natureza juridica", "Besloten vennootschap (B.V.)"),
                jex_info_row("Registro KVK", "85002976"),
                jex_info_row("Estabelecimento", "000051083825"),
                jex_info_row("Sede", "Rotterdam, Paises Baixos"),
                jex_info_row("Endereco", "Nassaukade 5, 3071 JL Rotterdam"),
                jex_info_row("Atividade cadastral", "Atividades de sedes administrativas"),
                jex_info_row("Situacao em bolsa", "Empresa privada. Sem ticker publico."),
                ft.Container(height=1, bgcolor="#D0C7B8"),
                ft.Text("Atuacao declarada pela empresa", size=16, weight=ft.FontWeight.BOLD),
                ft.Text(
                    "Software, servicos empresariais, recrutamento, backoffice e solucoes de vendas com IA.",
                    size=14,
                    color="#374151",
                ),
            ],
            spacing=11,
        ),
    )


def jex_info_row(label: str, value: str) -> ft.Control:
    return ft.Column(
        [
            ft.Text(label.upper(), size=10, color="#5F6873", weight=ft.FontWeight.BOLD),
            ft.Text(value, size=14, color="#20242B"),
        ],
        spacing=2,
    )


def jex_timeline_panel() -> ft.Control:
    items = [
        (
            "2020",
            "Origem da marca",
            "Segundo a propria JEX, a operacao foi fundada em 2020 com foco inicial no mercado de trabalho neerlandes.",
        ),
        (
            "30/12/2021",
            "Constituicao da JEX Nederland B.V.",
            "O registro empresarial informa a constituicao da entidade JEX Nederland B.V. e sede estatutaria em Rotterdam.",
        ),
        (
            "31/12/2021",
            "Registro comercial",
            "Publicacao cadastral registra a nova inscricao e JEX Technology Group B.V. como diretora.",
        ),
        (
            "2023",
            "Expansao em Rotterdam",
            "A empresa passou a operar no antigo edificio da Unilever em Rotterdam, atual endereco Nassaukade 5.",
        ),
        (
            "2024",
            "Marca e parcerias",
            "A JEX publicou iniciativas de posicionamento de marca, incluindo parceria com o Feyenoord e o evento Battle of the Branche.",
        ),
        (
            "2025",
            "Ampliacao do portifolio",
            "Documentos institucionais publicos passaram a listar software, consultoria, trabalho temporario, backoffice e empresas relacionadas do grupo.",
        ),
        (
            "Atual",
            "Software de vendas com IA",
            "O site oficial destaca JEX CORE Sales, automacao de prospeccao, gestao de leads e dashboarding.",
        ),
    ]
    return ft.Container(
        bgcolor="#FFFFFF",
        border=ft.Border(
            top=ft.BorderSide(1, "#D7D0C4"),
            right=ft.BorderSide(1, "#D7D0C4"),
            bottom=ft.BorderSide(1, "#D7D0C4"),
            left=ft.BorderSide(1, "#D7D0C4"),
        ),
        border_radius=8,
        padding=16,
        content=ft.Column(
            [
                ft.Text("Linha do tempo publica", size=18, weight=ft.FontWeight.BOLD),
                ft.Text(
                    "Resumo baseado em fontes publicas. Nao substitui certidao oficial nem auditoria.",
                    size=13,
                    color="#5F6873",
                ),
                *[jex_timeline_item(year, title, description) for year, title, description in items],
            ],
            spacing=12,
        ),
    )


def jex_timeline_item(year: str, title: str, description: str) -> ft.Control:
    return ft.Container(
        border=ft.Border(
            top=ft.BorderSide(0, "#D7D0C4"),
            right=ft.BorderSide(0, "#D7D0C4"),
            bottom=ft.BorderSide(0, "#D7D0C4"),
            left=ft.BorderSide(3, "#3E8E7E"),
        ),
        padding=ft.Padding(left=12, top=7, right=6, bottom=7),
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.Text(year, size=13, color="#167A4B", weight=ft.FontWeight.BOLD),
                        ft.Text(title, size=14, weight=ft.FontWeight.BOLD, expand=True),
                    ],
                    spacing=8,
                ),
                ft.Text(description, size=13, color="#374151"),
            ],
            spacing=5,
        ),
    )


def jex_sources_panel() -> ft.Control:
    sources = [
        ("Registro empresarial", "KVK Handelsregister", "https://www.kvk.nl/Handelsregister/"),
        ("Institucional", "Site oficial JEX", "https://www.jex.nl/en/about-us"),
        ("Termos publicos", "Documento oficial JEX", "https://www.jex.nl/hubfs/20241204%20General%20Terms%20and%20Conditions.pdf"),
        ("Consulta auxiliar", "Dados cadastrais derivados do KVK", "https://www.transfirm.nl/nl/organisatie/85002976-000051083825-jex-nederland-b.v.?lang=en"),
    ]
    return ft.Container(
        bgcolor="#F7F3EB",
        border=ft.Border(
            top=ft.BorderSide(1, "#D0C7B8"),
            right=ft.BorderSide(1, "#D0C7B8"),
            bottom=ft.BorderSide(1, "#D0C7B8"),
            left=ft.BorderSide(1, "#D0C7B8"),
        ),
        border_radius=8,
        padding=14,
        content=ft.Column(
            [
                ft.Text("Fontes e verificacao", size=16, weight=ft.FontWeight.BOLD),
                ft.Text(
                    "Para diligencia formal, consulte o KVK e solicite o extrato oficial atualizado.",
                    size=13,
                    color="#5F6873",
                ),
                ft.ResponsiveRow(
                    [responsive_item(jex_source_card(category, label, url), md=6, lg=3) for category, label, url in sources],
                    spacing=8,
                    run_spacing=8,
                ),
            ],
            spacing=9,
        ),
    )


def jex_source_card(category: str, label: str, url: str) -> ft.Control:
    return ft.Container(
        bgcolor="#FFFFFF",
        border=ft.Border(
            top=ft.BorderSide(1, "#D7D0C4"),
            right=ft.BorderSide(1, "#D7D0C4"),
            bottom=ft.BorderSide(1, "#D7D0C4"),
            left=ft.BorderSide(3, "#8B5CF6"),
        ),
        border_radius=7,
        padding=ft.Padding(left=10, top=9, right=10, bottom=9),
        content=ft.Column(
            [
                ft.Text(category.upper(), size=9, color="#6D45A0", weight=ft.FontWeight.BOLD),
                ft.Text(label, size=12, color="#20242B", weight=ft.FontWeight.BOLD),
                ft.TextButton("Abrir fonte", icon=ft.Icons.OPEN_IN_NEW, url=url),
            ],
            spacing=4,
        ),
    )


def jex_analytics_view(on_back, on_snapshot) -> ft.Control:
    return ft.Container(
        expand=True,
        padding=ft.Padding(left=16, top=8, right=16, bottom=20),
        content=ft.Column(
            [
                ft.ResponsiveRow(
                    [
                        responsive_item(ft.IconButton(
                            icon=ft.Icons.ARROW_BACK,
                            tooltip="Voltar para JEX",
                            icon_color="#20242B",
                            bgcolor="#E4DED2",
                            on_click=lambda _event: on_back(),
                        ), xs=2, sm=1, md=1, lg=1),
                        responsive_item(ft.Column(
                            [
                                ft.Text("JEX Analytics", size=24, weight=ft.FontWeight.BOLD),
                                ft.Text("Analise publica com limites, riscos e fontes declaradas", size=14, color="#5F6873"),
                            ],
                            spacing=3,
                        ), xs=10, sm=11, md=11, lg=11),
                    ],
                    spacing=12,
                    run_spacing=8,
                ),
                ft.Container(
                    bgcolor="#FFF4D8",
                    border_radius=6,
                    padding=10,
                    content=ft.Text(
                        "JEX e uma empresa privada. Esta tela organiza informacoes publicas selecionadas; nao ha demonstracoes completas abertas nem guidance auditado recente suficiente para projetar fluxo de caixa com confianca.",
                        size=13,
                        color="#8A5B00",
                    ),
                ),
                ft.ResponsiveRow(
                    [
                        responsive_item(jex_analytics_financial_panel(on_snapshot)),
                        responsive_item(jex_analytics_fundamental_panel()),
                    ],
                    spacing=12,
                    run_spacing=12,
                ),
                ft.ResponsiveRow(
                    [
                        responsive_item(jex_analytics_ipo_panel()),
                        responsive_item(jex_analytics_sentiment_panel()),
                    ],
                    spacing=12,
                    run_spacing=12,
                ),
                jex_analytics_sources_panel(),
            ],
            spacing=14,
            scroll=ft.ScrollMode.AUTO,
        ),
    )


def analytics_panel(title: str, controls: list[ft.Control], width: float = 510) -> ft.Control:
    return ft.Container(
        bgcolor="#FFFFFF",
        border=ft.Border(
            top=ft.BorderSide(1, "#D7D0C4"),
            right=ft.BorderSide(1, "#D7D0C4"),
            bottom=ft.BorderSide(1, "#D7D0C4"),
            left=ft.BorderSide(3, "#3E8E7E"),
        ),
        border_radius=8,
        padding=16,
        content=ft.Column(
            [
                ft.Text(title, size=18, weight=ft.FontWeight.BOLD),
                *controls,
            ],
            spacing=11,
        ),
    )


def analytics_text(text: str, color: str = "#374151") -> ft.Control:
    return ft.Text(text, size=13, color=color)


def jex_analytics_financial_panel(on_snapshot) -> ft.Control:
    return analytics_panel(
        "Caixa, capital de giro e pressao financeira",
        [
            jex_info_row("Receita publica citada - 2023", "EUR 112 milhoes"),
            jex_info_row("Prejuizo publico citado - 2023", "EUR 24,5 milhoes"),
            jex_info_row("Patrimonio liquido no fim de 2023", "EUR -15 milhoes"),
            jex_info_row("Deficit de capital de giro no fim de 2023", "EUR 44 milhoes"),
            jex_info_row("Divida tributaria citada", "Mais de EUR 25 milhoes"),
            analytics_text(
                "Leitura: o historico publico aponta consumo relevante de caixa e dependencia de capital externo. Nao e possivel montar DCF responsavel sem balanco, DRE e fluxo de caixa completos e atualizados."
            ),
            analytics_text(
                "O relatorio anual citado pela imprensa indicava necessidade minima de EUR 13 milhoes adicionais ate o fim de 2025. Esta informacao precisa ser revalidada com documentos posteriores.",
                "#8A5B00",
            ),
            jex_action_button(
                "Ver fotografia financeira",
                ft.Icons.PIE_CHART,
                on_snapshot,
                tooltip="Comparar magnitudes financeiras publicas",
            ),
        ],
    )


def jex_analytics_fundamental_panel() -> ft.Control:
    return analytics_panel(
        "Analise fundamentalista publica",
        [
            jex_info_row("Modelo", "Software e servicos empresariais para recrutamento, backoffice e vendas com IA"),
            jex_info_row("Ponto positivo", "Receita relevante e marca com visibilidade no mercado neerlandes"),
            jex_info_row("Ponto positivo", "Oferta integrada e migracao para produtos de maior margem"),
            jex_info_row("Risco central", "Prejuizos elevados frente a margem bruta publica citada"),
            jex_info_row("Risco central", "Necessidade de financiamento e alerta de continuidade"),
            analytics_text(
                "Conclusao: perfil de crescimento agressivo com risco financeiro elevado. O potencial depende de converter escala em margem recorrente e demonstrar geracao de caixa sustentavel."
            ),
        ],
    )


def jex_analytics_ipo_panel() -> ft.Control:
    return analytics_panel(
        "Perspectiva de IPO",
        [
            jex_info_row("Evidencia publica", "A direcao ja mencionou uma possivel abertura de capital"),
            jex_info_row("Evidencia publica", "A pagina de carreiras informa opcoes de funcionarios convertiveis em caso de IPO"),
            jex_info_row("Mercado provavel", "Nao divulgado oficialmente"),
            jex_info_row("Data projetada", "Nao ha data oficial nem prospecto publico"),
            analytics_text(
                "Inferencia: por ser uma empresa neerlandesa sediada em Rotterdam, Euronext Amsterdam seria uma hipotese natural, mas nao ha confirmacao publica de bolsa, cronograma ou coordenadores."
            ),
            analytics_text(
                "Antes de um IPO, a empresa precisaria reduzir incertezas de continuidade, demonstrar rentabilidade ou caminho verificavel para caixa positivo e publicar informacoes financeiras mais robustas.",
                "#8A5B00",
            ),
        ],
    )


def jex_analytics_sentiment_panel() -> ft.Control:
    return analytics_panel(
        "Sentimento qualitativo",
        [
            jex_info_row("Sentimento estimado", "Cauteloso / especulativo"),
            jex_info_row("Fatores favoraveis", "Crescimento, produtos de IA, marca e ambicao comercial"),
            jex_info_row("Fatores desfavoraveis", "Prejuizo, deficit de capital de giro e dependencia de novos aportes"),
            analytics_text(
                "Como nao existe acao negociada, nao ha preco, volume, consenso de analistas ou indicador tecnico de sentimento. Esta leitura e qualitativa e deriva da cobertura publica."
            ),
            analytics_text(
                "A melhora do sentimento dependeria de evidencia publica de capitalizacao concluida, margem crescente e caixa operacional sustentavel.",
                "#167A4B",
            ),
        ],
    )


def jex_analytics_sources_panel() -> ft.Control:
    sources = [
        ("Auditoria", "Accountant.nl - alerta do auditor", "https://www.accountant.nl/nieuws/2025/2/accountant-jex-onthoudt-zich-van-oordeel-over-jaarverslag/"),
        ("Pressao financeira", "Flexmarkt - cobertura setorial", "https://www.flexmarkt.nl/brancheinformatie/financiele-druk-op-uitzendbureau-jex-neemt-toe-onzekerheid-over-voortbestaan/"),
        ("IPO", "JEX - entrevista sobre possivel IPO", "https://www.jex.nl/blog/diner-met-het-fd-interview-nick-hillebrand"),
        ("Carreiras", "JEX Careers - opcoes em acoes", "https://werkenbij.jex.nl/wat-je-krijgt"),
        ("Institucional", "JEX - site oficial", "https://www.jex.nl/"),
    ]
    return ft.Container(
        bgcolor="#F7F3EB",
        border_radius=8,
        padding=14,
        content=ft.Column(
            [
                ft.Text("Fontes da analise", size=16, weight=ft.FontWeight.BOLD),
                ft.Text(
                    "Links externos usados como referencia publica. Revise as fontes oficiais antes de qualquer decisao.",
                    size=13,
                    color="#5F6873",
                ),
                ft.ResponsiveRow(
                    [responsive_item(jex_source_card(category, label, url), md=6, lg=4) for category, label, url in sources],
                    spacing=8,
                    run_spacing=8,
                ),
            ],
            spacing=9,
        ),
    )


def jex_financial_snapshot_view(on_back) -> ft.Control:
    items = [
        ("Deficit de capital de giro", 44.0, "#8A5B00"),
        ("Divida tributaria citada", 25.0, "#B42332"),
        ("Prejuizo 2023", 24.5, "#2563A8"),
        ("Capital adicional indicado", 13.0, "#7C3FA3"),
    ]
    revenue = 112.0
    total = sum(value for _label, value, _color in items)
    return ft.Container(
        expand=True,
        padding=ft.Padding(left=16, top=8, right=16, bottom=20),
        content=ft.Column(
            [
                ft.ResponsiveRow(
                    [
                        responsive_item(ft.IconButton(
                            icon=ft.Icons.ARROW_BACK,
                            tooltip="Voltar para JEX Analytics",
                            icon_color="#20242B",
                            bgcolor="#E4DED2",
                            on_click=lambda _event: on_back(),
                        ), xs=2, sm=1, md=1, lg=1),
                        responsive_item(ft.Column(
                            [
                                ft.Text("Fotografia financeira JEX", size=24, weight=ft.FontWeight.BOLD),
                                ft.Text("Leitura visual de pressoes publicas selecionadas", size=14, color="#5F6873"),
                            ],
                            spacing=3,
                        ), xs=10, sm=11, md=11, lg=11),
                    ],
                    spacing=12,
                    run_spacing=8,
                ),
                ft.Container(
                    bgcolor="#FFF4D8",
                    border_radius=6,
                    padding=10,
                    content=ft.Text(
                        "Este grafico nao representa composicao contabil do caixa. Ele cruza indicadores publicos distintos para mostrar onde se concentra a pressao financeira selecionada.",
                        size=13,
                        color="#8A5B00",
                    ),
                ),
                ft.ResponsiveRow(
                    [
                        responsive_item(ft.Container(
                            bgcolor="#FFFFFF",
                            border_radius=8,
                            padding=16,
                            content=ft.Column(
                                [
                                    ft.Text("Mapa de pressao financeira", size=18, weight=ft.FontWeight.BOLD),
                                    ft.Text(
                                        "Percentual de cada indicador sobre a soma das pressoes publicas selecionadas.",
                                        size=13,
                                        color="#5F6873",
                                    ),
                                    jex_financial_pie_chart(items),
                                ],
                                spacing=10,
                                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                            ),
                        ), md=6, lg=4),
                        responsive_item(ft.Container(
                            bgcolor="#FFFFFF",
                            border_radius=8,
                            padding=16,
                            content=ft.Column(
                                [
                                    ft.Text("Materialidade versus receita 2023", size=18, weight=ft.FontWeight.BOLD),
                                    jex_info_row("Receita de referencia", "EUR 112,0 mi"),
                                    *[
                                        jex_snapshot_legend(
                                            label,
                                            value,
                                            value / total * 100,
                                            value / revenue * 100,
                                            color,
                                        )
                                        for label, value, color in items
                                    ],
                                    ft.Container(height=1, bgcolor="#D0C7B8"),
                                    analytics_text(
                                        "Objetivo da analise: identificar rapidamente a concentracao das pressoes financeiras e comparar sua materialidade com a receita publica de 2023."
                                    ),
                                    analytics_text(
                                        "Leitura: o deficit de capital de giro e a maior pressao selecionada. O conjunto das pressoes soma EUR 106,5 mi, equivalente a 95,1% da receita de referencia.",
                                        "#8A5B00",
                                    ),
                                ],
                                spacing=9,
                            ),
                        ), md=6, lg=4),
                        responsive_item(ft.Container(
                            bgcolor="#FFFFFF",
                            border=ft.Border(
                                top=ft.BorderSide(1, "#D7D0C4"),
                                right=ft.BorderSide(1, "#D7D0C4"),
                                bottom=ft.BorderSide(1, "#D7D0C4"),
                                left=ft.BorderSide(4, "#3E8E7E"),
                            ),
                            border_radius=8,
                            padding=16,
                            content=ft.Column(
                                [
                                    ft.Text("Sintese executiva", size=18, weight=ft.FontWeight.BOLD),
                                    ft.Text(
                                        "A fotografia mostra concentracao relevante no deficit de capital de giro: EUR 44,0 mi, ou 41,3% das pressoes selecionadas. Esse indicador representa sozinho 39,3% da receita publica de 2023."
                                        , size=13, color="#374151"
                                    ),
                                    ft.Text(
                                        "A divida tributaria citada e o prejuizo de 2023 possuem pesos semelhantes: 23,5% e 23,0% das pressoes. Juntos, somam EUR 49,5 mi."
                                        , size=13, color="#374151"
                                    ),
                                    ft.Text(
                                        "O capital adicional indicado corresponde a EUR 13,0 mi, ou 12,2% da fotografia. Esse valor sugere necessidade de reforco financeiro, mas deve ser revalidado com documentos posteriores."
                                        , size=13, color="#374151"
                                    ),
                                    ft.Container(height=1, bgcolor="#D0C7B8"),
                                    ft.Container(
                                        bgcolor="#FFF4D8",
                                        border=ft.Border(
                                            top=ft.BorderSide(1, "#D9A441"),
                                            right=ft.BorderSide(1, "#D9A441"),
                                            bottom=ft.BorderSide(1, "#D9A441"),
                                            left=ft.BorderSide(4, "#D9A441"),
                                        ),
                                        border_radius=8,
                                        padding=ft.Padding(left=12, top=10, right=12, bottom=10),
                                        content=ft.Column(
                                            [
                                                ft.Text("Conclusao executiva", size=17, weight=ft.FontWeight.BOLD, color="#8A5B00"),
                                                ft.Text(
                                                    "Com base nos dados publicos selecionados, a JEX apresentava pressao financeira material frente a sua receita. A prioridade analitica e verificar se houve capitalizacao posterior e se a empresa conseguiu reduzir deficit de capital de giro, prejuizo e exposicao tributaria.",
                                                    size=13,
                                                    color="#20242B",
                                                ),
                                                ft.Text(
                                                    "Sem demonstracoes financeiras mais recentes e completas, nao e possivel concluir que a situacao atual melhorou ou piorou.",
                                                    size=13,
                                                    color="#5F6873",
                                                ),
                                            ],
                                            spacing=7,
                                        ),
                                    ),
                                ],
                                spacing=9,
                            ),
                        ), md=12, lg=4),
                    ],
                    spacing=8,
                    run_spacing=8,
                ),
                jex_financial_snapshot_footer(),
            ],
            spacing=12,
            scroll=ft.ScrollMode.AUTO,
        ),
    )


def jex_financial_snapshot_footer() -> ft.Control:
    return ft.Container(
        bgcolor="#F7F3EB",
        border=ft.Border(
            top=ft.BorderSide(1, "#3E8E7E"),
            right=ft.BorderSide(1, "#D0C7B8"),
            bottom=ft.BorderSide(1, "#D0C7B8"),
            left=ft.BorderSide(1, "#D0C7B8"),
        ),
        border_radius=6,
        padding=14,
        alignment=ft.Alignment(0, 0),
        content=ft.Column(
            [
                ft.Text(
                        "Pressao financeira, nesta tela, significa concentracao de sinais publicos que podem indicar dificuldade para manter caixa, pagar compromissos e sustentar a operacao. Nao representa o total exato das dividas da empresa.",
                    size=12,
                    color="#374151",
                    text_align=ft.TextAlign.CENTER,
                ),
                ft.Text(
                        "Nota de transparencia: esta pesquisa foi elaborada com apoio de inteligencia artificial a partir do cruzamento de fontes publicas. As informacoes devem ser confirmadas nas fontes oficiais antes de qualquer decisao.",
                    size=12,
                    color="#8A5B00",
                    text_align=ft.TextAlign.CENTER,
                ),
            ],
            spacing=7,
            horizontal_alignment=ft.CrossAxisAlignment.CENTER,
        ),
    )


def jex_financial_pie_chart(items: list[tuple[str, float, str]]) -> ft.Control:
    import math

    size = 285
    center = size / 2
    radius = 106
    total = sum(value for _label, value, _color in items)
    shapes = []
    start_angle = -math.pi / 2
    for _label, value, color in items:
        sweep = value / total * math.tau
        segment_count = max(2, math.ceil(sweep / (math.pi / 36)))
        for segment in range(segment_count):
            angle_1 = start_angle + sweep * segment / segment_count
            angle_2 = start_angle + sweep * (segment + 1) / segment_count
            shapes.append(
                cv.Path(
                    elements=[
                        cv.Path.MoveTo(center, center),
                        cv.Path.LineTo(
                            center + radius * math.cos(angle_1),
                            center + radius * math.sin(angle_1),
                        ),
                        cv.Path.LineTo(
                            center + radius * math.cos(angle_2),
                            center + radius * math.sin(angle_2),
                        ),
                        cv.Path.Close(),
                    ],
                    paint=ft.Paint(color=color, style=ft.PaintingStyle.FILL),
                )
            )
        start_angle += sweep
    shapes.append(
        cv.Circle(
            x=center,
            y=center,
            radius=64,
            paint=ft.Paint(color="#FFFFFF", style=ft.PaintingStyle.FILL),
        )
    )
    return ft.Stack(
        width=size,
        height=size,
        controls=[
            cv.Canvas(width=size, height=size, shapes=shapes),
            ft.Container(
                left=center - 48,
                top=center - 24,
                width=96,
                content=ft.Column(
                    [
                        ft.Text("JEX", size=22, weight=ft.FontWeight.BOLD, text_align=ft.TextAlign.CENTER),
                        ft.Text("visao rapida", size=12, color="#5F6873", text_align=ft.TextAlign.CENTER),
                    ],
                    spacing=0,
                ),
            ),
        ],
    )


def jex_snapshot_legend(label: str, value: float, pressure_percent: float, revenue_percent: float, color: str) -> ft.Control:
    return ft.Column(
        [
            ft.Row(
                [
                    ft.Container(width=10, height=10, bgcolor=color, border_radius=2),
                    ft.Text(label, size=13, color="#374151", expand=True),
                    ft.Text(f"EUR {value:.1f} mi", size=13, weight=ft.FontWeight.BOLD),
                ],
                spacing=7,
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            ft.Text(
                f"{pressure_percent:.1f}% das pressoes | {revenue_percent:.1f}% da receita",
                size=12,
                color=color,
            ),
        ],
        spacing=4,
    )


def daily_line_chart(candles: list) -> ft.Control:
    closes = [float(candle.close) for candle in candles]
    if len(closes) < 2:
        return ft.Container(
            width=920,
            height=420,
            alignment=ft.Alignment(0, 0),
            content=ft.Text("Poucos dados diarios para montar o grafico.", color="#5F6873"),
        )
    width = 920
    height = 420
    pad_left = 64
    pad_right = 24
    pad_top = 24
    pad_bottom = 42
    chart_width = width - pad_left - pad_right
    chart_height = height - pad_top - pad_bottom
    min_price = min(closes)
    max_price = max(closes)
    padding = (max_price - min_price) * 0.08 or 1
    min_y = min_price - padding
    max_y = max_price + padding
    ma9 = moving_average(closes, 9)
    ma20 = moving_average(closes, 20)

    def x_at(index: int) -> float:
        return pad_left + (index / (len(closes) - 1)) * chart_width

    def y_at(value: float) -> float:
        return pad_top + (max_y - value) / (max_y - min_y) * chart_height

    shapes = [
        cv.Rect(
            x=0,
            y=0,
            width=width,
            height=height,
            border_radius=0,
            paint=ft.Paint(color="#F7F3EB", style=ft.PaintingStyle.FILL),
        ),
        cv.Rect(
            x=pad_left,
            y=pad_top,
            width=chart_width,
            height=chart_height,
            border_radius=6,
            paint=ft.Paint(color="#F7F3EB", style=ft.PaintingStyle.FILL),
        ),
    ]
    for step in range(5):
        value = min_y + (max_y - min_y) * step / 4
        y = y_at(value)
        shapes.append(
            cv.Line(
                x1=pad_left,
                y1=y,
                x2=pad_left + chart_width,
                y2=y,
                paint=ft.Paint(color="#D9D3C8", stroke_width=1),
            )
        )

    def add_series(values: list[float | None], color: str, stroke_width: float) -> None:
        previous = None
        for index, value in enumerate(values):
            if value is None:
                previous = None
                continue
            current = (x_at(index), y_at(value))
            if previous is not None:
                shapes.append(
                    cv.Line(
                        x1=previous[0],
                        y1=previous[1],
                        x2=current[0],
                        y2=current[1],
                        paint=ft.Paint(color=color, stroke_width=stroke_width),
                    )
                )
            previous = current

    add_series(closes, "#167A4B", 3)
    add_series(ma9, "#8A5B00", 2)
    add_series(ma20, "#2563A8", 2)
    shapes.append(
        cv.Circle(
            x=x_at(len(closes) - 1),
            y=y_at(closes[-1]),
            radius=4,
            paint=ft.Paint(color="#167A4B", style=ft.PaintingStyle.FILL),
        )
    )

    y_label_controls = []
    for step in range(5):
        value = min_y + (max_y - min_y) * step / 4
        y = y_at(value)
        y_label_controls.append(
            ft.Container(
                left=6,
                top=max(y - 8, 0),
                width=54,
                content=ft.Text(price_text(value), size=10, color="#5F6873", text_align=ft.TextAlign.RIGHT),
            )
        )
    x_label_controls = []
    for index in label_indexes(len(candles), 6):
        x = x_at(index)
        x_label_controls.append(
            ft.Container(
                left=max(x - 18, 0),
                top=height - 28,
                width=42,
                content=ft.Text(candles[index].time_label, size=10, color="#5F6873"),
            )
        )

    return ft.Stack(
        width=width,
        height=height,
        controls=[
            cv.Canvas(width=width, height=height, shapes=shapes),
            *y_label_controls,
            *x_label_controls,
        ],
    )


def chart_error_view(message: str, on_back) -> ft.Control:
    return ft.Container(
        expand=True,
        padding=24,
        content=ft.Column(
            [
                ft.OutlinedButton("Voltar", icon=ft.Icons.ARROW_BACK, on_click=lambda _event: on_back()),
                ft.Text("Nao foi possivel carregar o grafico.", size=18, weight=ft.FontWeight.BOLD),
                ft.Text(message, color="#B42332"),
            ],
            spacing=12,
        ),
    )


def market_state_line(quote) -> ft.Control:
    label, color = market_state_label(quote.market_state)
    return ft.Text(label, size=9, color=color, weight=ft.FontWeight.BOLD)


def market_state_label(state: str | None) -> tuple[str, str]:
    labels = {
        "REGULAR": ("Aberto", "#167A4B"),
        "PRE": ("Pre-mercado", "#8A5B00"),
        "PREPRE": ("Pre-mercado", "#8A5B00"),
        "POST": ("Pos-mercado", "#8A5B00"),
        "POSTPOST": ("Pos-mercado", "#8A5B00"),
        "CLOSED": ("Fechado", "#B42332"),
    }
    return labels.get((state or "").upper(), ("Indisponivel", "#5F6873"))


def company_logo(quote, size: float = 22) -> ft.Control:
    if quote.symbol == "SSE Composite":
        return ft.Container(
            width=size,
            height=size,
            border_radius=size / 2,
            bgcolor="#DED6C8",
            clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
            content=ft.Image(src="/sse-composite.svg", width=size, height=size),
        )
    if quote.logo_url:
        return ft.Container(
            width=size,
            height=size,
            border_radius=size / 2,
            bgcolor="#DED6C8",
            clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
            content=ft.Image(src=quote.logo_url, width=size, height=size, gapless_playback=True),
        )
    return ft.Container(
        width=size,
        height=size,
        border_radius=size / 2,
        bgcolor="#DED6C8",
        alignment=ft.Alignment(0, 0),
        content=ft.Text(quote.symbol[:2], size=9 if size > 22 else 8, weight=ft.FontWeight.BOLD),
    )


if __name__ == "__main__":
    ft.app(target=main, assets_dir="assets", web_renderer=ft.WebRenderer.CANVAS_KIT)

