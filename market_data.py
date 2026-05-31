from __future__ import annotations

import os
import base64
import concurrent.futures
import json
import re
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, time, timedelta
from pathlib import Path
from urllib.parse import quote
from zoneinfo import ZoneInfo

import httpx


BRAPI_BASE_URL = "https://brapi.dev/api"
B3_INDEX_BASE_URL = "https://sistemaswebb3-listados.b3.com.br"
YAHOO_CHART_BASE_URL = "https://query1.finance.yahoo.com/v8/finance/chart"
YAHOO_CHART_FALLBACK_BASE_URL = "https://query2.finance.yahoo.com/v8/finance/chart"
TRADINGVIEW_SCAN_URL = "https://scanner.tradingview.com/america/scan"
TRADINGVIEW_BRAZIL_SCAN_URL = "https://scanner.tradingview.com/brazil/scan"
TRADINGVIEW_FOREX_SCAN_URL = "https://scanner.tradingview.com/forex/scan"
DEFAULT_MARKET_TICKERS = "^BVSP,PETR4,VALE3,ITUB4,MGLU3"
US_AI_TICKERS = "NVDA,MSFT,GOOGL,AMZN,META,AMD,AVGO,TSM,ASML,ARM,PLTR,ORCL,MU,SMCI,AI"
US_INDEX_TICKERS = "SP:SPX,AMEX:EWZ"
RARE_EARTH_TICKERS = "REMX,MP,LYC.AX,UUUU,NEO.TO,ILU.AX,USAR,CRML,IPX,NB"
EMINI_SP500_TICKER = "ES=F"
NIKKEI_TICKER = "^N225"
SHANGHAI_TICKER = "000001.SS"
IBOV_INDEX_SYMBOL = "BMFBOVESPA:IBOV"
IBOV_FUTURE_SYMBOL = "BMFBOVESPA:IND1!"
DOLLAR_BRL_SYMBOL = "FX_IDC:USDBRL"
US_LOGO_URLS = {
    "NVDA": "https://s3-symbol-logo.tradingview.com/nvidia.svg",
    "MSFT": "https://s3-symbol-logo.tradingview.com/microsoft.svg",
    "GOOGL": "https://s3-symbol-logo.tradingview.com/alphabet.svg",
    "AMZN": "https://s3-symbol-logo.tradingview.com/amazon.svg",
    "META": "https://s3-symbol-logo.tradingview.com/meta-platforms.svg",
    "AMD": "https://s3-symbol-logo.tradingview.com/advanced-micro-devices.svg",
    "AVGO": "https://s3-symbol-logo.tradingview.com/broadcom.svg",
    "TSM": "https://s3-symbol-logo.tradingview.com/taiwan-semiconductor.svg",
    "ASML": "https://s3-symbol-logo.tradingview.com/asml.svg",
    "ARM": "https://s3-symbol-logo.tradingview.com/arm-holdings.svg",
    "PLTR": "https://s3-symbol-logo.tradingview.com/palantir.svg",
    "ORCL": "https://s3-symbol-logo.tradingview.com/oracle.svg",
    "MU": "https://s3-symbol-logo.tradingview.com/micron-technology.svg",
    "SMCI": "https://s3-symbol-logo.tradingview.com/super-micro-computer.svg",
    "AI": "https://s3-symbol-logo.tradingview.com/c3-ai.svg",
    "SP:SPX": "https://s3-symbol-logo.tradingview.com/indices/s-and-p-500.svg",
    "EWZ": "https://s3-symbol-logo.tradingview.com/ishares.svg",
    "AMEX:EWZ": "https://s3-symbol-logo.tradingview.com/ishares.svg",
    "CME_MINI:ES1!": "https://s3-symbol-logo.tradingview.com/indices/s-and-p-500.svg",
    "ES=F": "https://s3-symbol-logo.tradingview.com/indices/s-and-p-500.svg",
    "^N225": "https://s3-symbol-logo.tradingview.com/indices/nikkei-225.svg",
}
US_EXCHANGES = {
    "NVDA": "NASDAQ",
    "MSFT": "NASDAQ",
    "GOOGL": "NASDAQ",
    "AMZN": "NASDAQ",
    "META": "NASDAQ",
    "AMD": "NASDAQ",
    "AVGO": "NASDAQ",
    "TSM": "NYSE",
    "ASML": "NASDAQ",
    "ARM": "NASDAQ",
    "PLTR": "NASDAQ",
    "ORCL": "NYSE",
    "MU": "NASDAQ",
    "SMCI": "NASDAQ",
    "AI": "NYSE",
    "SP:SPX": "S&P Dow Jones Indices",
    "EWZ": "NYSE Arca",
    "AMEX:EWZ": "NYSE Arca",
    "CME_MINI:ES1!": "CME Globex",
    "ES=F": "CME Globex",
    "^N225": "Tokyo Stock Exchange",
    "000001.SS": "Shanghai Stock Exchange",
    "MP": "NYSE",
    "LYC.AX": "ASX",
    "UUUU": "NYSE American",
    "NEO.TO": "TSX",
    "ILU.AX": "ASX",
    "USAR": "NASDAQ",
    "CRML": "NASDAQ",
    "IPX": "NASDAQ",
    "NB": "NASDAQ",
    "REMX": "NYSE Arca",
}
IBOVESPA_FALLBACK_TICKERS = (
    "ABEV3,ALOS3,ASAI3,AURE3,AXIA3,AXIA6,AZUL4,B3SA3,BBAS3,BBDC3,BBDC4,BBSE3,"
    "BEEF3,BPAC11,BRAP4,BRAV3,BRFS3,BRKM5,CCRO3,CMIG4,CMIN3,COGN3,CPFE3,CPLE6,"
    "CRFB3,CSAN3,CSNA3,CURY3,CVCB3,CXSE3,CYRE3,DIRR3,EGIE3,ELET3,ELET6,EMBJ3,"
    "ENEV3,ENGI11,EQTL3,FLRY3,GGBR4,GOAU4,HAPV3,HYPE3,IGTI11,IRBR3,ITSA4,ITUB4,"
    "JBSS3,KLBN11,LREN3,MGLU3,MOTV3,MRFG3,MRVE3,MULT3,NTCO3,PCAR3,PETR3,PETR4,"
    "PETZ3,PINE4,POMO3,PRIO3,RADL3,RAIL3,RAIZ4,RDOR3,RECV3,RENT3,SANB11,SBSP3,"
    "SLCE3,SMFT3,SMTO3,SUZB3,TAEE11,TOTS3,UGPA3,USIM5,VALE3,VAMO3,VBBR3,VIVA3,"
    "VIVT3,WEGE3,YDUQ3"
)
SEARCH_SYMBOL_ALIASES = {
    "EMBRAER": "EMBJ3",
    "EMBR3": "EMBJ3",
}
DAILY_CANDLE_CACHE_TTL = timedelta(minutes=5)
_DAILY_CANDLE_CACHE: dict[tuple[str, str, str], tuple[datetime, list["Candle"]]] = {}


