import unittest
from datetime import datetime, timedelta, timezone

from motor_analise.data_provider import Candle
from motor_analise.signal_service import TechnicalSignalService
from motor_analise.ta_engine import MarketTAEngine, talib


def candles(count: int = 240, direction: float = 1.0) -> list[Candle]:
    start = datetime(2026, 1, 2, 14, tzinfo=timezone.utc)
    result = []
    for index in range(count):
        close = 100 + index * direction * 0.25 + (index % 5) * 0.03
        result.append(Candle(
            timestamp=int((start + timedelta(minutes=index * 5)).timestamp()),
            datetime=(start + timedelta(minutes=index * 5)).isoformat(),
            open=close - direction * 0.1,
            high=close + 0.4,
            low=close - 0.4,
            close=close,
            volume=1000 + index * 5,
        ))
    return result


class AnalysisEngineTests(unittest.TestCase):
    def test_talib_engine_returns_structured_indicators(self):
        if talib is None:
            self.skipTest("TA-Lib não instalado")
        result = MarketTAEngine().calculate(candles(), "5m")
        self.assertTrue(result["available"])
        self.assertIsNotNone(result["values"]["ema200"])
        self.assertIsNotNone(result["values"]["rsi"])
        self.assertEqual(result["quality"], "completo")

    def test_signal_score_is_bounded_and_not_a_probability(self):
        values = {"ema9": 120, "ema21": 115, "ema80": 110, "macd_hist": 2,
                  "rsi": 60, "vwap": 112, "volume": 200, "volume_average20": 100, "adx": 30}
        result = TechnicalSignalService().evaluate(125, values)
        self.assertGreaterEqual(result["score"], -100)
        self.assertLessEqual(result["score"], 100)
        self.assertNotIn("%", result["label"])
        self.assertEqual(result["trend"], "Tendência de alta")

    def test_combined_context_uses_only_valid_asset_scores(self):
        result = TechnicalSignalService().combined([
            {"signal": {"score": 40}}, {"signal": {"score": -10}}, {"signal": {}},
        ])
        self.assertEqual(result["score"], 15)
        self.assertEqual(result["label"], "Contexto neutro")


if __name__ == "__main__":
    unittest.main()
