import unittest
from datetime import datetime, timedelta

from monitor_global import MarketDataService, SAO_PAULO


class FakeBridge:
    def __init__(self, rows=None, profit=True, excel=True):
        self.rows = rows or []
        self.profit = profit
        self.excel = excel

    def read_rows(self):
        return self.rows, {
            "profit_running": self.profit,
            "excel_running": self.excel,
            "workbook_found": True,
            "workbook_path": "profit_market_data.xlsx",
            "errors": [],
            "read_at": datetime.now(SAO_PAULO).isoformat(),
            "latency_ms": 1,
        }


def row(ticker="WIN", source_time=None, price=142350):
    return [ticker, ticker, "B3", price, 620, 0.44, 141900, 142500, 141800,
            141730, 1000, None, source_time or datetime.now(SAO_PAULO), "OK", "Profit RTD"]


class MonitorGlobalTest(unittest.TestCase):
    def test_updated_quote(self):
        result = MarketDataService(FakeBridge([row()])).snapshot()
        self.assertEqual(result["quotes"][0]["data_status"], "updated")
        self.assertEqual(result["quotes"][0]["previous_close"], 141730.0)

    def test_profit_closed_does_not_crash(self):
        result = MarketDataService(FakeBridge([], profit=False)).snapshot()
        self.assertEqual(result["quotes"], [])
        self.assertIn("Fonte Profit indisponível", result["diagnostics"]["message"])

    def test_excel_closed_does_not_crash(self):
        result = MarketDataService(FakeBridge([], excel=False)).snapshot()
        self.assertEqual(result["diagnostics"]["active_assets"], 0)

    def test_stale_quote_is_labelled(self):
        old = datetime.now(SAO_PAULO) - timedelta(minutes=2)
        quote = MarketDataService(FakeBridge([row(source_time=old)])).snapshot()["quotes"][0]
        self.assertEqual(quote["data_status"], "stale")
        self.assertIn("Dado desatualizado", quote["message"])

    def test_rtd_error_is_unavailable_not_fabricated(self):
        quote = MarketDataService(FakeBridge([row(price="#N/A")])).snapshot()["quotes"][0]
        self.assertIsNone(quote["price"])


if __name__ == "__main__":
    unittest.main()