@dataclass
class MarketQuote:
    symbol: str
    name: str
    price: float | None
    change: float | None
    change_percent: float | None
    volume: float | None
    market_time: str | None
    logo_url: str | None = None
    exchange: str | None = None
    market_state: str | None = None
    source_symbol: str | None = None
    currency: str | None = None


@dataclass
class Candle:
    time_label: str
    open: float
    high: float
    low: float
    close: float


def fetch_market_quotes(tickers: str = DEFAULT_MARKET_TICKERS) -> list[MarketQuote]:
    cleaned_tickers = normalize_tickers(tickers)
    if not cleaned_tickers:
        raise ValueError("Informe ao menos um ticker.")
    try:
        return fetch_brapi_quotes(cleaned_tickers)
    except Exception:
        return fetch_yahoo_quotes(cleaned_tickers)


def stream_market_quotes(
    tickers: str,
    on_quote: Callable[[MarketQuote], None],
    on_progress: Callable[[int, int], None] | None = None,
) -> int:
    cleaned_tickers = normalize_tickers(tickers)
    if not cleaned_tickers:
        raise ValueError("Informe ao menos um ticker.")

    symbols = cleaned_tickers.split(",")
    try:
        quotes = fetch_brapi_quotes(cleaned_tickers)
    except Exception:
        return stream_yahoo_quotes(symbols, on_quote, on_progress)

    for index, quote in enumerate(quotes, start=1):
        on_quote(quote)
        if on_progress:
            on_progress(index, len(quotes))
    return len(quotes)


def stream_brazil_tradingview_quotes(
    tickers: str,
    on_quote: Callable[[MarketQuote], None],
    on_progress: Callable[[int, int], None] | None = None,
) -> int:
    cleaned_tickers = normalize_tickers(tickers)
    if not cleaned_tickers:
        raise ValueError("Informe ao menos um ticker.")
    tradingview_symbols = ",".join(f"BMFBOVESPA:{symbol}" for symbol in cleaned_tickers.split(","))
    try:
        quotes = fetch_tradingview_quotes(tradingview_symbols, scan_url=TRADINGVIEW_BRAZIL_SCAN_URL)
    except Exception:
        quotes = []
    if not quotes:
        raise ValueError("TradingView nao retornou cotacoes da B3 neste momento.")
    for index, quote in enumerate(quotes, start=1):
        on_quote(quote)
        if on_progress:
            on_progress(index, len(quotes))
    return len(quotes)


def is_brazil_market_open() -> bool:
    return regular_brazil_market_state() == "REGULAR"


def is_us_stock_market_open() -> bool:
    return regular_us_market_state() == "REGULAR"


def is_cme_equity_futures_market_open() -> bool:
    return regular_cme_equity_futures_state() == "REGULAR"


def is_japan_market_open() -> bool:
    return regular_japan_market_state() == "REGULAR"


def is_shanghai_market_open() -> bool:
    return regular_shanghai_market_state() == "REGULAR"


def is_forex_market_open() -> bool:
    now = datetime.now(ZoneInfo("America/New_York"))
    if now.weekday() == 5:
        return False
    if now.weekday() == 6 and now.time() < time(17, 0):
        return False
    if now.weekday() == 4 and now.time() >= time(17, 0):
        return False
    return True


def is_any_index_market_open() -> bool:
    states = [
        regular_us_market_state(),
        regular_cme_equity_futures_state(),
        regular_japan_market_state(),
        regular_shanghai_market_state(),
    ]
    return any(state == "REGULAR" for state in states)


def fetch_brazil_dashboard_quotes() -> tuple[MarketQuote, MarketQuote]:
    return fetch_ibov_dashboard_quote(), fetch_dollar_brl_quote()


def fetch_ibov_dashboard_quote() -> MarketQuote:
    ibov_quotes = fetch_tradingview_quotes(
        IBOV_INDEX_SYMBOL,
        scan_url=TRADINGVIEW_BRAZIL_SCAN_URL,
    )
    if not ibov_quotes:
        raise ValueError("Nao foi possivel carregar IBOV.")
    ibov = ibov_quotes[0]
    ibov.symbol = "IBOV"
    ibov.name = "Ibovespa"
    ibov.exchange = "B3"
    ibov.currency = "BRL"
    return ibov


def fetch_ibov_future_quote() -> MarketQuote:
    future_quotes = fetch_tradingview_quotes(
        IBOV_FUTURE_SYMBOL,
        scan_url=TRADINGVIEW_BRAZIL_SCAN_URL,
    )
    if not future_quotes:
        raise ValueError("Nao foi possivel carregar o indice futuro.")
    future = future_quotes[0]
    future.symbol = "IND"
    future.name = "Futuro de Ibovespa"
    future.exchange = "B3"
    future.currency = "BRL"
    return future


def fetch_dollar_brl_quote() -> MarketQuote:
    dollar_quotes = fetch_tradingview_quotes(
        DOLLAR_BRL_SYMBOL,
        scan_url=TRADINGVIEW_FOREX_SCAN_URL,
    )
    if not dollar_quotes:
        raise ValueError("Nao foi possivel carregar USD/BRL.")
    dollar = dollar_quotes[0]
    dollar.symbol = "USD/BRL"
    dollar.name = "Dolar americano"
    dollar.currency = "BRL"
    return dollar


