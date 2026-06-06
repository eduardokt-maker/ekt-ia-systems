from __future__ import annotations

import flet as ft
import flet.canvas as cv
import json
import os
import sqlite3
import time
from datetime import datetime, time as datetime_time
from pathlib import Path
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
    fetch_ibov_dashboard_quote,
    fetch_yahoo_candles,
    fetch_yahoo_candles_cached,
    is_any_index_market_open,
    is_brazil_market_open,
    is_cme_equity_futures_market_open,
    is_forex_market_open,
    is_japan_market_open,
    is_shanghai_market_open,
    is_us_stock_market_open,
    label_indexes,
    moving_average,
    price_text,
    save_candlestick_svg,
    stream_brazil_tradingview_quotes,
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
IBOV_REFRESH_SECONDS = 3
FULL_REFRESH_SECONDS = 60
INITIAL_FULL_REFRESH_DELAY_SECONDS = 10
INVESTMENT_DATA_DIR = Path(os.getenv("EKT_DATA_DIR", Path(__file__).with_name("data")))
INVESTMENT_DB_PATH = INVESTMENT_DATA_DIR / "investments.db"
LEGACY_INVESTMENT_DB_PATH = Path(__file__).with_name("investments.db")
CLIENT_INVESTMENTS_KEY = "ekt_ia_systems.saved_investments"
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
    return os.getenv("DATABASE_URL", "").strip()


def use_postgres_investment_db() -> bool:
    return bool(investment_database_url()) and psycopg is not None


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
                created_at TEXT NOT NULL
            )
            """
        )


def ensure_postgres_investment_db() -> None:
    if not use_postgres_investment_db():
        return
    with psycopg.connect(investment_database_url()) as connection:
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
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
            """
        )


def ensure_investment_db() -> None:
    if use_postgres_investment_db():
        ensure_postgres_investment_db()
    else:
        ensure_sqlite_investment_db()


def save_investment_option(option: dict[str, str]) -> bool:
    ensure_investment_db()
    if use_postgres_investment_db():
        with psycopg.connect(investment_database_url()) as connection:
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
        with psycopg.connect(investment_database_url()) as connection:
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
        with psycopg.connect(investment_database_url()) as connection:
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


def investment_db_status() -> dict[str, object]:
    database_url_configured = bool(investment_database_url())
    backend = "postgresql" if use_postgres_investment_db() else "sqlite"
    try:
        ensure_investment_db()
        if use_postgres_investment_db():
            with psycopg.connect(investment_database_url()) as connection:
                count = connection.execute("SELECT COUNT(*) FROM investments").fetchone()[0]
        else:
            with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
                count = connection.execute("SELECT COUNT(*) FROM investments").fetchone()[0]
        return {
            "ok": True,
            "backend": backend,
            "database_url_configured": database_url_configured,
            "investment_count": int(count),
        }
    except Exception as exc:
        return {
            "ok": False,
            "backend": backend,
            "database_url_configured": database_url_configured,
            "investment_count": None,
            "error": str(exc),
        }


