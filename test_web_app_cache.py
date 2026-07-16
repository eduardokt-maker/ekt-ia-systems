import unittest
from unittest.mock import patch

import web_app


class IbovespaMarketCacheTest(unittest.TestCase):
    def setUp(self):
        with web_app._IBOV_MARKET_CACHE_LOCK:
            web_app._IBOV_MARKET_CACHE = None

    def test_reuses_cached_payload_without_new_market_request(self):
        expected = {"ok": True, "source": "test", "index": None, "quotes": []}
        with patch.object(web_app, "_fetch_ibovespa_market_payload", return_value=expected) as fetch:
            first = web_app.ibovespa_market_payload()
            second = web_app.ibovespa_market_payload()

        self.assertEqual(first["source"], "test")
        self.assertEqual(second["source"], "test")
        self.assertEqual(fetch.call_count, 1)
        self.assertIn("cache_age_seconds", second)


if __name__ == "__main__":
    unittest.main()