def search_quote(symbol: str) -> MarketQuote:
    cleaned_symbol = normalize_tickers(symbol)
    if not cleaned_symbol:
        raise ValueError("Informe um ticker para buscar.")
    if "," in cleaned_symbol:
        raise ValueError("Busque um ticker por vez.")

    if cleaned_symbol in ("IBOV", "IBOVESPA", "^BVSP"):
        return fetch_ibov_dashboard_quote()
    if cleaned_symbol in ("DOLAR", "DOLLAR", "USD", "USDBRL", "USD/BRL"):
        return fetch_dollar_brl_quote()
    if cleaned_symbol in ("SP500", "S&P500", "S&P 500", "SPX"):
        quotes = fetch_tradingview_quotes("SP:SPX")
        if not quotes:
            raise ValueError("Nao foi possivel carregar S&P 500.")
        return quotes[0]
    if cleaned_symbol in ("EWZ", "AMEX:EWZ"):
        quotes = fetch_tradingview_quotes("AMEX:EWZ")
        if not quotes:
            raise ValueError("Nao foi possivel carregar EWZ.")
        return quotes[0]
    if cleaned_symbol in ("ES", "ES1!", "EMINI", "E-MINI"):
        quote = fetch_yahoo_quote(EMINI_SP500_TICKER, brazilian=False)
        quote.symbol = "E-mini S&P 500"
        quote.name = "E-mini S&P 500 Futures"
        quote.exchange = US_EXCHANGES[EMINI_SP500_TICKER]
        quote.market_state = regular_cme_equity_futures_state()
        quote.logo_url = default_logo_url(EMINI_SP500_TICKER)
        quote.currency = "USD"
        return quote
    if cleaned_symbol in ("NIKKEI", "NIKKEI225", "^N225"):
        quote = fetch_yahoo_quote(NIKKEI_TICKER, brazilian=False)
        quote.symbol = "Nikkei 225"
        quote.exchange = US_EXCHANGES[NIKKEI_TICKER]
        quote.market_state = regular_japan_market_state()
        quote.logo_url = default_logo_url(NIKKEI_TICKER)
        return quote
    if cleaned_symbol in ("SSE", "SHANGHAI", "000001.SS"):
        quote = fetch_yahoo_quote(SHANGHAI_TICKER, brazilian=False)
        quote.symbol = "SSE Composite"
        quote.exchange = US_EXCHANGES[SHANGHAI_TICKER]
        quote.market_state = regular_shanghai_market_state()
        quote.logo_url = default_logo_url(SHANGHAI_TICKER)
        return quote
    if re.fullmatch(r"[A-Z]{4}\d{1,2}", cleaned_symbol):
        quotes = fetch_tradingview_quotes(
            f"BMFBOVESPA:{cleaned_symbol}",
            scan_url=TRADINGVIEW_BRAZIL_SCAN_URL,
        )
        if quotes:
            return quotes[0]
        return fetch_yahoo_quote(cleaned_symbol, brazilian=True)

    quote = fetch_yahoo_quote(cleaned_symbol, brazilian=False)
    quote.logo_url = quote.logo_url or default_logo_url(cleaned_symbol)
    quote.exchange = quote.exchange or US_EXCHANGES.get(cleaned_symbol)
    quote.market_state = quote.market_state or fallback_market_state(cleaned_symbol)
    return quote


def stream_us_market_quotes(
    tickers: str,
    on_quote: Callable[[MarketQuote], None],
    on_progress: Callable[[int, int], None] | None = None,
) -> int:
    cleaned_tickers = normalize_tickers(tickers)
    if not cleaned_tickers:
        raise ValueError("Informe ao menos um ticker.")
    return stream_yahoo_quotes(cleaned_tickers.split(","), on_quote, on_progress, brazilian=False)


def stream_rare_earth_quotes(
    tickers: str = RARE_EARTH_TICKERS,
    on_quote: Callable[[MarketQuote], None] | None = None,
    on_progress: Callable[[int, int], None] | None = None,
) -> int:
    callback = on_quote or (lambda _quote: None)
    cleaned_tickers = normalize_tickers(tickers)
    if not cleaned_tickers:
        raise ValueError("Informe ao menos um ticker.")
    return stream_yahoo_quotes(cleaned_tickers.split(","), callback, on_progress, brazilian=False)


def stream_tradingview_quotes(
    tickers: str,
    on_quote: Callable[[MarketQuote], None],
    on_progress: Callable[[int, int], None] | None = None,
) -> int:
    quotes = fetch_tradingview_quotes(tickers)
    for index, quote in enumerate(quotes, start=1):
        on_quote(quote)
        if on_progress:
            on_progress(index, len(quotes))
    return len(quotes)


def stream_nikkei_quote(
    on_quote: Callable[[MarketQuote], None],
    on_progress: Callable[[int, int], None] | None = None,
) -> int:
    quote = fetch_yahoo_quote(NIKKEI_TICKER, brazilian=False)
    quote.symbol = "Nikkei 225"
    quote.exchange = US_EXCHANGES[NIKKEI_TICKER]
    quote.market_state = regular_japan_market_state()
    quote.logo_url = default_logo_url(NIKKEI_TICKER)
    on_quote(quote)
    if on_progress:
        on_progress(1, 1)
    return 1


def stream_emini_sp500_quote(
    on_quote: Callable[[MarketQuote], None],
    on_progress: Callable[[int, int], None] | None = None,
) -> int:
    quote = fetch_yahoo_quote(EMINI_SP500_TICKER, brazilian=False)
    quote.symbol = "E-mini S&P 500"
    quote.name = "E-mini S&P 500 Futures"
    quote.exchange = US_EXCHANGES[EMINI_SP500_TICKER]
    quote.market_state = regular_cme_equity_futures_state()
    quote.logo_url = default_logo_url(EMINI_SP500_TICKER)
    quote.currency = "USD"
    on_quote(quote)
    if on_progress:
        on_progress(1, 1)
    return 1


def stream_shanghai_quote(
    on_quote: Callable[[MarketQuote], None],
    on_progress: Callable[[int, int], None] | None = None,
) -> int:
    quote = fetch_yahoo_quote(SHANGHAI_TICKER, brazilian=False)
    quote.symbol = "SSE Composite"
    quote.exchange = US_EXCHANGES[SHANGHAI_TICKER]
    quote.market_state = regular_shanghai_market_state()
    quote.logo_url = default_logo_url(SHANGHAI_TICKER)
    on_quote(quote)
    if on_progress:
        on_progress(1, 1)
    return 1


def fetch_yahoo_candles(symbol: str, interval: str = "5m", range_: str = "1d") -> list[Candle]:
    timeout = 5.0 if interval == "1d" else 12.0
    errors = []
    for base_url in (YAHOO_CHART_BASE_URL, YAHOO_CHART_FALLBACK_BASE_URL):
        try:
            return fetch_yahoo_candles_from_url(base_url, symbol, interval, range_, timeout)
        except Exception as exc:
            errors.append(str(exc))
    if interval == "1d":
        try:
            return fetch_yahoo_daily_candles_by_period(symbol, timeout)
        except Exception as exc:
            errors.append(str(exc))
    raise ValueError(f"Nao foi possivel carregar historico diario. Detalhe: {'; '.join(errors[:2])}")


