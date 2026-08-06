import unittest
from datetime import datetime

from monitor_global import GlobalBiasModel, MarketDataService, MarketQuote, SAO_PAULO


def quote(ticker: str, change: float) -> MarketQuote:
    now = datetime.now(SAO_PAULO).isoformat()
    return MarketQuote(
        ticker=ticker, provider_symbol=ticker, name=ticker, market="US",
        price=100.0, change_points=change, change_percent=change,
        previous_close=100.0, day_high=101.0, day_low=99.0, volume=1000,
        source_timestamp=now, read_timestamp=now, source="Fake",
        data_status="updated", message="Atualizado", age_seconds=1.0,
    )


class FakeProvider:
    def __init__(self, quotes=None, errors=None):
        self.quotes = quotes or []
        self.errors = errors or []
        self.calls = 0

    def fetch(self):
        self.calls += 1
        return self.quotes, self.errors


class MonitorGlobalTest(unittest.TestCase):
    def test_only_three_requested_assets_are_returned(self):
        provider = FakeProvider([quote("EWZ", 1), quote("ES", .5), quote("VIX", -4)])
        result = MarketDataService(provider, cache_seconds=20).snapshot()
        self.assertEqual(result["tickers"], ["EWZ", "ES", "VIX"])
        self.assertEqual(len(result["quotes"]), 3)

    def test_favourable_model_combines_ewz_es_and_inverse_vix(self):
        result = GlobalBiasModel().evaluate([quote("EWZ", 1.5), quote("ES", 1), quote("VIX", -5)])
        self.assertEqual(result["bias"], "favorável")
        self.assertEqual(result["score"], 100.0)

    def test_rising_vix_is_defensive(self):
        result = GlobalBiasModel().evaluate([quote("EWZ", -1.5), quote("ES", -1), quote("VIX", 5)])
        self.assertEqual(result["bias"], "defensivo")

    def test_partial_failure_keeps_available_quotes(self):
        result = MarketDataService(FakeProvider([quote("EWZ", .2)], ["ES: timeout"]), 0).snapshot()
        self.assertTrue(result["ok"])
        self.assertEqual(result["diagnostics"]["active_assets"], 1)

    def test_cache_avoids_repeated_external_calls(self):
        provider = FakeProvider([quote("EWZ", .2)])
        service = MarketDataService(provider, cache_seconds=60)
        service.snapshot()
        service.snapshot()
        self.assertEqual(provider.calls, 1)


if __name__ == "__main__":
    unittest.main()