def main(page: ft.Page) -> None:
    page.title = "DESENVOLVIMENTO -EDUARDO KATSUM TAKAHASHI"
    page.theme_mode = ft.ThemeMode.DARK
    page.bgcolor = "#171A21"
    page.padding = 0
    page.window.min_width = 280
    page.window.min_height = 460

    ibov_status = ft.Text("Carregando ativos do Ibovespa...", color="#AEB6C2", size=12)
    ai_status = ft.Text("Carregando ativos de IA dos EUA...", color="#AEB6C2", size=12)
    index_status = ft.Text("Carregando S&P 500, ES, EWZ, Nikkei e Xangai...", color="#AEB6C2", size=12)
    rare_earth_status = ft.Text("Carregando ativos globais de terras raras...", color="#AEB6C2", size=12)
    ibov_quotes_list = ft.ResponsiveRow(spacing=8, run_spacing=8)
    ai_quotes_list = ft.Column(spacing=4)
    index_quotes_list = ft.Column(spacing=4)
    rare_earth_quotes_list = ft.Column(spacing=4)
    search_input = ft.TextField(
        hint_text="Buscar ticker",
        dense=True,
        width=170,
        height=38,
        text_size=12,
        border_color="#46515F",
        focused_border_color="#3E8E7E",
        bgcolor="#20252F",
        color="#F3F5F2",
        cursor_color="#3E8E7E",
        content_padding=ft.Padding(left=10, top=0, right=10, bottom=0),
    )
    search_status = ft.Text("Digite um ticker e pressione Enter.", color="#AEB6C2", size=11)
    search_suggestions = ft.Column(spacing=2)
    search_results = ft.Column(spacing=6)
    dashboard_status = ft.Text("Carregando indicadores...", color="#AEB6C2", size=12)
    dashboard_quotes = ft.Column(spacing=6)
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
                        ft.Text(symbol, size=11, weight=ft.FontWeight.BOLD, color="#F3F5F2"),
                        ft.Text(description, size=9, color="#AEB6C2"),
                    ],
                    alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                ),
                style=ft.ButtonStyle(
                    bgcolor={"": "#2A303B", "hovered": "#243B35"},
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

    def update_b3_market_header() -> None:
        return

    def load_ibovespa_market(version: int) -> None:
        if ibov_refresh_state["running"]:
            return
        if first_load_done["ibov"] and not is_brazil_market_open():
            set_status(ibov_status, "Mercado fechado. Cotacoes pausadas.", version)
            return
        ibov_refresh_state["running"] = True
        tickers = IBOVESPA_FALLBACK_TICKERS

        try:
            if not is_current(version):
                return
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
                    blink=price_changed,
                    freshness_note="nova variacao" if price_changed else "sincronizado",
                    apple_style=True,
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

            total_quotes = stream_brazil_tradingview_quotes(tickers, add_quote, show_progress)
        except Exception as exc:
            set_status(ibov_status, f"Erro ao buscar cotacoes: {exc}", version)
            return
        finally:
            ibov_refresh_state["running"] = False

        if not is_current(version):
            return
        first_load_done["ibov"] = True
        updated_at = datetime.now(ZoneInfo("America/Sao_Paulo")).strftime("%H:%M:%S")
        set_status(
            ibov_status,
            f"{total_quotes} cotacoes | leitura {updated_at} | {changed_quotes} variacoes | ciclo {IBOV_REFRESH_SECONDS}s",
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
        body.content = home_menu_view(open_market_screen, open_investments_screen, open_jex_from_home)
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
        body.content = investments_login_view(render_home_screen, open_investments_form_screen)
        page.update()

    def open_investments_form_screen(_event=None) -> None:
        active_screen["name"] = "investments_form"
        update_b3_market_header()
        body.content = investments_form_view(render_home_screen, page, open_fixed_income_detail_screen)
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
            bgcolor="#0B0C0F",
            padding=ft.Padding(left=12, top=6, right=12, bottom=10),
            expand=True,
            content=ft.Column(
                [
                    ft.Container(
                        bgcolor="#252A34",
                        border=ft.Border(
                            top=ft.BorderSide(1, "#2C2D32"),
                            right=ft.BorderSide(1, "#2C2D32"),
                            bottom=ft.BorderSide(1, "#2C2D32"),
                            left=ft.BorderSide(1, "#2C2D32"),
                        ),
                        border_radius=8,
                        padding=ft.Padding(left=8, top=8, right=12, bottom=8),
                        content=ft.ResponsiveRow(
                            [
                                responsive_item(ft.IconButton(
                                    icon=ft.Icons.ARROW_BACK,
                                    tooltip="Voltar ao inicio",
                                    icon_color="#F5F5F7",
                                    bgcolor="#303640",
                                    on_click=lambda _event: render_home_screen(),
                                ), xs=2, sm=1, md=1, lg=1),
                                responsive_item(ft.Column(
                                    [
                                        ft.Text("Ibovespa", size=20, weight=ft.FontWeight.BOLD, color="#F5F5F7"),
                                        ft.Text(
                                            f"{total_assets} ativos do indice",
                                            size=12,
                                            color="#A1A1AA",
                                        ),
                                    ],
                                    spacing=1,
                                ), xs=10, sm=7, md=8, lg=8),
                                responsive_item(ft.Container(
                                    bgcolor="#16372D",
                                    border_radius=8,
                                    padding=ft.Padding(left=9, top=5, right=9, bottom=5),
                                    content=ft.Row(
                                        [
                                            ft.Icon(ft.Icons.SYNC, size=13, color="#71D49C"),
                                            ft.Text("Atualizacao ativa", size=10, color="#A6F0C5", weight=ft.FontWeight.BOLD),
                                        ],
                                        spacing=5,
                                        alignment=ft.MainAxisAlignment.CENTER,
                                    ),
                                ), xs=12, sm=4, md=3, lg=3),
                            ],
                            spacing=8,
                            run_spacing=8,
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
            bgcolor="#1B1F27",
            border=ft.Border(
                top=ft.BorderSide(1, "#2C2D32"),
                right=ft.BorderSide(1, "#2C2D32"),
                bottom=ft.BorderSide(1, "#2C2D32"),
                left=ft.BorderSide(1, "#2C2D32"),
            ),
            border_radius=8,
            padding=ft.Padding(left=12, top=10, right=12, bottom=12),
            content=ft.Column(
                [
                    ft.Row(
                        [
                            ft.Text("Cotações", size=15, weight=ft.FontWeight.BOLD, color="#F5F5F7"),
                            ft.Container(expand=True),
                            status,
                        ],
                        spacing=10,
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                    ft.ListView(
                        controls=[quotes],
                        expand=True,
                        spacing=0,
                        padding=ft.Padding(left=0, top=6, right=0, bottom=2),
                    ),
                ],
                spacing=10,
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

    page.add(
        ft.SafeArea(
            ft.Column(
                [
                    ft.Container(
                        padding=ft.Padding(left=7, top=5, right=7, bottom=4),
                        content=ft.ResponsiveRow(
                            [
                                responsive_item(ft.Text("Mercado", size=18, weight=ft.FontWeight.BOLD), xs=12, sm=3, md=2, lg=2),
                                responsive_item(ft.Text(
                                    f"Atualizacao automatica: Ibovespa {IBOV_REFRESH_SECONDS}s, mercados globais {FAST_REFRESH_SECONDS}s, indicadores {FULL_REFRESH_SECONDS}s. Fonte gratuita pode ter atraso.",
                                    size=11,
                                    color="#AEB6C2",
                                ), xs=12, sm=9, md=10, lg=10),
                            ],
                            spacing=12,
                            run_spacing=5,
                        ),
                    ),
                    body,
                    ft.Container(
                        border=ft.Border(
                            top=ft.BorderSide(1, "#343B47"),
                            right=ft.BorderSide(0, "#343B47"),
                            bottom=ft.BorderSide(0, "#343B47"),
                            left=ft.BorderSide(0, "#343B47"),
                        ),
                        padding=ft.Padding(left=12, top=7, right=12, bottom=8),
                        content=ft.Row(
                            [
                                ft.Text("DESENVOLVIDO POR", size=10, color="#AEB6C2", weight=ft.FontWeight.BOLD),
                                ft.Image(
                                    src="/ekt-ia-systems-logo.png",
                                    width=220,
                                    height=52,
                                ),
                            ],
                            alignment=ft.MainAxisAlignment.CENTER,
                            vertical_alignment=ft.CrossAxisAlignment.CENTER,
                            spacing=6,
                        ),
                    ),
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
                        ft.Text("Central de acompanhamento financeiro", size=12, color="#AEB6C2"),
                    ],
                    spacing=2,
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
                            sm=12,
                            md=4,
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
                            sm=12,
                            md=4,
                            lg=4,
                        ),
                        responsive_item(
                            home_menu_card(
                                "JEX",
                                "Historico institucional, analise fundamentalista e fotografia financeira.",
                                ft.Icons.BUSINESS,
                                "#8B5CF6",
                                "Acompanhe a JEX",
                                on_jex,
                            ),
                            xs=12,
                            sm=12,
                            md=4,
                            lg=4,
                        ),
                    ],
                    spacing=12,
                    run_spacing=12,
                ),
            ],
            spacing=18,
            scroll=ft.ScrollMode.AUTO,
        ),
    )


def home_menu_card(title: str, description: str, icon, accent: str, action_label: str, on_click) -> ft.Control:
    return ft.Container(
        bgcolor="#20252F",
        border=ft.Border(
            top=ft.BorderSide(1, "#343B47"),
            right=ft.BorderSide(1, "#343B47"),
            bottom=ft.BorderSide(1, "#343B47"),
            left=ft.BorderSide(1, "#343B47"),
        ),
        border_radius=8,
        padding=16,
        content=ft.Column(
            [
                ft.Icon(icon, size=26, color=accent),
                ft.Text(title, size=17, weight=ft.FontWeight.BOLD),
                ft.Text(description, size=12, color="#AEB6C2"),
                ft.Container(height=5),
                ft.FilledButton(
                    action_label,
                    icon=ft.Icons.ARROW_FORWARD,
                    on_click=on_click,
                    style=ft.ButtonStyle(
                        bgcolor=accent,
                        color="#F8FAFC",
                    ),
                ),
            ],
            spacing=8,
        ),
    )


def investments_login_view(on_back, on_success) -> ft.Control:
    login_input = ft.TextField(
        label="Login",
        dense=True,
        border_color="#46515F",
        focused_border_color="#4F8CFF",
        bgcolor="#1B2029",
        color="#F3F5F2",
        cursor_color="#4F8CFF",
    )
    password_input = ft.TextField(
        label="Senha",
        dense=True,
        password=True,
        border_color="#46515F",
        focused_border_color="#4F8CFF",
        bgcolor="#1B2029",
        color="#F3F5F2",
        cursor_color="#4F8CFF",
    )
    login_status = ft.Text("", size=11, color="#FF9B9B")

    def validate_login(_event=None) -> None:
        if login_input.value.strip() == "adm" and password_input.value == "musashi":
            login_status.value = ""
            on_success()
            return
        login_status.value = "Login ou senha invalidos."
        login_status.update()

    password_input.on_submit = validate_login
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
                            icon_color="#F3F5F2",
                            bgcolor="#2A303B",
                            on_click=lambda _event: on_back(),
                        ),
                        ft.Column(
                            [
                                ft.Text("Investimentos", size=22, weight=ft.FontWeight.BOLD),
                                ft.Text("Acesso restrito ao controle de investimentos", size=12, color="#AEB6C2"),
                            ],
                            spacing=1,
                        ),
                    ],
                    spacing=10,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Container(
                    bgcolor="#20252F",
                    border=ft.Border(
                        top=ft.BorderSide(1, "#343B47"),
                        right=ft.BorderSide(1, "#343B47"),
                        bottom=ft.BorderSide(1, "#343B47"),
                        left=ft.BorderSide(1, "#343B47"),
                    ),
                    border_radius=8,
                    padding=16,
                    content=ft.Column(
                        [
                            ft.Icon(ft.Icons.LOCK_PERSON, size=30, color="#4F8CFF"),
                            ft.Text("Login obrigatorio", size=17, weight=ft.FontWeight.BOLD),
                            ft.Text("Informe login e senha para acessar a area de investimentos.", size=12, color="#AEB6C2"),
                            login_input,
                            password_input,
                            login_status,
                            ft.FilledButton(
                                "Entrar",
                                icon=ft.Icons.LOGIN,
                                on_click=validate_login,
                                style=ft.ButtonStyle(bgcolor="#4F8CFF", color="#F8FAFC"),
                            ),
                        ],
                        spacing=9,
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
            bgcolor="#1B2029",
            border_radius=8,
            padding=ft.Padding(left=10, top=9, right=10, bottom=9),
            content=ft.Row(
                [
                    ft.Icon(icon, size=18, color="#4F8CFF"),
                    ft.Column(
                        [
                            ft.Text(label, size=10, color="#AEB6C2", weight=ft.FontWeight.BOLD),
                            ft.Text(value, size=12, color="#F3F5F2"),
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
                            icon_color="#F3F5F2",
                            bgcolor="#2A303B",
                            on_click=lambda _event: on_back(),
                        ),
                        ft.Column(
                            [
                                ft.Text("Informacoes do ativo", size=20, weight=ft.FontWeight.BOLD),
                                ft.Text("Renda fixa Santander - tela provisoria", size=12, color="#AEB6C2"),
                            ],
                            spacing=1,
                            expand=True,
                        ),
                    ],
                    spacing=10,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Container(
                    bgcolor="#20252F",
                    border=ft.Border(
                        top=ft.BorderSide(1, "#343B47"),
                        right=ft.BorderSide(1, "#343B47"),
                        bottom=ft.BorderSide(1, "#343B47"),
                        left=ft.BorderSide(1, "#343B47"),
                    ),
                    border_radius=8,
                    padding=16,
                    content=ft.Column(
                        [
                            ft.Row(
                                [
                                    ft.Icon(ft.Icons.ACCOUNT_BALANCE, size=24, color="#8EE59A"),
                                    ft.Column(
                                        [
                                            ft.Text(snapshot["title"], size=18, weight=ft.FontWeight.BOLD),
                                            ft.Text(category, size=11, color="#AEB6C2"),
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
                                color="#AEB6C2",
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


def investments_form_view(on_back, page: ft.Page, on_detail) -> ft.Control:
    ensure_investment_db()
    saved_column = ft.Column(spacing=6)
    save_status = ft.Text("Selecione um ativo da lista para cadastrar no banco de dados.", size=11, color="#AEB6C2")
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
        save_status.color = "#8EE59A" if removed else "#FFD27A"
        refresh_saved_list()
        save_status.update()
        saved_column.update()

    def request_delete_investment(product_name: str) -> None:
        pending_delete["name"] = product_name
        save_status.value = f"Confirme a exclusao de {product_name}."
        save_status.color = "#FFD27A"
        refresh_saved_list()
        save_status.update()
        saved_column.update()

    def cancel_delete_investment() -> None:
        pending_delete["name"] = ""
        save_status.value = "Exclusao cancelada."
        save_status.color = "#AEB6C2"
        refresh_saved_list()
        save_status.update()
        saved_column.update()

    def saved_investment_card(name: str, category: str, created_at: str) -> ft.Control:
        return ft.Container(
            bgcolor="#1B2029",
            border=ft.Border(
                top=ft.BorderSide(1, "#343B47"),
                right=ft.BorderSide(1, "#343B47"),
                bottom=ft.BorderSide(1, "#343B47"),
                left=ft.BorderSide(1, "#343B47"),
            ),
            border_radius=8,
            padding=ft.Padding(left=10, top=7, right=10, bottom=7),
            content=ft.Column(
                [
                    ft.Row(
                        [
                            ft.Icon(ft.Icons.CHECK_CIRCLE, size=16, color="#8EE59A"),
                            ft.Column(
                                [
                                    ft.Text(name, size=12, weight=ft.FontWeight.BOLD),
                                    ft.Text(f"{category} | cadastrado em {created_at[:10]}", size=10, color="#AEB6C2"),
                                ],
                                spacing=1,
                                expand=True,
                            ),
                            ft.IconButton(
                                icon=ft.Icons.DELETE_OUTLINE,
                                tooltip="Excluir investimento",
                                icon_color="#FF9B9B",
                                on_click=lambda _event, selected=name: request_delete_investment(selected),
                            ),
                        ],
                        spacing=8,
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                    ft.Container(
                        visible=pending_delete["name"].casefold() == name.casefold(),
                        bgcolor="#1B1214",
                        border_radius=8,
                        padding=ft.Padding(left=10, top=8, right=10, bottom=8),
                        content=ft.Column(
                            [
                                ft.Text("Confirmar exclusao deste investimento?", size=11, color="#FFD27A"),
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
                ft.Text("Nenhum investimento cadastrado ainda.", size=11, color="#AEB6C2")
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
        save_status.color = "#8EE59A" if inserted else "#FFD27A"
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
        save_status.color = "#FFD27A"
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
            save_status.color = "#FF9B9B"
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
        save_status.color = "#8EE59A" if inserted else "#FFD27A"
        if inserted:
            clear_manual_form()
            manual_form.visible = False
        refresh_saved_list()
        save_status.update()
        saved_column.update()
        manual_form.update()

    def santander_option_card(option: dict[str, str]) -> ft.Control:
        return ft.Container(
            bgcolor="#20252F",
            border=ft.Border(
                top=ft.BorderSide(1, "#343B47"),
                right=ft.BorderSide(1, "#343B47"),
                bottom=ft.BorderSide(1, "#343B47"),
                left=ft.BorderSide(1, "#343B47"),
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
                        color="#C9D1D9",
                    ),
                    ft.Text(option["issuer"], size=10, color="#AEB6C2"),
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
                            icon_color="#F3F5F2",
                            bgcolor="#2A303B",
                            on_click=lambda _event: on_back(),
                        ),
                        ft.Column(
                            [
                                ft.Text("Controle de investimentos", size=22, weight=ft.FontWeight.BOLD),
                                ft.Text("Formulario inicial", size=12, color="#AEB6C2"),
                            ],
                            spacing=1,
                        ),
                    ],
                    spacing=10,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Container(
                    bgcolor="#20252F",
                    border=ft.Border(
                        top=ft.BorderSide(1, "#343B47"),
                        right=ft.BorderSide(1, "#343B47"),
                        bottom=ft.BorderSide(1, "#343B47"),
                        left=ft.BorderSide(1, "#343B47"),
                    ),
                    border_radius=8,
                    padding=16,
                    content=ft.Column(
                        [
                            ft.Text("ok . passou", size=14, color="#8EE59A", weight=ft.FontWeight.BOLD),
                            ft.ResponsiveRow(
                                [
                                    responsive_item(
                                        ft.Container(
                                            bgcolor="#1B2029",
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
                                                        color="#AEB6C2",
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
                                        md=5,
                                        lg=4,
                                    ),
                                    responsive_item(
                                        ft.Container(
                                            bgcolor="#1B2029",
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
                                        md=4,
                                        lg=4,
                                    ),
                                    responsive_item(
                                        ft.Container(
                                            bgcolor="#1B2029",
                                            border_radius=8,
                                            padding=12,
                                            content=ft.Column(
                                                [
                                                    ft.OutlinedButton(
                                                        "Meus investimentos",
                                                        icon=ft.Icons.ACCOUNT_BALANCE_WALLET,
                                                        style=ft.ButtonStyle(color="#F8FAFC"),
                                                    ),
                                                    ft.OutlinedButton(
                                                        "Operacoes day trade",
                                                        icon=ft.Icons.SHOW_CHART,
                                                        on_click=show_day_trade_operations,
                                                        style=ft.ButtonStyle(color="#F8FAFC"),
                                                    ),
                                                ],
                                                spacing=10,
                                            ),
                                        ),
                                        xs=12,
                                        sm=12,
                                        md=3,
                                        lg=4,
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


def investment_text_field(label: str) -> ft.TextField:
    return ft.TextField(
        label=label,
        dense=True,
        height=42,
        text_size=12,
        border_color="#46515F",
        focused_border_color="#4F8CFF",
        bgcolor="#20252F",
        color="#F3F5F2",
        cursor_color="#4F8CFF",
        content_padding=ft.Padding(left=10, top=0, right=10, bottom=0),
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
                    bgcolor="#232832",
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
        bgcolor="#2A1F3D",
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
                ft.Icon(icon, size=18, color="#C4A7FF"),
                ft.Text(
                    label,
                    size=13,
                    color="#E7D7FF",
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
        bgcolor="#282E39",
        border=ft.Border(
            top=ft.BorderSide(0, "#2A303B"),
            right=ft.BorderSide(0, "#2A303B"),
            bottom=ft.BorderSide(2, "#3E8E7E"),
            left=ft.BorderSide(0, "#2A303B"),
        ),
        border_radius=8,
        padding=ft.Padding(left=9, top=7, right=9, bottom=7),
        content=ft.Text(
            title.upper(),
            size=11,
            weight=ft.FontWeight.BOLD,
            color="#F3F5F2",
        ),
    )


def compact_quote_card(
    quote,
    source_note: str,
    blink: bool = False,
    blink_bg: str = "#243B35",
    on_click=None,
) -> ft.Control:
    change = quote.change_percent
    change_color = "#8EE59A" if change is not None and change >= 0 else "#FF9B9B"
    change_text = "-" if change is None else f"{change:.2f}%"
    return ft.Container(
        bgcolor="#20252F",
        data={"base_bg": "#20252F", "blink_bg": blink_bg, "key": quote.symbol},
        animate=ft.Animation(180, ft.AnimationCurve.EASE_IN_OUT),
        border=ft.Border(
            top=ft.BorderSide(1, "#343B47"),
            right=ft.BorderSide(1, "#343B47"),
            bottom=ft.BorderSide(1, "#343B47"),
            left=ft.BorderSide(1, "#343B47"),
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
                        ft.Text(source_note, size=9, color="#FFD27A"),
                        daily_change_badge(quote) if quote.symbol == "IBOV" else ft.Text(quote.market_time or "-", size=9, color="#AEB6C2"),
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
        return ft.Text("DIA -", size=10, color="#AEB6C2")
    color = "#8EE59A" if quote.change_percent >= 0 else "#FF9B9B"
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
        return "#1E3A32"
    if direction == "down":
        return "#3A2024"
    return "#243B35"


def upsert_card(column: ft.Column, card: ft.Control, key: str) -> None:
    for index, existing in enumerate(column.controls):
        if isinstance(existing.data, dict) and existing.data.get("key") == key:
            column.controls[index] = card
            return
    column.controls.append(card)


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
    freshness_note: str | None = None,
    apple_style: bool = False,
) -> ft.Control:
    change = quote.change_percent
    change_color = "#8EE59A" if change is not None and change >= 0 else "#FF9B9B"
    change_text = "-" if change is None else f"{change:.2f}%"
    base_bg = "#252A34" if apple_style else "#232832"
    border_color = "#34353A" if apple_style else "#343B47"
    card_padding = ft.Padding(left=12, top=11, right=12, bottom=10) if apple_style else ft.Padding(left=8, top=6, right=8, bottom=6)
    return ft.Container(
        height=136 if apple_style else None,
        bgcolor=base_bg,
        data={"base_bg": base_bg, "blink_bg": "#243A34", "key": quote.symbol},
        animate=ft.Animation(180, ft.AnimationCurve.EASE_IN_OUT),
        border=ft.Border(
            top=ft.BorderSide(1, border_color),
            right=ft.BorderSide(1, border_color),
            bottom=ft.BorderSide(1, border_color),
            left=ft.BorderSide(1, border_color),
        ),
        border_radius=8,
        padding=card_padding,
        on_click=(lambda _event: on_click(quote)) if on_click and quote.symbol == "SSE Composite" else None,
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
                                    color="#F5F5F7" if apple_style else None,
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
                            color="#FFFFFF" if apple_style else None,
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
                ft.Row(
                    [
                        ft.Text(
                            quote.market_time or "-",
                            size=10 if apple_style else 9,
                            color="#8E8E93" if apple_style else "#AEB6C2",
                        ),
                        freshness_badge(freshness_note, apple_style=apple_style),
                    ],
                    alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
            ],
            spacing=5 if apple_style else 1,
        ),
    )


def market_change_badge(change_text: str, color: str) -> ft.Control:
    positive = color == "#8EE59A"
    return ft.Container(
        bgcolor="#17372F" if positive else "#3A2025",
        border_radius=7,
        padding=ft.Padding(left=7, top=3, right=7, bottom=3),
        content=ft.Text(change_text, size=11, color="#8EE59A" if positive else "#FF9B9B", weight=ft.FontWeight.BOLD),
    )


def market_state_badge(quote) -> ft.Control:
    label, color = market_state_label(quote.market_state)
    return ft.Container(
        bgcolor="#303640",
        border_radius=7,
        padding=ft.Padding(left=7, top=3, right=7, bottom=3),
        content=ft.Text(label, size=10, color=color, weight=ft.FontWeight.BOLD),
    )


def asset_name_line(quote, apple_style: bool = False) -> ft.Control:
    return ft.Row(
        [
            ft.Text(
                quote.name or "Ativo do Ibovespa",
                color="#C7C7CC" if apple_style else "#C9D1D9",
                size=11 if apple_style else 10,
                max_lines=1,
                overflow=ft.TextOverflow.ELLIPSIS,
                expand=True,
            ),
            exchange_badge(quote.exchange, apple_style=apple_style),
        ],
        spacing=6,
        vertical_alignment=ft.CrossAxisAlignment.CENTER,
    )


def freshness_badge(note: str | None, apple_style: bool = False) -> ft.Control:
    if not note:
        return ft.Container(width=0, height=0)
    changed = note == "nova variacao"
    return ft.Container(
        bgcolor=("#17372F" if changed else "#353B46") if apple_style else ("#1E3A32" if changed else "#303743"),
        border_radius=6 if apple_style else 4,
        padding=ft.Padding(left=6, top=2, right=6, bottom=2) if apple_style else ft.Padding(left=4, top=1, right=4, bottom=1),
        content=ft.Text(
            note,
            size=9 if apple_style else 7,
            color="#8EE59A" if changed else ("#A1A1AA" if apple_style else "#AEB6C2"),
            weight=ft.FontWeight.BOLD,
        ),
    )


def exchange_badge(exchange: str | None, apple_style: bool = False) -> ft.Control:
    if not exchange:
        return ft.Container(width=0, height=0)
    return ft.Container(
        bgcolor="#353B46" if apple_style else "#303743",
        border_radius=6 if apple_style else 4,
        padding=ft.Padding(left=6, top=2, right=6, bottom=2) if apple_style else ft.Padding(left=4, top=1, right=4, bottom=1),
        content=ft.Text(
            exchange,
            size=9 if apple_style else 7,
            color="#A1A1AA" if apple_style else "#AEB6C2",
            weight=ft.FontWeight.BOLD,
        ),
    )


def chart_loading_view() -> ft.Control:
    return ft.Container(
        expand=True,
        padding=24,
        content=ft.Column(
            [
                ft.Text("SSE Composite", size=22, weight=ft.FontWeight.BOLD),
                ft.Text("Carregando grafico de candles 5m...", color="#AEB6C2"),
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
                ft.Text("Carregando historico diario para analise grafica...", color="#AEB6C2"),
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
                ft.Text("Medias moveis: 9 periodos e 20 periodos", color="#AEB6C2", size=12),
                ft.Container(
                    bgcolor="#20252F",
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
    change_color = "#8EE59A" if change is not None and change >= 0 else "#FF9B9B"
    change_text = "-" if change is None else f"{'+' if change >= 0 else ''}{change:.2f}%"
    zoom_state = {"value": 1.0}
    chart_canvas = ft.Container(
        width=920,
        height=420,
        content=daily_line_chart(candles),
    )
    zoom_label = ft.Text("100%", size=11, color="#AEB6C2", width=42, text_align=ft.TextAlign.CENTER)
    chart_subtitle = ft.Text("Ultimos 6 meses | MA 9 / MA 20", size=11, color="#AEB6C2")

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
        bgcolor="#1A1F28",
        border=ft.Border(
            top=ft.BorderSide(1, "#414A58"),
            right=ft.BorderSide(1, "#414A58"),
            bottom=ft.BorderSide(1, "#414A58"),
            left=ft.BorderSide(4, "#3E8E7E"),
        ),
        border_radius=8,
        padding=ft.Padding(left=14, top=12, right=14, bottom=12),
        content=ft.Column(
            [
                ft.Text("Resumo do ativo", size=14, weight=ft.FontWeight.BOLD),
                quote_metric("Preco atual", price_text(quote.price, quote.currency), "#F3F5F2", width=None),
                quote_metric("Variacao do dia", change_text, change_color, width=None),
                quote_metric("Horario", quote.market_time or "-", "#C9D1D9", width=None),
                ft.Container(height=1, bgcolor="#414A58"),
                ft.Row(
                    [
                        ft.Icon(ft.Icons.INSIGHTS, size=18, color="#3E8E7E"),
                        ft.Text("Tendencia atual", size=14, weight=ft.FontWeight.BOLD),
                    ],
                    spacing=8,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                ft.Text(explanation, color="#C9D1D9", size=12, selectable=True),
            ],
            spacing=10,
        ),
    )
    chart_panel = ft.Container(
        bgcolor="#20252F",
        border=ft.Border(
            top=ft.BorderSide(1, "#343B47"),
            right=ft.BorderSide(1, "#343B47"),
            bottom=ft.BorderSide(1, "#343B47"),
            left=ft.BorderSide(1, "#343B47"),
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
                                    icon_color="#F3F5F2",
                                    bgcolor="#2A303B",
                                    on_click=lambda _event: update_chart_zoom(-0.1),
                                ),
                                zoom_label,
                                ft.IconButton(
                                    icon=ft.Icons.ADD,
                                    tooltip="Aumentar zoom",
                                    icon_color="#F3F5F2",
                                    bgcolor="#2A303B",
                                    on_click=lambda _event: update_chart_zoom(0.1),
                                ),
                                ft.IconButton(
                                    icon=ft.Icons.CENTER_FOCUS_STRONG,
                                    tooltip="Resetar zoom",
                                    icon_color="#F3F5F2",
                                    bgcolor="#2A303B",
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
                    bgcolor="#1B2029",
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
                            icon_color="#F3F5F2",
                            bgcolor="#2A303B",
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
                                    color="#AEB6C2",
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
        bgcolor="#20252F",
        border=ft.Border(
            top=ft.BorderSide(1, "#343B47"),
            right=ft.BorderSide(1, "#343B47"),
            bottom=ft.BorderSide(1, "#343B47"),
            left=ft.BorderSide(1, "#343B47"),
        ),
        border_radius=6,
        padding=ft.Padding(left=10, top=7, right=10, bottom=7),
        content=ft.Column(
            [
                ft.Text(label.upper(), size=9, color="#AEB6C2", weight=ft.FontWeight.BOLD),
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
                            icon_color="#F3F5F2",
                            bgcolor="#2A303B",
                            on_click=lambda _event: on_back(),
                        ), xs=2, sm=1, md=1, lg=1),
                        responsive_item(ft.Column(
                            [
                                ft.Text("JEX", size=24, weight=ft.FontWeight.BOLD),
                                ft.Text("Perfil institucional e historico publico consolidado", size=14, color="#AEB6C2"),
                            ],
                            spacing=3,
                        ), xs=10, sm=7, md=8, lg=8),
                        responsive_item(
                            jex_action_button(
                                "JEX ANALITICS",
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
                        responsive_item(jex_profile_panel(), md=4, lg=4),
                        responsive_item(jex_timeline_panel(), md=8, lg=8),
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
        bgcolor="#20252F",
        border=ft.Border(
            top=ft.BorderSide(1, "#343B47"),
            right=ft.BorderSide(1, "#343B47"),
            bottom=ft.BorderSide(1, "#343B47"),
            left=ft.BorderSide(4, "#3E8E7E"),
        ),
        border_radius=8,
        padding=16,
        content=ft.Column(
            [
                ft.Text("Dados da empresa", size=18, weight=ft.FontWeight.BOLD),
                jex_info_row("Razao social", "JEX Nederland B.V."),
                jex_info_row("Natureza juridica", "Besloten vennootschap (B.V.)"),
                jex_info_row("Registro KVK", "85002976"),
                jex_info_row("Estabelecimento", "000051083825"),
                jex_info_row("Sede", "Rotterdam, Paises Baixos"),
                jex_info_row("Endereco", "Nassaukade 5, 3071 JL Rotterdam"),
                jex_info_row("Atividade cadastral", "Atividades de sedes administrativas"),
                jex_info_row("Situacao em bolsa", "Empresa privada. Sem ticker publico."),
                ft.Container(height=1, bgcolor="#414A58"),
                ft.Text("Atuacao declarada", size=16, weight=ft.FontWeight.BOLD),
                ft.Text(
                    "Software, servicos empresariais, recrutamento, backoffice e solucoes de vendas com IA.",
                    size=14,
                    color="#C9D1D9",
                ),
            ],
            spacing=11,
        ),
    )


def jex_info_row(label: str, value: str) -> ft.Control:
    return ft.Column(
        [
            ft.Text(label.upper(), size=10, color="#AEB6C2", weight=ft.FontWeight.BOLD),
            ft.Text(value, size=14, color="#F3F5F2"),
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
        bgcolor="#20252F",
        border=ft.Border(
            top=ft.BorderSide(1, "#343B47"),
            right=ft.BorderSide(1, "#343B47"),
            bottom=ft.BorderSide(1, "#343B47"),
            left=ft.BorderSide(1, "#343B47"),
        ),
        border_radius=8,
        padding=16,
        content=ft.Column(
            [
                ft.Text("Linha do tempo publica", size=18, weight=ft.FontWeight.BOLD),
                ft.Text(
                    "Resumo baseado em fontes publicas. Nao substitui certidao oficial nem auditoria.",
                    size=13,
                    color="#AEB6C2",
                ),
                *[jex_timeline_item(year, title, description) for year, title, description in items],
            ],
            spacing=12,
        ),
    )


def jex_timeline_item(year: str, title: str, description: str) -> ft.Control:
    return ft.Container(
        border=ft.Border(
            top=ft.BorderSide(0, "#343B47"),
            right=ft.BorderSide(0, "#343B47"),
            bottom=ft.BorderSide(0, "#343B47"),
            left=ft.BorderSide(3, "#3E8E7E"),
        ),
        padding=ft.Padding(left=12, top=7, right=6, bottom=7),
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.Text(year, size=13, color="#8EE59A", weight=ft.FontWeight.BOLD),
                        ft.Text(title, size=14, weight=ft.FontWeight.BOLD, expand=True),
                    ],
                    spacing=8,
                ),
                ft.Text(description, size=13, color="#C9D1D9"),
            ],
            spacing=5,
        ),
    )


def jex_sources_panel() -> ft.Control:
    sources = [
        ("KVK Handelsregister", "https://www.kvk.nl/Handelsregister/"),
        ("Site oficial JEX", "https://www.jex.nl/en/about-us"),
        ("Termos publicos JEX", "https://www.jex.nl/hubfs/20241204%20General%20Terms%20and%20Conditions.pdf"),
        ("Dados cadastrais derivados do KVK", "https://www.transfirm.nl/nl/organisatie/85002976-000051083825-jex-nederland-b.v.?lang=en"),
    ]
    return ft.Container(
        bgcolor="#1A1F28",
        border=ft.Border(
            top=ft.BorderSide(1, "#414A58"),
            right=ft.BorderSide(1, "#414A58"),
            bottom=ft.BorderSide(1, "#414A58"),
            left=ft.BorderSide(1, "#414A58"),
        ),
        border_radius=8,
        padding=14,
        content=ft.Column(
            [
                ft.Text("Fontes para verificacao", size=16, weight=ft.FontWeight.BOLD),
                ft.Text(
                    "Para diligencia formal, consulte o KVK e solicite o extrato oficial atualizado.",
                    size=13,
                    color="#AEB6C2",
                ),
                ft.Row(
                    [
                        ft.TextButton(
                            label,
                            icon=ft.Icons.OPEN_IN_NEW,
                            url=url,
                        )
                        for label, url in sources
                    ],
                    spacing=4,
                    scroll=ft.ScrollMode.AUTO,
                ),
            ],
            spacing=6,
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
                            icon_color="#F3F5F2",
                            bgcolor="#2A303B",
                            on_click=lambda _event: on_back(),
                        ), xs=2, sm=1, md=1, lg=1),
                        responsive_item(ft.Column(
                            [
                                ft.Text("JEX ANALITICS", size=24, weight=ft.FontWeight.BOLD),
                                ft.Text("Analise baseada exclusivamente em informacoes publicas disponiveis", size=14, color="#AEB6C2"),
                            ],
                            spacing=3,
                        ), xs=10, sm=11, md=11, lg=11),
                    ],
                    spacing=12,
                    run_spacing=8,
                ),
                ft.Container(
                    bgcolor="#2C2518",
                    border_radius=6,
                    padding=10,
                    content=ft.Text(
                        "JEX e uma empresa privada. Nao ha demonstracoes completas abertas nem guidance auditado recente suficiente para projetar fluxo de caixa com confianca.",
                        size=13,
                        color="#FFD27A",
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
        bgcolor="#20252F",
        border=ft.Border(
            top=ft.BorderSide(1, "#343B47"),
            right=ft.BorderSide(1, "#343B47"),
            bottom=ft.BorderSide(1, "#343B47"),
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


def analytics_text(text: str, color: str = "#C9D1D9") -> ft.Control:
    return ft.Text(text, size=13, color=color)


def jex_analytics_financial_panel(on_snapshot) -> ft.Control:
    return analytics_panel(
        "Fluxo de caixa e pressao financeira",
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
                "#FFD27A",
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
        "Analise fundamentalista",
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
                "#FFD27A",
            ),
        ],
    )


def jex_analytics_sentiment_panel() -> ft.Control:
    return analytics_panel(
        "Sentimento de mercado",
        [
            jex_info_row("Sentimento estimado", "Cauteloso / especulativo"),
            jex_info_row("Fatores favoraveis", "Crescimento, produtos de IA, marca e ambicao comercial"),
            jex_info_row("Fatores desfavoraveis", "Prejuizo, deficit de capital de giro e dependencia de novos aportes"),
            analytics_text(
                "Como nao existe acao negociada, nao ha preco, volume, consenso de analistas ou indicador tecnico de sentimento. Esta leitura e qualitativa e deriva da cobertura publica."
            ),
            analytics_text(
                "A melhora do sentimento dependeria de evidencia publica de capitalizacao concluida, margem crescente e caixa operacional sustentavel.",
                "#8EE59A",
            ),
        ],
    )


def jex_analytics_sources_panel() -> ft.Control:
    sources = [
        ("Accountant.nl - alerta do auditor", "https://www.accountant.nl/nieuws/2025/2/accountant-jex-onthoudt-zich-van-oordeel-over-jaarverslag/"),
        ("Flexmarkt - pressao financeira", "https://www.flexmarkt.nl/brancheinformatie/financiele-druk-op-uitzendbureau-jex-neemt-toe-onzekerheid-over-voortbestaan/"),
        ("JEX - entrevista sobre possivel IPO", "https://www.jex.nl/blog/diner-met-het-fd-interview-nick-hillebrand"),
        ("JEX Careers - opcoes em acoes", "https://werkenbij.jex.nl/wat-je-krijgt"),
        ("JEX - site oficial", "https://www.jex.nl/"),
    ]
    return ft.Container(
        bgcolor="#1A1F28",
        border_radius=8,
        padding=14,
        content=ft.Column(
            [
                ft.Text("Fontes da analise", size=16, weight=ft.FontWeight.BOLD),
                ft.Row(
                    [
                        ft.TextButton(label, icon=ft.Icons.OPEN_IN_NEW, url=url)
                        for label, url in sources
                    ],
                    spacing=4,
                    scroll=ft.ScrollMode.AUTO,
                ),
            ],
            spacing=6,
        ),
    )


def jex_financial_snapshot_view(on_back) -> ft.Control:
    items = [
        ("Deficit de capital de giro", 44.0, "#FFD27A"),
        ("Divida tributaria citada", 25.0, "#FF9B9B"),
        ("Prejuizo 2023", 24.5, "#7AB8FF"),
        ("Capital adicional indicado", 13.0, "#C792EA"),
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
                            tooltip="Voltar para JEX ANALITICS",
                            icon_color="#F3F5F2",
                            bgcolor="#2A303B",
                            on_click=lambda _event: on_back(),
                        ), xs=2, sm=1, md=1, lg=1),
                        responsive_item(ft.Column(
                            [
                                ft.Text("Fotografia financeira JEX", size=24, weight=ft.FontWeight.BOLD),
                                ft.Text("Comparacao visual de magnitudes publicas selecionadas", size=14, color="#AEB6C2"),
                            ],
                            spacing=3,
                        ), xs=10, sm=11, md=11, lg=11),
                    ],
                    spacing=12,
                    run_spacing=8,
                ),
                ft.Container(
                    bgcolor="#2C2518",
                    border_radius=6,
                    padding=10,
                    content=ft.Text(
                        "Esta pizza nao representa composicao contabil do caixa. Ela cruza indicadores publicos distintos para mostrar onde se concentra a pressao financeira selecionada.",
                        size=13,
                        color="#FFD27A",
                    ),
                ),
                ft.ResponsiveRow(
                    [
                        responsive_item(ft.Container(
                            bgcolor="#20252F",
                            border_radius=8,
                            padding=16,
                            content=ft.Column(
                                [
                                    ft.Text("Distribuicao da pressao financeira", size=18, weight=ft.FontWeight.BOLD),
                                    ft.Text(
                                        "Percentual de cada indicador sobre a soma das pressoes publicas selecionadas.",
                                        size=13,
                                        color="#AEB6C2",
                                    ),
                                    jex_financial_pie_chart(items),
                                ],
                                spacing=10,
                                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                            ),
                        ), md=6, lg=4),
                        responsive_item(ft.Container(
                            bgcolor="#20252F",
                            border_radius=8,
                            padding=16,
                            content=ft.Column(
                                [
                                    ft.Text("Cruzamento com receita 2023", size=18, weight=ft.FontWeight.BOLD),
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
                                    ft.Container(height=1, bgcolor="#414A58"),
                                    analytics_text(
                                        "Objetivo da analise: identificar rapidamente a concentracao das pressoes financeiras e comparar sua materialidade com a receita publica de 2023."
                                    ),
                                    analytics_text(
                                        "Leitura: o deficit de capital de giro e a maior pressao selecionada. O conjunto das pressoes soma EUR 106,5 mi, equivalente a 95,1% da receita de referencia.",
                                        "#FFD27A",
                                    ),
                                ],
                                spacing=9,
                            ),
                        ), md=6, lg=4),
                        responsive_item(ft.Container(
                            bgcolor="#20252F",
                            border=ft.Border(
                                top=ft.BorderSide(1, "#343B47"),
                                right=ft.BorderSide(1, "#343B47"),
                                bottom=ft.BorderSide(1, "#343B47"),
                                left=ft.BorderSide(4, "#3E8E7E"),
                            ),
                            border_radius=8,
                            padding=16,
                            content=ft.Column(
                                [
                                    ft.Text("Resumo executivo", size=18, weight=ft.FontWeight.BOLD),
                                    ft.Text(
                                        "A fotografia mostra concentracao relevante no deficit de capital de giro: EUR 44,0 mi, ou 41,3% das pressoes selecionadas. Esse indicador representa sozinho 39,3% da receita publica de 2023."
                                        , size=13, color="#C9D1D9"
                                    ),
                                    ft.Text(
                                        "A divida tributaria citada e o prejuizo de 2023 possuem pesos semelhantes: 23,5% e 23,0% das pressoes. Juntos, somam EUR 49,5 mi."
                                        , size=13, color="#C9D1D9"
                                    ),
                                    ft.Text(
                                        "O capital adicional indicado corresponde a EUR 13,0 mi, ou 12,2% da fotografia. Esse valor sugere necessidade de reforco financeiro, mas deve ser revalidado com documentos posteriores."
                                        , size=13, color="#C9D1D9"
                                    ),
                                    ft.Container(height=1, bgcolor="#414A58"),
                                    ft.Text("Conclusao objetiva", size=16, weight=ft.FontWeight.BOLD, color="#FFD27A"),
                                    ft.Text(
                                        "Com base nos dados publicos selecionados, a JEX apresentava pressao financeira material frente a sua receita. A prioridade analitica e verificar se houve capitalizacao posterior e se a empresa conseguiu reduzir deficit de capital de giro, prejuizo e exposicao tributaria.",
                                        size=13,
                                        color="#F3F5F2",
                                    ),
                                    ft.Text(
                                        "Sem demonstracoes financeiras mais recentes e completas, nao e possivel concluir que a situacao atual melhorou ou piorou.",
                                        size=13,
                                        color="#AEB6C2",
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
        bgcolor="#1A1F28",
        border=ft.Border(
            top=ft.BorderSide(1, "#3E8E7E"),
            right=ft.BorderSide(1, "#414A58"),
            bottom=ft.BorderSide(1, "#414A58"),
            left=ft.BorderSide(1, "#414A58"),
        ),
        border_radius=6,
        padding=14,
        alignment=ft.Alignment(0, 0),
        content=ft.Column(
            [
                ft.Text(
                    "Pressao financeira significa dificuldade para manter dinheiro disponivel para pagar compromissos e sustentar a operacao. Nesta tela, o termo resume sinais publicos de alerta. Nao representa o total exato das dividas da empresa.",
                    size=12,
                    color="#C9D1D9",
                    text_align=ft.TextAlign.CENTER,
                ),
                ft.Text(
                    "Nota de transparencia: esta pesquisa foi elaborada com apoio de inteligencia artificial, a partir do cruzamento de diversas fontes financeiras publicas. As informacoes devem ser confirmadas nas fontes oficiais antes de qualquer decisao.",
                    size=12,
                    color="#FFD27A",
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
            paint=ft.Paint(color="#20252F", style=ft.PaintingStyle.FILL),
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
                        ft.Text("visao rapida", size=12, color="#AEB6C2", text_align=ft.TextAlign.CENTER),
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
                    ft.Text(label, size=13, color="#C9D1D9", expand=True),
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
            content=ft.Text("Poucos dados diarios para montar o grafico.", color="#AEB6C2"),
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
            paint=ft.Paint(color="#1B2029", style=ft.PaintingStyle.FILL),
        ),
        cv.Rect(
            x=pad_left,
            y=pad_top,
            width=chart_width,
            height=chart_height,
            border_radius=6,
            paint=ft.Paint(color="#1B2029", style=ft.PaintingStyle.FILL),
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
                paint=ft.Paint(color="#26303A", stroke_width=1),
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

    add_series(closes, "#8EE59A", 3)
    add_series(ma9, "#FFD27A", 2)
    add_series(ma20, "#7AB8FF", 2)
    shapes.append(
        cv.Circle(
            x=x_at(len(closes) - 1),
            y=y_at(closes[-1]),
            radius=4,
            paint=ft.Paint(color="#8EE59A", style=ft.PaintingStyle.FILL),
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
                content=ft.Text(price_text(value), size=10, color="#AEB6C2", text_align=ft.TextAlign.RIGHT),
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
                content=ft.Text(candles[index].time_label, size=10, color="#AEB6C2"),
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
                ft.Text(message, color="#FF9B9B"),
            ],
            spacing=12,
        ),
    )


def market_state_line(quote) -> ft.Control:
    label, color = market_state_label(quote.market_state)
    return ft.Text(label, size=9, color=color, weight=ft.FontWeight.BOLD)


def market_state_label(state: str | None) -> tuple[str, str]:
    labels = {
        "REGULAR": ("Aberto", "#8EE59A"),
        "PRE": ("Pre-mercado", "#FFD27A"),
        "PREPRE": ("Pre-mercado", "#FFD27A"),
        "POST": ("Pos-mercado", "#FFD27A"),
        "POSTPOST": ("Pos-mercado", "#FFD27A"),
        "CLOSED": ("Fechado", "#FF9B9B"),
    }
    return labels.get((state or "").upper(), ("Indisponivel", "#AEB6C2"))


def company_logo(quote, size: float = 22) -> ft.Control:
    if quote.symbol == "SSE Composite":
        return ft.Container(
            width=size,
            height=size,
            border_radius=size / 2,
            bgcolor="#39414D",
            clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
            content=ft.Image(src="/sse-composite.svg", width=size, height=size),
        )
    if quote.logo_url:
        return ft.Container(
            width=size,
            height=size,
            border_radius=size / 2,
            bgcolor="#39414D",
            clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
            content=ft.Image(src=quote.logo_url, width=size, height=size, gapless_playback=True),
        )
    return ft.Container(
        width=size,
        height=size,
        border_radius=size / 2,
        bgcolor="#39414D",
        alignment=ft.Alignment(0, 0),
        content=ft.Text(quote.symbol[:2], size=9 if size > 22 else 8, weight=ft.FontWeight.BOLD),
    )


if __name__ == "__main__":
    ft.run(main, assets_dir="assets")