def fetch_yahoo_candles_from_url(
    base_url: str,
    symbol: str,
    interval: str,
    range_: str,
    timeout: float,
) -> list[Candle]:
    with httpx.Client(timeout=timeout, headers={"User-Agent": "Mozilla/5.0"}) as client:
        response = client.get(
            f"{base_url}/{quote(symbol, safe='')}",
            params={"range": range_, "interval": interval},
        )
        response.raise_for_status()
    return candles_from_yahoo_chart_response(response.json(), interval)


def fetch_yahoo_daily_candles_by_period(symbol: str, timeout: float) -> list[Candle]:
    now = datetime.now()
    start = now - timedelta(days=210)
    params = {
        "period1": int(start.timestamp()),
        "period2": int(now.timestamp()),
        "interval": "1d",
    }
    with httpx.Client(timeout=timeout, headers={"User-Agent": "Mozilla/5.0"}) as client:
        response = client.get(
            f"{YAHOO_CHART_FALLBACK_BASE_URL}/{quote(symbol, safe='')}",
            params=params,
        )
        response.raise_for_status()
    return candles_from_yahoo_chart_response(response.json(), "1d")


def candles_from_yahoo_chart_response(data: dict, interval: str) -> list[Candle]:
    chart = data.get("chart") or {}
    if chart.get("error"):
        description = chart["error"].get("description") or "erro retornado pela fonte"
        raise ValueError(description)
    result = ((data.get("chart") or {}).get("result") or [None])[0]
    if not result:
        raise ValueError("Nao foi possivel carregar candles.")

    timestamps = result.get("timestamp") or []
    quote_data = ((result.get("indicators") or {}).get("quote") or [{}])[0]
    opens = quote_data.get("open") or []
    highs = quote_data.get("high") or []
    lows = quote_data.get("low") or []
    closes = quote_data.get("close") or []

    candles = []
    for index, timestamp in enumerate(timestamps):
        values = (
            opens[index] if index < len(opens) else None,
            highs[index] if index < len(highs) else None,
            lows[index] if index < len(lows) else None,
            closes[index] if index < len(closes) else None,
        )
        if any(value is None for value in values):
            continue
        date_format = "%d/%m" if interval.endswith("d") or interval.endswith("wk") or interval.endswith("mo") else "%H:%M"
        candles.append(
            Candle(
                time_label=datetime.fromtimestamp(timestamp).strftime(date_format),
                open=float(values[0]),
                high=float(values[1]),
                low=float(values[2]),
                close=float(values[3]),
            )
        )
    if not candles:
        raise ValueError("Historico diario vazio.")
    return candles


def fetch_yahoo_candles_cached(symbol: str, interval: str = "1d", range_: str = "6mo") -> list[Candle]:
    cache_key = (symbol, interval, range_)
    cached = _DAILY_CANDLE_CACHE.get(cache_key)
    now = datetime.now()
    if cached and now - cached[0] <= DAILY_CANDLE_CACHE_TTL:
        return cached[1]
    candles = fetch_yahoo_candles(symbol, interval=interval, range_=range_)
    _DAILY_CANDLE_CACHE[cache_key] = (now, candles)
    return candles


def daily_quote_for_search(symbol: str) -> tuple[MarketQuote, list[Candle]]:
    symbol = resolve_search_symbol(symbol)
    yahoo_symbol = yahoo_symbol_for_search(symbol)
    candles = fetch_yahoo_candles_cached(yahoo_symbol, interval="1d", range_="6mo")
    if len(candles) < 2:
        raise ValueError("Poucos pontos diarios retornados para analise.")

    display_symbol = display_symbol_for_search(symbol)
    last = candles[-1]
    previous = candles[-2]
    change = last.close - previous.close
    change_percent = (change / previous.close) * 100 if previous.close else None
    return (
        MarketQuote(
            symbol=display_symbol,
            name=display_name_for_search(display_symbol),
            price=last.close,
            change=change,
            change_percent=change_percent,
            volume=None,
            market_time=last.time_label,
            logo_url=default_logo_url(display_symbol),
            exchange=exchange_for_search(display_symbol),
            market_state=fallback_market_state(yahoo_symbol),
            currency=currency_for_search(display_symbol),
        ),
        candles,
    )


def display_symbol_for_search(symbol: str) -> str:
    cleaned_symbol = resolve_search_symbol(symbol)
    if cleaned_symbol in ("IBOV", "IBOVESPA", "^BVSP"):
        return "IBOV"
    if cleaned_symbol in ("DOLAR", "DOLLAR", "USD", "USDBRL", "USD/BRL"):
        return "USD/BRL"
    if cleaned_symbol in ("SP500", "S&P500", "S&P 500", "SPX"):
        return "S&P 500"
    if cleaned_symbol in ("EWZ", "AMEX:EWZ"):
        return "EWZ"
    if cleaned_symbol in ("ES", "ES1!", "EMINI", "E-MINI"):
        return "E-mini S&P 500"
    if cleaned_symbol in ("NIKKEI", "NIKKEI225", "^N225"):
        return "Nikkei 225"
    if cleaned_symbol in ("SSE", "SHANGHAI", "000001.SS"):
        return "SSE Composite"
    return cleaned_symbol


def display_name_for_search(symbol: str) -> str:
    names = {
        "IBOV": "Ibovespa",
        "USD/BRL": "Dolar americano",
        "S&P 500": "S&P 500",
        "EWZ": "iShares MSCI Brazil ETF",
        "E-mini S&P 500": "E-mini S&P 500 Futures",
        "Nikkei 225": "Nikkei 225",
        "SSE Composite": "SSE Composite",
    }
    return names.get(symbol, symbol)


def exchange_for_search(symbol: str) -> str | None:
    if symbol == "IBOV" or re.fullmatch(r"[A-Z]{4}\d{1,2}", symbol):
        return "B3"
    if symbol == "USD/BRL":
        return "Forex"
    if symbol == "S&P 500":
        return "S&P Dow Jones Indices"
    return US_EXCHANGES.get(symbol)


def currency_for_search(symbol: str) -> str | None:
    if symbol == "IBOV":
        return "BRL"
    if symbol == "USD/BRL":
        return "BRL"
    if re.fullmatch(r"[A-Z]{4}\d{1,2}", symbol):
        return "BRL"
    if symbol.endswith(".AX"):
        return "AUD"
    if symbol.endswith(".TO"):
        return "CAD"
    return "USD"


