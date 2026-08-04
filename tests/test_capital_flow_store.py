from decimal import Decimal
import unittest
from unittest.mock import patch

import capital_flow_store


class CapitalFlowStoreTest(unittest.TestCase):
    def test_official_b3_records_are_read_only(self):
        official = f"{capital_flow_store.OFFICIAL_SOURCE_PREFIX} (BDI)"
        with patch.object(capital_flow_store, "_record_source", return_value=official):
            with self.assertRaisesRegex(ValueError, "somente leitura"):
                capital_flow_store.save_record({}, item_id=7)
            with self.assertRaisesRegex(ValueError, "somente leitura"):
                capital_flow_store.delete_record(7)

    def test_api_row_preserves_exact_monetary_values(self):
        item = capital_flow_store._row_dict(
            (
                1,
                "2026-07-27",
                "Estrangeiro",
                Decimal("2450000.50"),
                Decimal("1800000.25"),
                "Fonte manual",
                "",
                "D-2",
                "2026-07-27T12:00:00",
            )
        )
        self.assertEqual(item["inflow_exact"], "2450000.50")
        self.assertEqual(item["outflow_exact"], "1800000.25")
        self.assertEqual(item["net_exact"], "650000.25")
        self.assertFalse(item["official"])

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
