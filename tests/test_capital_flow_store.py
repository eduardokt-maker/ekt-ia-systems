from decimal import Decimal
import unittest

import capital_flow_store


class CapitalFlowStoreTest(unittest.TestCase):
    def test_validate_payload_calculates_values_without_accepting_negative_amounts(self):
        item = capital_flow_store.validate_payload(
            {
                "reference_date": "2026-07-27",
                "investor_type": "Estrangeiro",
                "inflow": "2.450.000,50",
                "outflow": "1.800.000,25",
                "source": "B3 - arquivo informado",
                "source_lag": "D+2",
            }
        )
        self.assertEqual(item["inflow"], Decimal("2450000.50"))
        self.assertEqual(item["outflow"], Decimal("1800000.25"))

        with self.assertRaisesRegex(ValueError, "não podem ser negativas"):
            capital_flow_store.validate_payload(
                {
                    "reference_date": "2026-07-27",
                    "investor_type": "Estrangeiro",
                    "inflow": "-1",
                    "outflow": "0",
                    "source": "B3",
                }
            )

    def test_validate_payload_rejects_weekends_and_unknown_investors(self):
        with self.assertRaisesRegex(ValueError, "não são pregões"):
            capital_flow_store.validate_payload(
                {
                    "reference_date": "2026-08-01",
                    "investor_type": "Estrangeiro",
                    "inflow": "1",
                    "outflow": "0",
                    "source": "B3",
                }
            )

        with self.assertRaisesRegex(ValueError, "tipo de investidor"):
            capital_flow_store.validate_payload(
                {
                    "reference_date": "2026-07-27",
                    "investor_type": "Outro",
                    "inflow": "1",
                    "outflow": "0",
                    "source": "B3",
                }
            )


if __name__ == "__main__":
    unittest.main()
