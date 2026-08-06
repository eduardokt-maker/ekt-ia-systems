from __future__ import annotations

import math
from typing import Any

import numpy as np

try:
    import talib
except ImportError:  # diagnóstico preserva o restante do sistema
    talib = None

from .data_provider import Candle


def _last(values: Any) -> float | None:
    try:
        value = float(values[-1])
        return round(value, 6) if math.isfinite(value) else None
    except (IndexError, TypeError, ValueError):
        return None


class MarketTAEngine:
    """Único ponto de acesso ao TA-Lib; a interface recebe apenas resultados prontos."""

    def calculate(self, candles: list[Candle], period: str) -> dict:
        if talib is None:
            return {"available": False, "message": "TA-Lib não instalado no backend. Execute: pip install TA-Lib>=0.6.5"}
        open_ = np.asarray([c.open for c in candles], dtype=float)
        high = np.asarray([c.high for c in candles], dtype=float)
        low = np.asarray([c.low for c in candles], dtype=float)
        close = np.asarray([c.close for c in candles], dtype=float)
        volume = np.asarray([c.volume for c in candles], dtype=float)
        ema9, ema21, ema80, ema200 = (talib.EMA(close, timeperiod=p) for p in (9, 21, 80, 200))
        macd, macd_signal, macd_hist = talib.MACD(close, fastperiod=12, slowperiod=26, signalperiod=9)
        upper, middle, lower = talib.BBANDS(close, timeperiod=20, nbdevup=2, nbdevdn=2)
        sma20 = talib.SMA(close, timeperiod=20)
        slowk, slowd = talib.STOCH(high, low, close)
        typical = (high + low + close) / 3
        cumulative_volume = np.cumsum(volume)
        vwap = np.divide(np.cumsum(typical * volume), cumulative_volume, out=np.full_like(close, np.nan), where=cumulative_volume != 0)
        range_values = high - low
        indicators = {
            "ema9": _last(ema9), "ema21": _last(ema21), "ema80": _last(ema80), "ema200": _last(ema200),
            "adx": _last(talib.ADX(high, low, close, timeperiod=14)), "rsi": _last(talib.RSI(close, timeperiod=14)),
            "macd": _last(macd), "macd_signal": _last(macd_signal), "macd_hist": _last(macd_hist),
            "sar": _last(talib.SAR(high, low)), "stoch_k": _last(slowk), "stoch_d": _last(slowd),
            "roc": _last(talib.ROC(close, timeperiod=10)), "momentum": _last(talib.MOM(close, timeperiod=10)),
            "williams_r": _last(talib.WILLR(high, low, close, timeperiod=14)), "atr": _last(talib.ATR(high, low, close, timeperiod=14)),
            "bollinger_upper": _last(upper), "bollinger_middle": _last(middle), "bollinger_lower": _last(lower),
            "obv": _last(talib.OBV(close, volume)), "mfi": _last(talib.MFI(high, low, close, volume, timeperiod=14)),
            "vwap": _last(vwap), "current_range": _last(range_values), "average_range20": _last(talib.SMA(range_values, timeperiod=20)),
            "volume_average20": _last(talib.SMA(volume, timeperiod=20)),
        }
        patterns = []
        for name, label in (("CDLDOJI", "Doji"), ("CDLHAMMER", "Martelo"), ("CDLENGULFING", "Engolfo"), ("CDLSHOOTINGSTAR", "Estrela cadente")):
            value = int(getattr(talib, name)(open_, high, low, close)[-1])
            if value:
                patterns.append({"name": label, "direction": "alta" if value > 0 else "baixa", "intensity": value, "time": candles[-1].datetime, "period": period})
        chart = []
        start = max(0, len(candles) - 80)
        for index in range(start, len(candles)):
            def finite_at(series):
                value = float(series[index])
                return round(value, 6) if math.isfinite(value) else None

            chart.append({
                "timestamp": candles[index].timestamp,
                "datetime": candles[index].datetime,
                "open": candles[index].open,
                "high": candles[index].high,
                "low": candles[index].low,
                "close": candles[index].close,
                "ema9": finite_at(ema9),
                "sma20": finite_at(sma20),
                "bollinger_upper": finite_at(upper),
                "bollinger_lower": finite_at(lower),
            })
        return {"available": True, "engine": f"TA-Lib {getattr(talib, '__version__', '')}", "quality": "completo" if len(candles) >= 200 else "parcial — EMA 200 requer mais histórico", "values": indicators, "patterns": patterns, "chart": chart}
