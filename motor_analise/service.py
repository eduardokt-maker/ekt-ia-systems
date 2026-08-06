from __future__ import annotations

import threading
import time
from datetime import datetime
from zoneinfo import ZoneInfo

from .data_provider import ASSETS, YahooDelayedCandleProvider
from .signal_service import TechnicalSignalService
from .ta_engine import MarketTAEngine


class AnalysisService:
    periods = ("5m", "15m", "1h", "1d")

    def __init__(self, provider=None, cache_seconds: int = 30):
        self.provider = provider or YahooDelayedCandleProvider()
        self.engine = MarketTAEngine()
        self.signals = TechnicalSignalService()
        self.cache_seconds = cache_seconds
        self._cache: dict[str, tuple[float, dict]] = {}
        self._lock = threading.Lock()

    def snapshot(self, period: str = "5m") -> dict:
        period = period if period in self.periods else "5m"
        with self._lock:
            cached = self._cache.get(period)
            if cached and time.monotonic() - cached[0] < self.cache_seconds:
                return cached[1]
        assets = [self._analyze(ticker, period) for ticker in ASSETS]
        payload = {
            "ok": any(item.get("ok") for item in assets), "module": "Motor de Análise", "period": period,
            "updated_at": datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(), "assets": assets,
            "combined": self.signals.combined(assets),
            "disclaimer": "Indicadores técnicos são ferramentas de apoio e não garantem resultados. A decisão operacional permanece sob responsabilidade do usuário.",
        }
        with self._lock: self._cache[period] = (time.monotonic(), payload)
        return payload

    def _analyze(self, ticker: str, period: str) -> dict:
        try:
            candles, meta = self.provider.fetch(ticker, period)
            technical = self.engine.calculate(candles, period)
            latest, previous = candles[-1], candles[-2]
            values = dict(technical.get("values") or {})
            values["volume"] = latest.volume
            signal = self.signals.evaluate(latest.close, values) if technical.get("available") else {}
            return {"ok": technical.get("available", False), **meta, "period": period, "price": latest.close,
                    "change_points": round(latest.close - previous.close, 4), "change_percent": round((latest.close / previous.close - 1) * 100, 4),
                    "last_update": latest.datetime, "candle_count": len(candles), "technical": technical, "signal": signal,
                    "candles": [c.__dict__ for c in candles[-80:]]}
        except Exception as exc:
            return {"ok": False, "ticker": ticker, "period": period, "error": str(exc), "source": "Fonte temporariamente indisponível"}


analysis_service = AnalysisService()
