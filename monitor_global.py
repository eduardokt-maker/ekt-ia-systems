from __future__ import annotations

import math
import threading
import time
from dataclasses import asdict, dataclass
from datetime import datetime
from typing import Any, Protocol
from zoneinfo import ZoneInfo

import httpx


SAO_PAULO = ZoneInfo("America/Sao_Paulo")
ASSETS = (
    ("EWZ", "EWZ", "iShares MSCI Brazil ETF", "NYSE Arca"),
    ("ES", "ES=F", "E-mini S&P 500 futuro", "CME"),
    ("VIX", "^VIX", "Cboe Volatility Index", "Cboe"),
)


def _finite(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def _clamp(value: float, minimum: float = -1.0, maximum: float = 1.0) -> float:
    return max(minimum, min(maximum, value))


@dataclass(frozen=True)
class MarketQuote:
    ticker: str
    provider_symbol: str
    name: str
    market: str
    price: float | None
    change_points: float | None
    change_percent: float | None
    previous_close: float | None
    day_high: float | None
    day_low: float | None
    volume: float | None
    source_timestamp: str | None
    read_timestamp: str
    source: str
    data_status: str
    message: str
    age_seconds: float | None


class GlobalMarketProvider(Protocol):
    def fetch(self) -> tuple[list[MarketQuote], list[str]]: ...


class YahooFinanceProvider:
    """External delayed-data adapter. No Profit, Excel, COM or local file access."""

    base_urls = (
        "https://query2.finance.yahoo.com/v8/finance/chart",
        "https://query1.finance.yahoo.com/v8/finance/chart",
    )

    def __init__(self, timeout_seconds: float = 12.0):
        self.timeout_seconds = timeout_seconds

    def fetch(self) -> tuple[list[MarketQuote], list[str]]:
        read_at = datetime.now(SAO_PAULO)
        quotes: list[MarketQuote] = []
        errors: list[str] = []
        headers = {"User-Agent": "Mozilla/5.0 EKT-Monitor-Global/1.0", "Accept": "application/json"}
        with httpx.Client(timeout=self.timeout_seconds, headers=headers, follow_redirects=True) as client:
            for ticker, provider_symbol, name, market in ASSETS:
                try:
                    response = None
                    attempts: list[str] = []
                    for base_url in self.base_urls:
                        candidate = client.get(
                            f"{base_url}/{provider_symbol}",
                            params={"interval": "5m", "range": "1d"},
                        )
                        if candidate.is_success:
                            response = candidate
                            break
                        attempts.append(str(candidate.status_code))
                    if response is None:
                        raise RuntimeError(f"HTTP {'/'.join(attempts)}")
                    result = response.json().get("chart", {}).get("result") or []
                    if not result:
                        raise ValueError("resposta sem cotação")
                    meta = result[0].get("meta") or {}
                    price = _finite(meta.get("regularMarketPrice"))
                    previous = _finite(meta.get("chartPreviousClose") or meta.get("previousClose"))
                    change_points = price - previous if price is not None and previous not in (None, 0) else None
                    change_percent = change_points / previous * 100 if change_points is not None and previous else None
                    epoch = meta.get("regularMarketTime")
                    source_time = datetime.fromtimestamp(float(epoch), SAO_PAULO) if epoch else None
                    age = max(0.0, (read_at - source_time).total_seconds()) if source_time else None
                    status = "updated" if age is not None and age <= 20 * 60 else "delayed"
                    message = "Atualizado pela fonte externa" if status == "updated" else "Dado possivelmente atrasado"
                    quotes.append(MarketQuote(
                        ticker=ticker,
                        provider_symbol=provider_symbol,
                        name=name,
                        market=market,
                        price=price,
                        change_points=round(change_points, 4) if change_points is not None else None,
                        change_percent=round(change_percent, 4) if change_percent is not None else None,
                        previous_close=previous,
                        day_high=_finite(meta.get("regularMarketDayHigh")),
                        day_low=_finite(meta.get("regularMarketDayLow")),
                        volume=_finite(meta.get("regularMarketVolume")),
                        source_timestamp=source_time.isoformat() if source_time else None,
                        read_timestamp=read_at.isoformat(),
                        source="Yahoo Finance",
                        data_status=status,
                        message=message,
                        age_seconds=round(age, 1) if age is not None else None,
                    ))
                except Exception as exc:
                    errors.append(f"{ticker}: {type(exc).__name__}")
        return quotes, errors


class TradingViewProvider:
    """Fallback adapter used when the primary provider blocks the server."""

    scanner_url = "https://scanner.tradingview.com/global/scan"
    provider_symbols = {
        "EWZ": "AMEX:EWZ",
        "ES": "CME_MINI:ES1!",
        "VIX": "CBOE:VIX",
    }
    columns = ("close", "change", "open", "high", "low", "volume", "update_mode")

    def __init__(self, timeout_seconds: float = 12.0):
        self.timeout_seconds = timeout_seconds

    def fetch(self) -> tuple[list[MarketQuote], list[str]]:
        read_at = datetime.now(SAO_PAULO)
        payload = {
            "symbols": {
                "tickers": list(self.provider_symbols.values()),
                "query": {"types": []},
            },
            "columns": list(self.columns),
        }
        try:
            response = httpx.post(
                self.scanner_url,
                json=payload,
                timeout=self.timeout_seconds,
                headers={"User-Agent": "Mozilla/5.0 EKT-Monitor-Global/1.0"},
                follow_redirects=True,
            )
            response.raise_for_status()
            rows = response.json().get("data") or []
        except Exception as exc:
            return [], [f"TradingView: {type(exc).__name__}"]

        asset_by_provider = {
            self.provider_symbols[ticker]: (ticker, provider_symbol, name, market)
            for ticker, provider_symbol, name, market in ASSETS
        }
        quotes: list[MarketQuote] = []
        errors: list[str] = []
        for row in rows:
            symbol = str(row.get("s") or "")
            asset = asset_by_provider.get(symbol)
            values = row.get("d") or []
            if asset is None or len(values) < len(self.columns):
                continue
            ticker, provider_symbol, name, market = asset
            price = _finite(values[0])
            change_percent = _finite(values[1])
            previous = (
                price / (1 + change_percent / 100)
                if price is not None and change_percent is not None and change_percent != -100
                else None
            )
            change_points = price - previous if price is not None and previous is not None else None
            update_mode = str(values[6] or "")
            delayed = "delayed" in update_mode
            quotes.append(MarketQuote(
                ticker=ticker,
                provider_symbol=provider_symbol,
                name=name,
                market=market,
                price=price,
                change_points=round(change_points, 4) if change_points is not None else None,
                change_percent=round(change_percent, 4) if change_percent is not None else None,
                previous_close=round(previous, 4) if previous is not None else None,
                day_high=_finite(values[3]),
                day_low=_finite(values[4]),
                volume=_finite(values[5]),
                source_timestamp=None,
                read_timestamp=read_at.isoformat(),
                source="TradingView",
                data_status="delayed" if delayed else "updated",
                message="Dado com atraso da fonte alternativa" if delayed else "Atualizado pela fonte alternativa",
                age_seconds=None,
            ))
        received = {quote.ticker for quote in quotes}
        errors.extend(
            f"{ticker}: ausente na fonte alternativa"
            for ticker, *_ in ASSETS
            if ticker not in received
        )
        return quotes, errors


class ResilientMarketProvider:
    def __init__(
        self,
        primary: GlobalMarketProvider | None = None,
        fallback: GlobalMarketProvider | None = None,
    ):
        self.primary = primary or YahooFinanceProvider()
        self.fallback = fallback or TradingViewProvider()

    def fetch(self) -> tuple[list[MarketQuote], list[str]]:
        primary_quotes, primary_errors = self.primary.fetch()
        received = {quote.ticker for quote in primary_quotes}
        if len(received) == len(ASSETS):
            return primary_quotes, primary_errors
        fallback_quotes, fallback_errors = self.fallback.fetch()
        combined = list(primary_quotes)
        combined.extend(quote for quote in fallback_quotes if quote.ticker not in received)
        return combined, primary_errors + fallback_errors


class GlobalBiasModel:
    weights = {"EWZ": 0.45, "ES": 0.35, "VIX": 0.20}

    def evaluate(self, quotes: list[MarketQuote]) -> dict:
        by_ticker = {quote.ticker: quote for quote in quotes}
        components = []
        weighted_score = 0.0
        available_weight = 0.0
        for ticker, weight in self.weights.items():
            quote = by_ticker.get(ticker)
            change = quote.change_percent if quote else None
            if change is None:
                components.append({"ticker": ticker, "available": False, "effect": "indisponível", "score": None})
                continue
            raw = _clamp((-change / 5.0) if ticker == "VIX" else (change / (1.5 if ticker == "EWZ" else 1.0)))
            weighted_score += raw * weight
            available_weight += weight
            effect = "favorável" if raw >= 0.15 else "desfavorável" if raw <= -0.15 else "neutro"
            components.append({
                "ticker": ticker,
                "available": True,
                "change_percent": round(change, 2),
                "effect": effect,
                "score": round(raw * 100, 1),
                "weight_percent": round(weight * 100),
            })
        normalized = weighted_score / available_weight * 100 if available_weight else 0.0
        bias = "favorável" if normalized >= 20 else "defensivo" if normalized <= -20 else "neutro"
        return {
            "bias": bias,
            "score": round(normalized, 1),
            "confidence_percent": round(available_weight * 100),
            "components": components,
            "summary": {
                "favorável": "Ambiente externo favorável ao apetite por risco.",
                "defensivo": "Ambiente externo defensivo; risco e volatilidade pedem cautela.",
                "neutro": "Sinais externos mistos ou sem direção suficiente.",
            }[bias],
            "methodology": "EWZ 45% + ES 35% + VIX invertido 20%.",
        }


class MarketDataService:
    def __init__(self, provider: GlobalMarketProvider | None = None, cache_seconds: int = 20):
        self.provider = provider or ResilientMarketProvider()
        self.cache_seconds = cache_seconds
        self.model = GlobalBiasModel()
        self._lock = threading.Lock()
        self._cached_at = 0.0
        self._cached: dict | None = None

    def snapshot(self) -> dict:
        with self._lock:
            if self._cached and time.monotonic() - self._cached_at < self.cache_seconds:
                return self._cached
            started = time.perf_counter()
            quotes, errors = self.provider.fetch()
            payload = {
                "ok": bool(quotes),
                "quotes": [asdict(quote) for quote in quotes],
                "model": self.model.evaluate(quotes),
                "diagnostics": {
                    "provider": " + ".join(dict.fromkeys(quote.source for quote in quotes))
                    or "Yahoo Finance + TradingView",
                    "provider_online": bool(quotes),
                    "requested_assets": len(ASSETS),
                    "active_assets": len(quotes),
                    "delayed_assets": sum(quote.data_status == "delayed" for quote in quotes),
                    "errors": errors,
                    "read_at": datetime.now(SAO_PAULO).isoformat(),
                    "latency_ms": round((time.perf_counter() - started) * 1000, 1),
                    "message": (
                        f"Fonte externa ativa — {len(quotes)}/{len(ASSETS)} indicadores recebidos."
                        if quotes else "Fonte externa temporariamente indisponível."
                    ),
                    "delay_notice": "Cotações externas podem ter atraso e não substituem dados da corretora.",
                },
                "tickers": [ticker for ticker, *_ in ASSETS],
            }
            self._cached = payload
            self._cached_at = time.monotonic()
            return payload


market_data_service = MarketDataService()
