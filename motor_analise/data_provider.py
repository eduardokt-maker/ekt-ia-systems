from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Protocol
from zoneinfo import ZoneInfo

import httpx

SAO_PAULO = ZoneInfo("America/Sao_Paulo")
ASSETS = {
    "ES": ("ES=F", "E-mini S&P 500 futuro", "CME"),
    "EWZ": ("EWZ", "iShares MSCI Brazil ETF", "NYSE Arca"),
}


@dataclass(frozen=True)
class Candle:
    timestamp: int
    datetime: str
    open: float
    high: float
    low: float
    close: float
    volume: float


class CandleProvider(Protocol):
    def fetch(self, ticker: str, interval: str) -> tuple[list[Candle], dict]: ...


class YahooDelayedCandleProvider:
    """Adapter substituível para protótipo; nunca é tratado como tempo real oficial."""

    base_url = "https://query1.finance.yahoo.com/v8/finance/chart"
    interval_map = {"5m": ("5m", "5d"), "15m": ("15m", "5d"), "1h": ("60m", "1mo"), "1d": ("1d", "1y")}

    def fetch(self, ticker: str, interval: str) -> tuple[list[Candle], dict]:
        if ticker not in ASSETS:
            raise ValueError("Ativo não permitido. Use ES ou EWZ.")
        provider_symbol, name, market = ASSETS[ticker]
        provider_interval, range_value = self.interval_map.get(interval, self.interval_map["5m"])
        response = httpx.get(
            f"{self.base_url}/{provider_symbol}",
            params={"interval": provider_interval, "range": range_value, "includePrePost": "false"},
            headers={"User-Agent": "Mozilla/5.0 EKT-Motor-Analise/1.0"},
            timeout=15,
            follow_redirects=True,
        )
        response.raise_for_status()
        result = (response.json().get("chart", {}).get("result") or [None])[0]
        if not result:
            raise ValueError("A fonte não retornou candles.")
        timestamps = result.get("timestamp") or []
        quote = ((result.get("indicators") or {}).get("quote") or [{}])[0]
        candles: list[Candle] = []
        for index, stamp in enumerate(timestamps):
            try:
                values = [float(quote[key][index]) for key in ("open", "high", "low", "close")]
                volume = float((quote.get("volume") or [0] * len(timestamps))[index] or 0)
            except (TypeError, ValueError, IndexError):
                continue
            open_, high, low, close = values
            if min(values) <= 0 or low > high or not (low <= open_ <= high and low <= close <= high) or volume < 0:
                continue
            moment = datetime.fromtimestamp(int(stamp), SAO_PAULO)
            candles.append(Candle(int(stamp), moment.isoformat(), open_, high, low, close, volume))
        unique = {c.timestamp: c for c in candles}
        validated = [unique[key] for key in sorted(unique)]
        if len(validated) < 35:
            raise ValueError(f"Candles válidos insuficientes: {len(validated)}.")
        meta = result.get("meta") or {}
        return validated, {
            "ticker": ticker,
            "provider_symbol": provider_symbol,
            "name": name,
            "market": market,
            "currency": meta.get("currency") or "USD",
            "source": "Yahoo Finance — dados indicativos/possivelmente atrasados",
            "exchange_timezone": meta.get("exchangeTimezoneName"),
        }