def yahoo_symbol_for_search(symbol: str, quote: MarketQuote | None = None) -> str:
    cleaned_symbol = resolve_search_symbol(symbol)
    if cleaned_symbol in ("IBOV", "IBOVESPA", "^BVSP"):
        return "^BVSP"
    if cleaned_symbol in ("DOLAR", "DOLLAR", "USD", "USDBRL", "USD/BRL"):
        return "USDBRL=X"
    if cleaned_symbol in ("SP500", "S&P500", "S&P 500", "SPX") or (quote and quote.source_symbol == "SP:SPX"):
        return "^GSPC"
    if cleaned_symbol in ("EWZ", "AMEX:EWZ") or (quote and quote.symbol == "EWZ"):
        return "EWZ"
    if cleaned_symbol in ("ES", "ES1!", "EMINI", "E-MINI") or (quote and quote.symbol == "E-mini S&P 500"):
        return EMINI_SP500_TICKER
    if cleaned_symbol in ("NIKKEI", "NIKKEI225", "^N225") or (quote and quote.symbol == "Nikkei 225"):
        return NIKKEI_TICKER
    if cleaned_symbol in ("SSE", "SHANGHAI", "000001.SS") or (quote and quote.symbol == "SSE Composite"):
        return SHANGHAI_TICKER
    if re.fullmatch(r"[A-Z]{4}\d{1,2}", cleaned_symbol):
        return to_yahoo_symbol(cleaned_symbol)
    if quote and quote.source_symbol:
        source_symbol = quote.source_symbol.split(":", 1)[-1]
        if re.fullmatch(r"[A-Z]{4}\d{1,2}", source_symbol):
            return to_yahoo_symbol(source_symbol)
    return cleaned_symbol


def resolve_search_symbol(symbol: str) -> str:
    cleaned_symbol = normalize_tickers(symbol)
    return SEARCH_SYMBOL_ALIASES.get(cleaned_symbol, cleaned_symbol)


def save_line_chart_svg(candles: list[Candle], output_path: Path, title: str) -> Path:
    if len(candles) < 2:
        raise ValueError("Poucos pontos retornados para montar o grafico.")

    width = 920
    height = 420
    pad_left = 64
    pad_right = 28
    pad_top = 28
    pad_bottom = 44
    chart_width = width - pad_left - pad_right
    chart_height = height - pad_top - pad_bottom
    closes = [candle.close for candle in candles]
    min_price = min(closes)
    max_price = max(closes)
    padding = (max_price - min_price) * 0.08 or 1
    min_price -= padding
    max_price += padding

    def x_at(index: int) -> float:
        return pad_left + (index / (len(candles) - 1)) * chart_width

    def y_at(price: float) -> float:
        return pad_top + (max_price - price) / (max_price - min_price) * chart_height

    ma9 = moving_average(closes, 9)
    ma20 = moving_average(closes, 20)
    points = " ".join(f"{x_at(index):.1f},{y_at(close):.1f}" for index, close in enumerate(closes))

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#15191E"/>',
        f'<rect x="{pad_left}" y="{pad_top}" width="{chart_width}" height="{chart_height}" rx="6" fill="#101419" stroke="#2A3038"/>',
        f'<text x="{pad_left}" y="18" fill="#8EE59A" font-size="12" font-family="Arial" font-weight="700">Preco</text>',
        f'<text x="{pad_left + 58}" y="18" fill="#FFD27A" font-size="12" font-family="Arial" font-weight="700">MA 9</text>',
        f'<text x="{pad_left + 108}" y="18" fill="#7AB8FF" font-size="12" font-family="Arial" font-weight="700">MA 20</text>',
    ]
    for step in range(5):
        price = min_price + (max_price - min_price) * step / 4
        y = y_at(price)
        label = f"{price:,.2f}"
        parts.append(f'<line x1="{pad_left}" y1="{y:.1f}" x2="{pad_left + chart_width}" y2="{y:.1f}" stroke="#26303A" stroke-width="1"/>')
        parts.append(f'<text x="10" y="{y + 4:.1f}" fill="#AEB6C2" font-size="11" font-family="Arial">{label}</text>')
    parts.append(f'<polyline points="{points}" fill="none" stroke="#8EE59A" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>')
    parts.append(polyline_for_average(ma9, x_at, y_at, "#FFD27A"))
    parts.append(polyline_for_average(ma20, x_at, y_at, "#7AB8FF"))
    for index in label_indexes(len(candles), 5):
        x = x_at(index)
        parts.append(f'<text x="{x - 16:.1f}" y="{height - 16}" fill="#AEB6C2" font-size="11" font-family="Arial">{candles[index].time_label}</text>')
    parts.append("</svg>")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(parts), encoding="utf-8")
    return output_path


def trend_explanation(candles: list[Candle], quote: MarketQuote) -> str:
    closes = [candle.close for candle in candles]
    if len(closes) < 3:
        return "Ainda ha poucos pontos para interpretar a tendencia com confianca."

    first = closes[0]
    last = closes[-1]
    variation = ((last - first) / first) * 100 if first else 0
    recent = closes[-min(6, len(closes)) :]
    recent_variation = ((recent[-1] - recent[0]) / recent[0]) * 100 if recent[0] else 0
    ma9 = moving_average(closes, 9)[-1]
    ma20 = moving_average(closes, 20)[-1]

    if ma9 is not None and ma20 is not None:
        if last >= ma9 >= ma20 and recent_variation >= 0:
            direction = "alta"
            detail = "o preco esta acima das medias curtas e a parte final do grafico segue positiva"
        elif last <= ma9 <= ma20 and recent_variation <= 0:
            direction = "queda"
            detail = "o preco esta abaixo das medias curtas e a parte final do grafico segue negativa"
        else:
            direction = "lateralizacao"
            detail = "o preco esta oscilando perto das medias, sem confirmacao clara de direcao"
    elif recent_variation > 0:
        direction = "alta"
        detail = "os ultimos pontos estao acima do inicio da janela analisada"
    elif recent_variation < 0:
        direction = "queda"
        detail = "os ultimos pontos estao abaixo do inicio da janela analisada"
    else:
        direction = "lateralizacao"
        detail = "os ultimos pontos estao praticamente estaveis"

    sign = "+" if variation >= 0 else ""
    recent_sign = "+" if recent_variation >= 0 else ""
    return (
        f"Tendencia atual: {direction}. No periodo do grafico, {quote.symbol} variou "
        f"{sign}{variation:.2f}%, com movimento recente de {recent_sign}{recent_variation:.2f}%. "
        f"Leitura: {detail}."
    )


