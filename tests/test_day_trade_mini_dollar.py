from decimal import Decimal
import unittest

import day_trade_store
import web_app


def _result(direction: str, entry: str, exit_price: str, quantity: int):
    return day_trade_store.calculated_trade_result(
        direction=direction,
        entry_price_text=entry,
        exit_price_text=exit_price,
        quantity=quantity,
        point_value=day_trade_store.WDO_POINT_VALUE,
    )


class DayTradeMiniDollarRulesTest(unittest.TestCase):
    def test_wdo_required_calculation_scenarios(self):
        cases = (
            ("Compra", "5430", "5440", 1, "10", "100", "GAIN"),
            ("Compra", "5430", "5420", 2, "-10", "-200", "LOSS"),
            ("Venda", "5430", "5420", 3, "10", "300", "GAIN"),
            ("Venda", "5430", "5440", 2, "-10", "-200", "LOSS"),
            ("Compra", "5430", "5430", 5, "0", "0", "BREAK-EVEN"),
            ("Compra", "5430", "5430.5", 1, "0.5", "5.0", "GAIN"),
        )
        for case in cases:
            direction, entry, exit_price, quantity, points, gross, classification = case
            with self.subTest(case=case):
                self.assertEqual(
                    _result(direction, entry, exit_price, quantity),
                    {
                        "points": Decimal(points),
                        "gross": Decimal(gross),
                        "classification": classification,
                    },
                )

    def test_wdo_payload_uses_contract_specification(self):
        payload = web_app.validated_day_trade_payload(
            {
                "trade_date": "2026-08-13", "entry_time": "10:30",
                "asset": "WDOU26", "market": "Mini dólar",
                "direction": "Compra", "quantity": 2,
                "entry_price_text": "5430", "stop_price_text": "5420",
                "target_price_text": "5440", "point_value_text": "999",
                "strategy": "Rompimento", "operation_result": "Gain",
            }
        )
        self.assertEqual(Decimal(payload["point_value_text"]), Decimal("10"))

    def test_win_existing_point_value_is_unchanged(self):
        payload = web_app.validated_day_trade_payload(
            {
                "trade_date": "2026-08-13", "entry_time": "10:30",
                "asset": "WINQ26", "market": "Mini índice",
                "direction": "Compra", "quantity": 2,
                "entry_price_text": "135000", "stop_price_text": "134900",
                "target_price_text": "135200", "point_value_text": "999",
                "strategy": "Rompimento", "operation_result": "Gain",
            }
        )
        self.assertEqual(Decimal(payload["point_value_text"]), Decimal("0.20"))
