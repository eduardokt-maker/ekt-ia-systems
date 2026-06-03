from __future__ import annotations

import flet as ft
import flet.canvas as cv
import sqlite3
import time
from datetime import datetime, time as datetime_time
from pathlib import Path
from zoneinfo import ZoneInfo

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
INVESTMENT_DB_PATH = Path(__file__).with_name("investments.db")
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
]


def ensure_investment_db() -> None:
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


def save_investment_option(option: dict[str, str]) -> bool:
    ensure_investment_db()
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
    with sqlite3.connect(INVESTMENT_DB_PATH) as connection:
        rows = connection.execute(
            """
            SELECT product_name, category, created_at
            FROM investments
            ORDER BY id DESC
            """
        ).fetchall()
    return [(str(name), str(category), str(created_at)) for name, category, created_at in rows]


def main(page: ft.Page) -> None:
    page.title = "DESENVOLVIMENTO -EDUARDO KATSUM TAKAHASHI"
    page.theme_mode = ft.ThemeMode.DARK
    page.bgcolor = "#101214"
    page.padding = 0
    page.window.min_width = 280
    page.window.min_height = 460

    ibov_status = ft.Text("Carregando ativos do Ibovespa...", color="#AEB6C2", size=12)
    ai_status = ft.Text("Carregando ativos de IA dos EUA...", color="#AEB6C2", size=12)
    index_status = ft.Text("Carregando S&P 500, ES, EWZ, Nikkei e Xangai...", color="#AEB6C2", size=12)
    rare_earth_status = ft.Text("Carregando ativos globais de terras raras...", color="#AEB6C2", size=12)
    ibov_quotes_list = ft.Column(spacing=4)
    ai_quotes_list = ft.Column(spacing=4)
    index_quotes_list = ft.Column(spacing=4)
    rare_earth_quotes_list = ft.Column(spacing=4)
    search_input = ft.TextField(
        hint_text="Buscar ticker",
        dense=True,
        width=170,
        height=38,
        text_size=12,
        border_color="#2F3944",
        focused_border_color="#3E8E7E",
        bgcolor="#15191E",
        color="#F3F5F2",
        cursor_color="#3E8E7E",
        content_padding=ft.Padding(left=10, top=0, right=10, bottom=0),
    )
    search_status = ft.Text("Digite um ticker e pressione Enter.", color="#AEB6C2", size=11)
    search_suggestions = ft.Column(spacing=2)
    search_results = ft.Column(spacing=6)
    dashboard_status = ft.Text("Carregando indicadores...", color="#AEB6C2", size=12)
    dashboard_quotes = ft.Column(spacing=6)
    b3_market_status_dot = ft.Icon(ft.Icons.CIRCLE, size=10, color="#D6A756")
    b3_market_status = ft.Text("CONSULTANDO MERCADO", size=11, weight=ft.FontWeight.BOLD, color="#D6A756")
    b3_market_phase = ft.Text("Horario de Brasilia", size=10, color="#AEB6C2")
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
                    bgcolor={"": "#1D232B", "hovered": "#243B35"},
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
        now = datetime.now(ZoneInfo("America/Sao_Paulo"))
        regular_open = datetime_time(10, 0) <= now.time() < datetime_time(16, 55)
        closing_call = datetime_time(16, 55) <= now.time() <= datetime_time(17, 0)
        business_day = now.weekday() < 5
        if business_day and regular_open:
            b3_market_status.value = "MERCADO ABERTO"
            b3_market_status.color = "#5AC58E"
            b3_market_status_dot.color = "#5AC58E"
            b3_market_phase.value = "Negociacao regular em andamento"
        elif business_day and closing_call:
            b3_market_status.value = "CALL DE FECHAMENTO"
            b3_market_status.color = "#D6A756"
            b3_market_status_dot.color = "#D6A756"
            b3_market_phase.value = "Formacao do preco de fechamento"
        else:
            b3_market_status.value = "MERCADO FECHADO"
            b3_market_status.color = "#E57373"
            b3_market_status_dot.color = "#E57373"
            b3_market_phase.value = "Fora da sessao regular"

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
                )
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
        body.content = investments_login_view(render_home_screen, open_investments_form_screen)
        page.update()

    def open_investments_form_screen(_event=None) -> None:
        active_screen["name"] = "investments_form"
        body.content = investments_form_view(render_home_screen)
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
        page_width = page.width or 1200
        wide_layout = page_width >= 980
        column_width = min(max(page_width - 18, 280), 760)
        body.content = ft.Container(
            padding=ft.Padding(left=5, top=0, right=5, bottom=5),
            expand=True,
            content=ft.Column(
                [
                    ft.Row(
                        [
                            ft.IconButton(
                                icon=ft.Icons.ARROW_BACK,
                                tooltip="Voltar ao inicio",
                                icon_color="#F3F5F2",
                                bgcolor="#1D232B",
                                on_click=lambda _event: render_home_screen(),
                            ),
                            ft.Column(
                                [
                                    ft.Text("Ibovespa", size=16, weight=ft.FontWeight.BOLD),
                                    ft.Text("Ativos integrantes do indice | acompanhamento de cotacoes", size=11, color="#AEB6C2"),
                                ],
                                spacing=0,
                            ),
                            ft.Container(expand=True),
                            ft.Container(
                                bgcolor="#17372F",
                                border_radius=8,
                                padding=ft.Padding(left=8, top=4, right=8, bottom=4),
                                content=ft.Row(
                                    [
                                        ft.Icon(ft.Icons.CIRCLE, size=8, color="#5AC58E"),
                                        ft.Text("SINCRONIZACAO ATIVA", size=9, color="#8EE59A", weight=ft.FontWeight.BOLD),
                                    ],
                                    spacing=5,
                                ),
                            ),
                        ],
                        spacing=8,
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                    ft.Row(
                        [
                            market_column("Ibovespa", ibov_status, ibov_quotes_list, wide_layout, column_width),
                        ],
                        alignment=ft.MainAxisAlignment.CENTER,
                        vertical_alignment=ft.CrossAxisAlignment.START,
                        expand=True,
                    ),
                ],
                spacing=6,
            ),
        )
        page.update()

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
                                responsive_item(
                                    ft.Container(
                                        bgcolor="#15191E",
                                        border=ft.Border(
                                            top=ft.BorderSide(1, "#242B33"),
                                            right=ft.BorderSide(1, "#242B33"),
                                            bottom=ft.BorderSide(1, "#242B33"),
                                            left=ft.BorderSide(1, "#242B33"),
                                        ),
                                        border_radius=6,
                                        padding=ft.Padding(left=10, top=7, right=10, bottom=7),
                                        content=ft.Column(
                                            [
                                                ft.Row(
                                                    [b3_market_status_dot, b3_market_status],
                                                    spacing=6,
                                                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                                                ),
                                                b3_market_phase,
                                                ft.Text(
                                                    "B3 | Pregao regular: 10:00-16:55 | Call de fechamento: 16:55-17:00",
                                                    size=10,
                                                    color="#D5DBE3",
                                                ),
                                                ft.Text("Horario de Brasilia", size=9, color="#8F9AA8"),
                                            ],
                                            spacing=2,
                                        ),
                                    ),
                                    xs=12,
                                    sm=9,
                                    md=5,
                                    lg=5,
                                ),
                                responsive_item(ft.Text(
                                    f"Atualizacao automatica: Ibovespa {IBOV_REFRESH_SECONDS}s, mercados globais {FAST_REFRESH_SECONDS}s, indicadores {FULL_REFRESH_SECONDS}s. Fonte gratuita pode ter atraso.",
                                    size=11,
                                    color="#AEB6C2",
                                ), xs=12, sm=12, md=5, lg=5),
                            ],
                            spacing=12,
                            run_spacing=5,
                        ),
                    ),
                    body,
                    ft.Container(
                        border=ft.Border(
                            top=ft.BorderSide(1, "#242B33"),
                            right=ft.BorderSide(0, "#242B33"),
                            bottom=ft.BorderSide(0, "#242B33"),
                            left=ft.BorderSide(0, "#242B33"),
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
        bgcolor="#15191E",
        border=ft.Border(
            top=ft.BorderSide(1, "#242B33"),
            right=ft.BorderSide(1, "#242B33"),
            bottom=ft.BorderSide(1, "#242B33"),
            left=ft.BorderSide(1, "#242B33"),
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
        border_color="#2F3944",
        focused_border_color="#4F8CFF",
        bgcolor="#101419",
        color="#F3F5F2",
        cursor_color="#4F8CFF",
    )
    password_input = ft.TextField(
        label="Senha",
        dense=True,
        password=True,
        border_color="#2F3944",
        focused_border_color="#4F8CFF",
        bgcolor="#101419",
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
                            bgcolor="#1D232B",
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
                    bgcolor="#15191E",
                    border=ft.Border(
                        top=ft.BorderSide(1, "#242B33"),
                        right=ft.BorderSide(1, "#242B33"),
                        bottom=ft.BorderSide(1, "#242B33"),
                        left=ft.BorderSide(1, "#242B33"),
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


def investments_form_view(on_back) -> ft.Control:
    ensure_investment_db()
    saved_column = ft.Column(spacing=6)
    save_status = ft.Text("Selecione um ativo da lista para cadastrar no banco de dados.", size=11, color="#AEB6C2")

    def saved_investment_card(name: str, category: str, created_at: str) -> ft.Control:
        return ft.Container(
            bgcolor="#101419",
            border=ft.Border(
                top=ft.BorderSide(1, "#242B33"),
                right=ft.BorderSide(1, "#242B33"),
                bottom=ft.BorderSide(1, "#242B33"),
                left=ft.BorderSide(1, "#242B33"),
            ),
            border_radius=8,
            padding=ft.Padding(left=10, top=7, right=10, bottom=7),
            content=ft.Row(
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
                ],
                spacing=8,
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
        )

    def refresh_saved_list() -> None:
        rows = load_saved_investments()
        if not rows:
            saved_column.controls = [
                ft.Text("Nenhum investimento cadastrado ainda.", size=11, color="#AEB6C2")
            ]
            return
        saved_column.controls = [saved_investment_card(name, category, created_at) for name, category, created_at in rows]

    def register_investment(option: dict[str, str]) -> None:
        inserted = save_investment_option(option)
        save_status.value = (
            f"{option['name']} cadastrado no banco de dados."
            if inserted
            else f"{option['name']} ja estava cadastrado."
        )
        save_status.color = "#8EE59A" if inserted else "#FFD27A"
        refresh_saved_list()
        save_status.update()
        saved_column.update()

    def focus_investment_list(_event=None) -> None:
        save_status.value = "Clique em um ativo da lista Santander para cadastrar no banco de dados."
        save_status.color = "#4F8CFF"
        save_status.update()

    def santander_option_card(option: dict[str, str]) -> ft.Control:
        return ft.Container(
            bgcolor="#15191E",
            border=ft.Border(
                top=ft.BorderSide(1, "#242B33"),
                right=ft.BorderSide(1, "#242B33"),
                bottom=ft.BorderSide(1, "#242B33"),
                left=ft.BorderSide(1, "#242B33"),
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
                            bgcolor="#1D232B",
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
                    bgcolor="#15191E",
                    border=ft.Border(
                        top=ft.BorderSide(1, "#242B33"),
                        right=ft.BorderSide(1, "#242B33"),
                        bottom=ft.BorderSide(1, "#242B33"),
                        left=ft.BorderSide(1, "#242B33"),
                    ),
                    border_radius=8,
                    padding=16,
                    content=ft.Column(
                        [
                            ft.Text("ok . passou", size=14, color="#8EE59A", weight=ft.FontWeight.BOLD),
                            ft.FilledButton(
                                "Cadastrar meus investimentos",
                                icon=ft.Icons.ADD,
                                on_click=focus_investment_list,
                                style=ft.ButtonStyle(bgcolor="#4F8CFF", color="#F8FAFC"),
                            ),
                            save_status,
                            ft.Text("Renda fixa Santander - lista inicial", size=15, weight=ft.FontWeight.BOLD),
                            ft.Text(
                                "Clique em um ativo para cadastrar. Taxas e disponibilidade devem ser confirmadas no Santander antes da aplicacao.",
                                size=11,
                                color="#AEB6C2",
                            ),
                            ft.ResponsiveRow(
                                [
                                    responsive_item(santander_option_card(option), xs=12, sm=12, md=6, lg=6)
                                    for option in SANTANDER_FIXED_INCOME_OPTIONS
                                ],
                                spacing=10,
                                run_spacing=10,
                            ),
                            ft.Text("Meus investimentos cadastrados", size=15, weight=ft.FontWeight.BOLD),
                            saved_column,
                        ],
                        spacing=11,
                    ),
                ),
            ],
            spacing=16,
            scroll=ft.ScrollMode.AUTO,
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
                    bgcolor="#171B20",
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
        padding=ft.Padding(left=7, top=6, right=7, bottom=6),
        on_click=on_click,
        ink=True,
        tooltip=tooltip or label,
        content=ft.Row(
            [
                ft.Icon(icon, size=15, color="#C4A7FF"),
                ft.Text(
                    label,
                    size=10,
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
        bgcolor="#1C2128",
        border=ft.Border(
            top=ft.BorderSide(0, "#1D232B"),
            right=ft.BorderSide(0, "#1D232B"),
            bottom=ft.BorderSide(2, "#3E8E7E"),
            left=ft.BorderSide(0, "#1D232B"),
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
        bgcolor="#15191E",
        data={"base_bg": "#15191E", "blink_bg": blink_bg, "key": quote.symbol},
        animate=ft.Animation(180, ft.AnimationCurve.EASE_IN_OUT),
        border=ft.Border(
            top=ft.BorderSide(1, "#242B33"),
            right=ft.BorderSide(1, "#242B33"),
            bottom=ft.BorderSide(1, "#242B33"),
            left=ft.BorderSide(1, "#242B33"),
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
) -> ft.Control:
    change = quote.change_percent
    change_color = "#8EE59A" if change is not None and change >= 0 else "#FF9B9B"
    change_text = "-" if change is None else f"{change:.2f}%"
    return ft.Container(
        bgcolor="#171B20",
        data={"base_bg": "#171B20", "blink_bg": "#23483D", "key": quote.symbol},
        animate=ft.Animation(180, ft.AnimationCurve.EASE_IN_OUT),
        border=ft.Border(
            top=ft.BorderSide(1, "#242B33"),
            right=ft.BorderSide(1, "#242B33"),
            bottom=ft.BorderSide(1, "#242B33"),
            left=ft.BorderSide(1, "#242B33"),
        ),
        border_radius=8,
        padding=ft.Padding(left=8, top=6, right=8, bottom=6),
        on_click=(lambda _event: on_click(quote)) if on_click and quote.symbol == "SSE Composite" else None,
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.Row(
                            [
                                company_logo(quote),
                                ft.Text(quote.symbol, size=12, weight=ft.FontWeight.BOLD),
                            ],
                            spacing=5,
                            vertical_alignment=ft.CrossAxisAlignment.CENTER,
                        ),
                        ft.Text(change_text, size=10, color=change_color, weight=ft.FontWeight.BOLD),
                    ],
                    alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                ),
                ft.Row(
                    [
                        ft.Text(price_text(quote.price, quote.currency), size=13, weight=ft.FontWeight.BOLD),
                        market_state_line(quote) if show_market_state else ft.Container(width=0, height=0),
                    ],
                    alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                asset_name_line(quote),
                ft.Row(
                    [
                        ft.Text(quote.market_time or "-", size=9, color="#AEB6C2"),
                        freshness_badge(freshness_note),
                    ],
                    alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
            ],
            spacing=1,
        ),
    )


def asset_name_line(quote) -> ft.Control:
    return ft.Row(
        [
            ft.Text(
                quote.name or "Ativo do Ibovespa",
                color="#C9D1D9",
                size=10,
                max_lines=1,
                overflow=ft.TextOverflow.ELLIPSIS,
                expand=True,
            ),
            exchange_badge(quote.exchange),
        ],
        spacing=6,
        vertical_alignment=ft.CrossAxisAlignment.CENTER,
    )


def freshness_badge(note: str | None) -> ft.Control:
    if not note:
        return ft.Container(width=0, height=0)
    changed = note == "nova variacao"
    return ft.Container(
        bgcolor="#1E3A32" if changed else "#232A32",
        border_radius=4,
        padding=ft.Padding(left=4, top=1, right=4, bottom=1),
        content=ft.Text(
            note,
            size=7,
            color="#8EE59A" if changed else "#AEB6C2",
            weight=ft.FontWeight.BOLD,
        ),
    )


def exchange_badge(exchange: str | None) -> ft.Control:
    if not exchange:
        return ft.Container(width=0, height=0)
    return ft.Container(
        bgcolor="#222A33",
        border_radius=4,
        padding=ft.Padding(left=4, top=1, right=4, bottom=1),
        content=ft.Text(exchange, size=7, color="#AEB6C2", weight=ft.FontWeight.BOLD),
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
                    bgcolor="#15191E",
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
        bgcolor="#11161B",
        border=ft.Border(
            top=ft.BorderSide(1, "#2C3742"),
            right=ft.BorderSide(1, "#2C3742"),
            bottom=ft.BorderSide(1, "#2C3742"),
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
                ft.Container(height=1, bgcolor="#2C3742"),
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
        bgcolor="#15191E",
        border=ft.Border(
            top=ft.BorderSide(1, "#242B33"),
            right=ft.BorderSide(1, "#242B33"),
            bottom=ft.BorderSide(1, "#242B33"),
            left=ft.BorderSide(1, "#242B33"),
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
                                    bgcolor="#1D232B",
                                    on_click=lambda _event: update_chart_zoom(-0.1),
                                ),
                                zoom_label,
                                ft.IconButton(
                                    icon=ft.Icons.ADD,
                                    tooltip="Aumentar zoom",
                                    icon_color="#F3F5F2",
                                    bgcolor="#1D232B",
                                    on_click=lambda _event: update_chart_zoom(0.1),
                                ),
                                ft.IconButton(
                                    icon=ft.Icons.CENTER_FOCUS_STRONG,
                                    tooltip="Resetar zoom",
                                    icon_color="#F3F5F2",
                                    bgcolor="#1D232B",
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
                    bgcolor="#101419",
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
                            bgcolor="#1D232B",
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
        bgcolor="#15191E",
        border=ft.Border(
            top=ft.BorderSide(1, "#242B33"),
            right=ft.BorderSide(1, "#242B33"),
            bottom=ft.BorderSide(1, "#242B33"),
            left=ft.BorderSide(1, "#242B33"),
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
        padding=ft.Padding(left=14, top=6, right=14, bottom=18),
        content=ft.Column(
            [
                ft.ResponsiveRow(
                    [
                        responsive_item(ft.IconButton(
                            icon=ft.Icons.ARROW_BACK,
                            tooltip="Voltar",
                            icon_color="#F3F5F2",
                            bgcolor="#1D232B",
                            on_click=lambda _event: on_back(),
                        ), xs=2, sm=1, md=1, lg=1),
                        responsive_item(ft.Column(
                            [
                                ft.Text("JEX", size=22, weight=ft.FontWeight.BOLD),
                                ft.Text("Perfil institucional e historico publico consolidado", size=12, color="#AEB6C2"),
                            ],
                            spacing=1,
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
            spacing=12,
            scroll=ft.ScrollMode.AUTO,
        ),
    )


def jex_profile_panel() -> ft.Control:
    return ft.Container(
        bgcolor="#15191E",
        border=ft.Border(
            top=ft.BorderSide(1, "#242B33"),
            right=ft.BorderSide(1, "#242B33"),
            bottom=ft.BorderSide(1, "#242B33"),
            left=ft.BorderSide(4, "#3E8E7E"),
        ),
        border_radius=8,
        padding=14,
        content=ft.Column(
            [
                ft.Text("Dados da empresa", size=15, weight=ft.FontWeight.BOLD),
                jex_info_row("Razao social", "JEX Nederland B.V."),
                jex_info_row("Natureza juridica", "Besloten vennootschap (B.V.)"),
                jex_info_row("Registro KVK", "85002976"),
                jex_info_row("Estabelecimento", "000051083825"),
                jex_info_row("Sede", "Rotterdam, Paises Baixos"),
                jex_info_row("Endereco", "Nassaukade 5, 3071 JL Rotterdam"),
                jex_info_row("Atividade cadastral", "Atividades de sedes administrativas"),
                jex_info_row("Situacao em bolsa", "Empresa privada. Sem ticker publico."),
                ft.Container(height=1, bgcolor="#2C3742"),
                ft.Text("Atuacao declarada", size=13, weight=ft.FontWeight.BOLD),
                ft.Text(
                    "Software, servicos empresariais, recrutamento, backoffice e solucoes de vendas com IA.",
                    size=12,
                    color="#C9D1D9",
                ),
            ],
            spacing=9,
        ),
    )


def jex_info_row(label: str, value: str) -> ft.Control:
    return ft.Column(
        [
            ft.Text(label.upper(), size=9, color="#AEB6C2", weight=ft.FontWeight.BOLD),
            ft.Text(value, size=12, color="#F3F5F2"),
        ],
        spacing=1,
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
        bgcolor="#15191E",
        border=ft.Border(
            top=ft.BorderSide(1, "#242B33"),
            right=ft.BorderSide(1, "#242B33"),
            bottom=ft.BorderSide(1, "#242B33"),
            left=ft.BorderSide(1, "#242B33"),
        ),
        border_radius=8,
        padding=14,
        content=ft.Column(
            [
                ft.Text("Linha do tempo publica", size=15, weight=ft.FontWeight.BOLD),
                ft.Text(
                    "Resumo baseado em fontes publicas. Nao substitui certidao oficial nem auditoria.",
                    size=11,
                    color="#AEB6C2",
                ),
                *[jex_timeline_item(year, title, description) for year, title, description in items],
            ],
            spacing=10,
        ),
    )


def jex_timeline_item(year: str, title: str, description: str) -> ft.Control:
    return ft.Container(
        border=ft.Border(
            top=ft.BorderSide(0, "#242B33"),
            right=ft.BorderSide(0, "#242B33"),
            bottom=ft.BorderSide(0, "#242B33"),
            left=ft.BorderSide(3, "#3E8E7E"),
        ),
        padding=ft.Padding(left=10, top=3, right=4, bottom=3),
        content=ft.Column(
            [
                ft.Row(
                    [
                        ft.Text(year, size=11, color="#8EE59A", weight=ft.FontWeight.BOLD),
                        ft.Text(title, size=12, weight=ft.FontWeight.BOLD),
                    ],
                    spacing=8,
                ),
                ft.Text(description, size=11, color="#C9D1D9"),
            ],
            spacing=3,
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
        bgcolor="#11161B",
        border=ft.Border(
            top=ft.BorderSide(1, "#2C3742"),
            right=ft.BorderSide(1, "#2C3742"),
            bottom=ft.BorderSide(1, "#2C3742"),
            left=ft.BorderSide(1, "#2C3742"),
        ),
        border_radius=8,
        padding=12,
        content=ft.Column(
            [
                ft.Text("Fontes para verificacao", size=14, weight=ft.FontWeight.BOLD),
                ft.Text(
                    "Para diligencia formal, consulte o KVK e solicite o extrato oficial atualizado.",
                    size=11,
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
        padding=ft.Padding(left=14, top=6, right=14, bottom=18),
        content=ft.Column(
            [
                ft.ResponsiveRow(
                    [
                        responsive_item(ft.IconButton(
                            icon=ft.Icons.ARROW_BACK,
                            tooltip="Voltar para JEX",
                            icon_color="#F3F5F2",
                            bgcolor="#1D232B",
                            on_click=lambda _event: on_back(),
                        ), xs=2, sm=1, md=1, lg=1),
                        responsive_item(ft.Column(
                            [
                                ft.Text("JEX ANALITICS", size=22, weight=ft.FontWeight.BOLD),
                                ft.Text("Analise baseada exclusivamente em informacoes publicas disponiveis", size=12, color="#AEB6C2"),
                            ],
                            spacing=1,
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
                        size=11,
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
            spacing=12,
            scroll=ft.ScrollMode.AUTO,
        ),
    )
def analytics_panel(title: str, controls: list[ft.Control], width: float = 510) -> ft.Control:
    return ft.Container(
        bgcolor="#15191E",
        border=ft.Border(
            top=ft.BorderSide(1, "#242B33"),
            right=ft.BorderSide(1, "#242B33"),
            bottom=ft.BorderSide(1, "#242B33"),
            left=ft.BorderSide(3, "#3E8E7E"),
        ),
        border_radius=8,
        padding=14,
        content=ft.Column(
            [
                ft.Text(title, size=15, weight=ft.FontWeight.BOLD),
                *controls,
            ],
            spacing=8,
        ),
    )


def analytics_text(text: str, color: str = "#C9D1D9") -> ft.Control:
    return ft.Text(text, size=11, color=color)


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
        bgcolor="#11161B",
        border_radius=8,
        padding=12,
        content=ft.Column(
            [
                ft.Text("Fontes da analise", size=14, weight=ft.FontWeight.BOLD),
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
        padding=ft.Padding(left=14, top=6, right=14, bottom=18),
        content=ft.Column(
            [
                ft.ResponsiveRow(
                    [
                        responsive_item(ft.IconButton(
                            icon=ft.Icons.ARROW_BACK,
                            tooltip="Voltar para JEX ANALITICS",
                            icon_color="#F3F5F2",
                            bgcolor="#1D232B",
                            on_click=lambda _event: on_back(),
                        ), xs=2, sm=1, md=1, lg=1),
                        responsive_item(ft.Column(
                            [
                                ft.Text("Fotografia financeira JEX", size=22, weight=ft.FontWeight.BOLD),
                                ft.Text("Comparacao visual de magnitudes publicas selecionadas", size=12, color="#AEB6C2"),
                            ],
                            spacing=1,
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
                        size=11,
                        color="#FFD27A",
                    ),
                ),
                ft.ResponsiveRow(
                    [
                        responsive_item(ft.Container(
                            bgcolor="#15191E",
                            border_radius=8,
                            padding=12,
                            content=ft.Column(
                                [
                                    ft.Text("Distribuicao da pressao financeira", size=15, weight=ft.FontWeight.BOLD),
                                    ft.Text(
                                        "Percentual de cada indicador sobre a soma das pressoes publicas selecionadas.",
                                        size=11,
                                        color="#AEB6C2",
                                    ),
                                    jex_financial_pie_chart(items),
                                ],
                                spacing=10,
                                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                            ),
                        ), md=6, lg=4),
                        responsive_item(ft.Container(
                            bgcolor="#15191E",
                            border_radius=8,
                            padding=12,
                            content=ft.Column(
                                [
                                    ft.Text("Cruzamento com receita 2023", size=15, weight=ft.FontWeight.BOLD),
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
                                    ft.Container(height=1, bgcolor="#2C3742"),
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
                            bgcolor="#15191E",
                            border=ft.Border(
                                top=ft.BorderSide(1, "#242B33"),
                                right=ft.BorderSide(1, "#242B33"),
                                bottom=ft.BorderSide(1, "#242B33"),
                                left=ft.BorderSide(4, "#3E8E7E"),
                            ),
                            border_radius=8,
                            padding=12,
                            content=ft.Column(
                                [
                                    ft.Text("Resumo executivo", size=15, weight=ft.FontWeight.BOLD),
                                    ft.Text(
                                        "A fotografia mostra concentracao relevante no deficit de capital de giro: EUR 44,0 mi, ou 41,3% das pressoes selecionadas. Esse indicador representa sozinho 39,3% da receita publica de 2023."
                                        , size=10, color="#C9D1D9"
                                    ),
                                    ft.Text(
                                        "A divida tributaria citada e o prejuizo de 2023 possuem pesos semelhantes: 23,5% e 23,0% das pressoes. Juntos, somam EUR 49,5 mi."
                                        , size=10, color="#C9D1D9"
                                    ),
                                    ft.Text(
                                        "O capital adicional indicado corresponde a EUR 13,0 mi, ou 12,2% da fotografia. Esse valor sugere necessidade de reforco financeiro, mas deve ser revalidado com documentos posteriores."
                                        , size=10, color="#C9D1D9"
                                    ),
                                    ft.Container(height=1, bgcolor="#2C3742"),
                                    ft.Text("Conclusao objetiva", size=14, weight=ft.FontWeight.BOLD, color="#FFD27A"),
                                    ft.Text(
                                        "Com base nos dados publicos selecionados, a JEX apresentava pressao financeira material frente a sua receita. A prioridade analitica e verificar se houve capitalizacao posterior e se a empresa conseguiu reduzir deficit de capital de giro, prejuizo e exposicao tributaria.",
                                        size=10,
                                        color="#F3F5F2",
                                    ),
                                    ft.Text(
                                        "Sem demonstracoes financeiras mais recentes e completas, nao e possivel concluir que a situacao atual melhorou ou piorou.",
                                        size=10,
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
        bgcolor="#11161B",
        border=ft.Border(
            top=ft.BorderSide(1, "#3E8E7E"),
            right=ft.BorderSide(1, "#2C3742"),
            bottom=ft.BorderSide(1, "#2C3742"),
            left=ft.BorderSide(1, "#2C3742"),
        ),
        border_radius=6,
        padding=10,
        alignment=ft.Alignment(0, 0),
        content=ft.Column(
            [
                ft.Text(
                    "Pressao financeira significa dificuldade para manter dinheiro disponivel para pagar compromissos e sustentar a operacao. Nesta tela, o termo resume sinais publicos de alerta. Nao representa o total exato das dividas da empresa.",
                    size=10,
                    color="#C9D1D9",
                    text_align=ft.TextAlign.CENTER,
                ),
                ft.Text(
                    "Nota de transparencia: esta pesquisa foi elaborada com apoio de inteligencia artificial, a partir do cruzamento de diversas fontes financeiras publicas. As informacoes devem ser confirmadas nas fontes oficiais antes de qualquer decisao.",
                    size=10,
                    color="#FFD27A",
                    text_align=ft.TextAlign.CENTER,
                ),
            ],
            spacing=4,
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
            paint=ft.Paint(color="#15191E", style=ft.PaintingStyle.FILL),
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
                        ft.Text("JEX", size=20, weight=ft.FontWeight.BOLD, text_align=ft.TextAlign.CENTER),
                        ft.Text("visao rapida", size=10, color="#AEB6C2", text_align=ft.TextAlign.CENTER),
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
                    ft.Text(label, size=11, color="#C9D1D9", expand=True),
                    ft.Text(f"EUR {value:.1f} mi", size=11, weight=ft.FontWeight.BOLD),
                ],
                spacing=7,
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            ft.Text(
                f"{pressure_percent:.1f}% das pressoes | {revenue_percent:.1f}% da receita",
                size=10,
                color=color,
            ),
        ],
        spacing=2,
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
            paint=ft.Paint(color="#101419", style=ft.PaintingStyle.FILL),
        ),
        cv.Rect(
            x=pad_left,
            y=pad_top,
            width=chart_width,
            height=chart_height,
            border_radius=6,
            paint=ft.Paint(color="#101419", style=ft.PaintingStyle.FILL),
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


def company_logo(quote) -> ft.Control:
    if quote.symbol == "SSE Composite":
        return ft.Container(
            width=22,
            height=22,
            border_radius=11,
            bgcolor="#2A3038",
            clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
            content=ft.Image(src="/sse-composite.svg", width=22, height=22),
        )
    if quote.logo_url:
        return ft.Container(
            width=22,
            height=22,
            border_radius=11,
            bgcolor="#2A3038",
            clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
            content=ft.Image(src=quote.logo_url, width=22, height=22, gapless_playback=True),
        )
    return ft.Container(
        width=22,
        height=22,
        border_radius=11,
        bgcolor="#2A3038",
        alignment=ft.Alignment(0, 0),
        content=ft.Text(quote.symbol[:2], size=8, weight=ft.FontWeight.BOLD),
    )


if __name__ == "__main__":
    ft.run(main, assets_dir="assets")
