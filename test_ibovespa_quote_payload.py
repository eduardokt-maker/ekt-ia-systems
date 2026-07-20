import unittest

import market_data
import web_app


class IbovespaQuotePayloadTest(unittest.TestCase):
    def test_yahoo_intraday_fields_are_reused_in_card_payload(self):
        response = {
            "chart": {
                "result": [{
                    "meta": {
                        "regularMarketPrice": 25.5,
                        "previousClose": 24.0,
                        "regularMarketTime": 1784554215,
                        "marketState": "REGULAR",
                        "currency": "BRL",
                    },
                    "timestamp": [1784554000, 1784554215],
                    "indicators": {"quote": [{
                        "open": [24.0, 25.0],
                        "high": [25.0, 26.0],
                        "low": [23.5, 24.8],
                        "close": [24.8, 25.5],
                        "volume": [1000, 2000],
                    }]},
                }]
            }
        }
        quote = market_data.yahoo_quote_from_response("TEST3", response)
        payload = web_app.market_quote_payload(quote)

        self.assertEqual(payload["day_open"], 24.0)
        self.assertEqual(payload["day_high"], 26.0)
        self.assertEqual(payload["day_low"], 23.5)
        self.assertEqual(payload["volume"], 3000)
        self.assertEqual(payload["financial_volume"], 76500)
        self.assertEqual(payload["intraday_prices"], [24.8, 25.5])


if __name__ == "__main__":
    unittest.main()