def save_candlestick_svg(candles: list[Candle], output_path: Path, title: str) -> Path:
    if len(candles) < 2:
        raise ValueError("Poucos candles retornados para montar o grafico.")

    width = 920
    height = 520
    pad_left = 64
    pad_right = 28
    pad_top = 52
    pad_bottom = 44
    chart_width = width - pad_left - pad_right
    chart_height = height - pad_top - pad_bottom

    highs = [candle.high for candle in candles]
    lows = [candle.low for candle in candles]
    min_price = min(lows)
    max_price = max(highs)
    padding = (max_price - min_price) * 0.08 or 1
    min_price -= padding
    max_price += padding

    def x_at(index: int) -> float:
        if len(candles) == 1:
            return pad_left + chart_width / 2
        return pad_left + (index / (len(candles) - 1)) * chart_width

    def y_at(price: float) -> float:
        return pad_top + (max_price - price) / (max_price - min_price) * chart_height

    ma9 = moving_average([candle.close for candle in candles], 9)
    ma20 = moving_average([candle.close for candle in candles], 20)
    candle_width = max(3, min(10, chart_width / len(candles) * 0.55))

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#101214"/>',
        f'<text x="{pad_left}" y="30" fill="#F3F5F2" font-size="22" font-family="Arial" font-weight="700">{escape_xml(title)}</text>',
        f'<text x="{pad_left + 250}" y="30" fill="#FFD27A" font-size="13" font-family="Arial">MA 9</text>',
        f'<text x="{pad_left + 310}" y="30" fill="#7AB8FF" font-size="13" font-family="Arial">MA 20</text>',
        f'<rect x="{pad_left}" y="{pad_top}" width="{chart_width}" height="{chart_height}" fill="#15191E" stroke="#2A3038"/>',
    ]

    for step in range(5):
        price = min_price + (max_price - min_price) * step / 4
        y = y_at(price)
        label = f"{price:,.2f}"
        parts.append(f'<line x1="{pad_left}" y1="{y:.1f}" x2="{pad_left + chart_width}" y2="{y:.1f}" stroke="#26303A" stroke-width="1"/>')
        parts.append(f'<text x="10" y="{y + 4:.1f}" fill="#AEB6C2" font-size="11" font-family="Arial">{label}</text>')

    for index, candle in enumerate(candles):
        x = x_at(index)
        color = "#8EE59A" if candle.close >= candle.open else "#FF7A7A"
        y_open = y_at(candle.open)
        y_close = y_at(candle.close)
        body_y = min(y_open, y_close)
        body_h = max(abs(y_close - y_open), 1.5)
        parts.append(f'<line x1="{x:.1f}" y1="{y_at(candle.high):.1f}" x2="{x:.1f}" y2="{y_at(candle.low):.1f}" stroke="{color}" stroke-width="1"/>')
        parts.append(f'<rect x="{x - candle_width / 2:.1f}" y="{body_y:.1f}" width="{candle_width:.1f}" height="{body_h:.1f}" fill="{color}" rx="1"/>')

    parts.append(polyline_for_average(ma9, x_at, y_at, "#FFD27A"))
    parts.append(polyline_for_average(ma20, x_at, y_at, "#7AB8FF"))

    for index in label_indexes(len(candles), 5):
        x = x_at(index)
        parts.append(f'<text x="{x - 16:.1f}" y="{height - 16}" fill="#AEB6C2" font-size="11" font-family="Arial">{candles[index].time_label}</text>')

    parts.append("</svg>")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(parts), encoding="utf-8")
    return output_path


def moving_average(values: list[float], period: int) -> list[float | None]:
    result: list[float | None] = []
    for index in range(len(values)):
        if index + 1 < period:
            result.append(None)
            continue
        window = values[index + 1 - period : index + 1]
        result.append(sum(window) / period)
    return result


def polyline_for_average(values, x_at, y_at, color: str) -> str:
    points = [
        f"{x_at(index):.1f},{y_at(value):.1f}"
        for index, value in enumerate(values)
        if value is not None
    ]
    if len(points) < 2:
        return ""
    return f'<polyline points="{" ".join(points)}" fill="none" stroke="{color}" stroke-width="2"/>'


def label_indexes(size: int, count: int) -> list[int]:
    if size <= count:
        return list(range(size))
    return sorted({round(index * (size - 1) / (count - 1)) for index in range(count)})


def escape_xml(value: str) -> str:
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def fetch_tradingview_quotes(tickers: str, scan_url: str = TRADINGVIEW_SCAN_URL) -> list[MarketQuote]:
    symbols = normalize_tickers(tickers).split(",")
    payload = {
        "symbols": {"tickers": symbols, "query": {"types": []}},
        "columns": [
            "name",
            "description",
            "close",
            "change",
            "change_abs",
            "exchange",
            "type",
            "subtype",
            "currency",
            "update_mode",
        ],
    }
    headers = {
        "User-Agent": "Mozilla/5.0",
        "Content-Type": "application/json",
        "Origin": "https://www.tradingview.com",
        "Referer": "https://www.tradingview.com/",
    }
    with httpx.Client(timeout=6.0, headers=headers) as client:
        response = client.post(scan_url, json=payload)
        response.raise_for_status()

    rows = response.json().get("data") or []
    quotes = [tradingview_quote_from_row(row) for row in rows]
    order = {symbol: index for index, symbol in enumerate(symbols)}
    return sorted(quotes, key=lambda quote: order.get(quote.source_symbol or quote.symbol, 9999))


def fetch_ibovespa_tickers() -> str:
    try:
        tickers = fetch_ibovespa_tickers_from_api()
    except Exception:
        tickers = fetch_ibovespa_tickers_from_page()
    if tickers:
        return ",".join(tickers)
    return IBOVESPA_FALLBACK_TICKERS


def fetch_ibovespa_tickers_from_api() -> list[str]:
    payload = {
        "language": "pt-br",
        "pageNumber": 1,
        "pageSize": 120,
        "index": "IBOV",
        "segment": "1",
    }
    encoded = base64.b64encode(
        json.dumps(payload, separators=(",", ":")).encode("utf-8")
    ).decode("utf-8")
    url = f"{B3_INDEX_BASE_URL}/indexProxy/indexCall/GetPortfolioDay/{quote(encoded, safe='')}"
    with httpx.Client(timeout=12.0, headers={"User-Agent": "Mozilla/5.0"}) as client:
        response = client.get(url)
        response.raise_for_status()
    data = response.json()
    results = data.get("results") or data.get("Results") or []
    return unique_tickers(
        item.get("cod") or item.get("code") or item.get("symbol") or item.get("Código") or ""
        for item in results
    )


def fetch_ibovespa_tickers_from_page() -> list[str]:
    url = f"{B3_INDEX_BASE_URL}/indexPage/preview/IBOV?language=pt-br"
    with httpx.Client(timeout=12.0, headers={"User-Agent": "Mozilla/5.0"}) as client:
        response = client.get(url)
        response.raise_for_status()
    return unique_tickers(re.findall(r"\b[A-Z]{4}\d{1,2}\b", response.text))


def fetch_brapi_quotes(cleaned_tickers: str) -> list[MarketQuote]:
    headers = {}
    token = os.getenv("BRAPI_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"

    url = f"{BRAPI_BASE_URL}/quote/{cleaned_tickers}"
    with httpx.Client(timeout=12.0, headers=headers) as client:
        response = client.get(url)
        if response.status_code in (401, 403):
            raise ValueError(
                "A brapi recusou a consulta. Configure um token em BRAPI_TOKEN para acessar mais ativos."
            )
        response.raise_for_status()

    data = response.json()
    results = data.get("results") or []
    if not results:
        raise ValueError("Nenhuma cotacao retornada pela brapi.")

    return [quote_from_result(item) for item in results]


def fetch_yahoo_quotes(cleaned_tickers: str) -> list[MarketQuote]:
    symbols = cleaned_tickers.split(",")
    quotes = []
    errors = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
        futures = [executor.submit(fetch_yahoo_quote, symbol, True) for symbol in symbols]
        for future in concurrent.futures.as_completed(futures):
            try:
                quotes.append(future.result())
            except Exception as exc:
                errors.append(str(exc))

    if quotes:
        order = {symbol: index for index, symbol in enumerate(symbols)}
        return sorted(quotes, key=lambda quote: order.get(quote.symbol, 9999))
    detail = "; ".join(errors) if errors else "sem resposta da fonte alternativa"
    raise ValueError(f"Nao foi possivel buscar cotacoes. Detalhe: {detail}")


def stream_yahoo_quotes(
    symbols: list[str],
    on_quote: Callable[[MarketQuote], None],
    on_progress: Callable[[int, int], None] | None = None,
    brazilian: bool = True,
) -> int:
    completed = 0
    successes = 0
    errors = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=24) as executor:
        futures = [executor.submit(fetch_yahoo_quote, symbol, brazilian) for symbol in symbols]
        for future in concurrent.futures.as_completed(futures):
            completed += 1
            try:
                quote = future.result()
            except Exception as exc:
                errors.append(str(exc))
            else:
                successes += 1
                on_quote(quote)
            if on_progress:
                on_progress(completed, len(symbols))

    if successes == 0:
        detail = "; ".join(errors) if errors else "sem resposta da fonte alternativa"
        raise ValueError(f"Nao foi possivel buscar cotacoes. Detalhe: {detail}")
    return successes


def fetch_yahoo_quote(symbol: str, brazilian: bool = True) -> MarketQuote:
    yahoo_symbol = to_yahoo_symbol(symbol) if brazilian else symbol
    with httpx.Client(timeout=12.0, headers={"User-Agent": "Mozilla/5.0"}) as client:
        response = client.get(
            f"{YAHOO_CHART_BASE_URL}/{yahoo_symbol}",
            params={"range": "1d", "interval": "1m"},
        )
        response.raise_for_status()
        return yahoo_quote_from_response(symbol, response.json())


def normalize_tickers(tickers: str) -> str:
    symbols = []
    for raw_symbol in tickers.replace(";", ",").split(","):
        symbol = raw_symbol.strip().upper()
        if symbol:
            symbols.append(symbol)
    return ",".join(symbols)


def unique_tickers(symbols) -> list[str]:
    seen = set()
    tickers = []
    for raw_symbol in symbols:
        symbol = str(raw_symbol).strip().upper()
        if not re.fullmatch(r"[A-Z]{4}\d{1,2}", symbol):
            continue
        if symbol not in seen:
            seen.add(symbol)
            tickers.append(symbol)
    return tickers


def quote_from_result(item: dict) -> MarketQuote:
    symbol = item.get("symbol") or item.get("stock") or "-"
    return MarketQuote(
        symbol=symbol,
        name=item.get("shortName") or item.get("longName") or item.get("name") or "",
        price=item.get("regularMarketPrice") or item.get("close"),
        change=item.get("regularMarketChange"),
        change_percent=item.get("regularMarketChangePercent") or item.get("change"),
        volume=item.get("regularMarketVolume") or item.get("volume"),
        market_time=format_market_time(item.get("regularMarketTime")),
        logo_url=item.get("logourl") or default_logo_url(symbol),
        exchange=item.get("exchange") or item.get("market"),
        market_state=item.get("marketState"),
        currency=item.get("currency") or "BRL",
    )


def tradingview_quote_from_row(row: dict) -> MarketQuote:
    values = row.get("d") or []
    source_symbol = row.get("s") or ""
    raw_symbol = values[0] if len(values) > 0 else source_symbol
    description = values[1] if len(values) > 1 else ""
    close = values[2] if len(values) > 2 else None
    change_percent = values[3] if len(values) > 3 else None
    change = values[4] if len(values) > 4 else None
    exchange = values[5] if len(values) > 5 else None
    currency = values[8] if len(values) > 8 else None

    display_symbol = "S&P 500" if source_symbol == "SP:SPX" else raw_symbol
    if source_symbol == "AMEX:EWZ":
        display_symbol = "EWZ"
    if source_symbol == "CME_MINI:ES1!":
        display_symbol = "E-mini S&P 500"
    if source_symbol.startswith("BMFBOVESPA:"):
        display_symbol = source_symbol.split(":", 1)[1]
    if display_symbol == "EMBR3":
        display_symbol = "EMBJ3"
    if source_symbol == DOLLAR_BRL_SYMBOL:
        display_symbol = "USD/BRL"

    return MarketQuote(
        symbol=display_symbol,
        name=description or display_symbol,
        price=close,
        change=change,
        change_percent=change_percent,
        volume=None,
        market_time=datetime.now().strftime("%d/%m/%Y %H:%M"),
        logo_url=default_logo_url(display_symbol) or default_logo_url(source_symbol),
        exchange=exchange_for_tradingview_symbol(source_symbol, exchange),
        market_state=market_state_for_tradingview_symbol(source_symbol),
        source_symbol=source_symbol,
        currency=currency,
    )


def to_yahoo_symbol(symbol: str) -> str:
    if symbol.startswith("^") or "." in symbol or "=" in symbol:
        return symbol
    return f"{symbol}.SA"


def yahoo_quote_from_response(original_symbol: str, data: dict) -> MarketQuote:
    result = ((data.get("chart") or {}).get("result") or [None])[0]
    if not result:
        raise ValueError("resposta vazia")

    meta = result.get("meta") or {}
    indicators = result.get("indicators") or {}
    quote_data = (indicators.get("quote") or [{}])[0]
    timestamps = result.get("timestamp") or []

    price = meta.get("regularMarketPrice")
    previous_close = meta.get("chartPreviousClose") or meta.get("previousClose")
    change = price - previous_close if price is not None and previous_close else None
    change_percent = (change / previous_close) * 100 if change is not None and previous_close else None
    volumes = [value for value in (quote_data.get("volume") or []) if value is not None]
    market_timestamp = timestamps[-1] if timestamps else meta.get("regularMarketTime")

    return MarketQuote(
        symbol=original_symbol,
        name=meta.get("longName") or meta.get("shortName") or meta.get("instrumentType") or "",
        price=price,
        change=change,
        change_percent=change_percent,
        volume=volumes[-1] if volumes else None,
        market_time=format_market_time(market_timestamp),
        logo_url=default_logo_url(original_symbol),
        exchange=US_EXCHANGES.get(original_symbol) or meta.get("fullExchangeName") or meta.get("exchangeName"),
        market_state=meta.get("marketState") or fallback_market_state(original_symbol),
        currency=meta.get("currency"),
    )


def default_logo_url(symbol: str) -> str | None:
    if symbol in US_LOGO_URLS:
        return US_LOGO_URLS[symbol]
    if not re.fullmatch(r"[A-Z]{4}\d{1,2}", symbol):
        return None
    return f"https://icons.brapi.dev/icons/{symbol}.svg"


def fallback_market_state(symbol: str) -> str | None:
    if symbol in US_EXCHANGES:
        if symbol in ("ES=F", "CME_MINI:ES1!"):
            return regular_cme_equity_futures_state()
        return regular_us_market_state()
    if symbol == NIKKEI_TICKER:
        return regular_japan_market_state()
    if symbol == SHANGHAI_TICKER:
        return regular_shanghai_market_state()
    return None


def market_state_for_tradingview_symbol(symbol: str) -> str:
    if symbol.startswith("BMFBOVESPA:"):
        return regular_brazil_market_state()
    if symbol in ("CME_MINI:ES1!", EMINI_SP500_TICKER):
        return regular_cme_equity_futures_state()
    return regular_us_market_state()


def exchange_for_tradingview_symbol(symbol: str, fallback: str | None) -> str | None:
    if symbol.startswith("BMFBOVESPA:"):
        return "B3"
    if symbol == DOLLAR_BRL_SYMBOL:
        return "Forex"
    return US_EXCHANGES.get(symbol) or fallback


def regular_us_market_state() -> str:
    now = datetime.now(ZoneInfo("America/New_York"))
    market_open = time(9, 30)
    market_close = time(16, 0)
    if now.weekday() >= 5:
        return "CLOSED"
    if market_open <= now.time() <= market_close:
        return "REGULAR"
    return "CLOSED"


def regular_cme_equity_futures_state() -> str:
    now = datetime.now(ZoneInfo("America/New_York"))
    daily_pause_start = time(17, 0)
    daily_pause_end = time(18, 0)
    if now.weekday() == 5:
        return "CLOSED"
    if now.weekday() == 6 and now.time() < daily_pause_end:
        return "CLOSED"
    if now.weekday() == 4 and now.time() >= daily_pause_start:
        return "CLOSED"
    if daily_pause_start <= now.time() < daily_pause_end:
        return "CLOSED"
    return "REGULAR"


def regular_brazil_market_state() -> str:
    now = datetime.now(ZoneInfo("America/Sao_Paulo"))
    market_open = time(10, 0)
    market_close = time(17, 0)
    if now.weekday() >= 5:
        return "CLOSED"
    if market_open <= now.time() <= market_close:
        return "REGULAR"
    return "CLOSED"


def regular_japan_market_state() -> str:
    now = datetime.now(ZoneInfo("Asia/Tokyo"))
    morning_open = time(9, 0)
    morning_close = time(11, 30)
    afternoon_open = time(12, 30)
    afternoon_close = time(15, 30)
    if now.weekday() >= 5:
        return "CLOSED"
    if morning_open <= now.time() <= morning_close:
        return "REGULAR"
    if afternoon_open <= now.time() <= afternoon_close:
        return "REGULAR"
    return "CLOSED"


def regular_shanghai_market_state() -> str:
    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    morning_open = time(9, 30)
    morning_close = time(11, 30)
    afternoon_open = time(13, 0)
    afternoon_close = time(15, 0)
    if now.weekday() >= 5:
        return "CLOSED"
    if morning_open <= now.time() <= morning_close:
        return "REGULAR"
    if afternoon_open <= now.time() <= afternoon_close:
        return "REGULAR"
    return "CLOSED"


def format_market_time(value: str | int | float | None) -> str | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value).strftime("%d/%m/%Y %H:%M")
    if isinstance(value, str):
        try:
            normalized = value.replace("Z", "+00:00")
            return datetime.fromisoformat(normalized).strftime("%d/%m/%Y %H:%M")
        except ValueError:
            return value
    return str(value)


def compact_number(value: float | None) -> str:
    if value is None:
        return "-"
    if value >= 1_000_000_000:
        return f"{value / 1_000_000_000:.2f} bi"
    if value >= 1_000_000:
        return f"{value / 1_000_000:.2f} mi"
    if value >= 1_000:
        return f"{value / 1_000:.2f} mil"
    return f"{value:.0f}"


def money(value: float | None) -> str:
    if value is None:
        return "-"
    return f"R$ {value:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")


def price_text(value: float | None, currency: str | None = None) -> str:
    if value is None:
        return "-"
    formatted = f"{value:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
    if currency == "BRL":
        return f"R$ {formatted}"
    if currency == "USD":
        return f"US$ {formatted}"
    if currency == "AUD":
        return f"A$ {formatted}"
    if currency == "CAD":
        return f"C$ {formatted}"
    return formatted
