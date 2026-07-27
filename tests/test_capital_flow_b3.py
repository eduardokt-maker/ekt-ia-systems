from decimal import Decimal
import unittest

import capital_flow_b3


class CapitalFlowB3Test(unittest.TestCase):
    def test_extracts_official_reference_date_and_values_in_reais(self):
        payload = {
            "texts": [
                {
                    "textPt": (
                        "Contribuição de diferentes perfis. "
                        "Dados acumulados do início do mês até o dia 22/07/2026."
                    )
                }
            ],
            "values": [
                ["Institucionais", 90845751, 12.22, 98542408, 13.26],
                ["Investidor Estrangeiro", 222507750, 29.93, 217893934, 29.31],
            ],
        }
        self.assertEqual(capital_flow_b3._reference_date(payload), "2026-07-22")
        rows = capital_flow_b3._cumulative_rows(payload)
        self.assertEqual(rows["Estrangeiro"][0], Decimal("222507750000"))

    def test_daily_values_are_differences_between_official_accumulated_values(self):
        snapshots = [
            {
                "reference_date": "2026-07-21",
                "bulletin_date": "2026-07-23",
                "cumulative": {
                    "Estrangeiro": (Decimal("1000"), Decimal("800")),
                    "Institucional brasileiro": (Decimal("500"), Decimal("700")),
                },
            },
            {
                "reference_date": "2026-07-22",
                "bulletin_date": "2026-07-24",
                "cumulative": {
                    "Estrangeiro": (Decimal("1400"), Decimal("900")),
                    "Institucional brasileiro": (Decimal("800"), Decimal("750")),
                },
            },
        ]
        records = capital_flow_b3._daily_records(snapshots)
        foreign = next(
            item
            for item in records
            if item["reference_date"] == "2026-07-22"
            and item["investor_type"] == "Estrangeiro"
        )
        self.assertEqual(foreign["inflow"], Decimal("400"))
        self.assertEqual(foreign["outflow"], Decimal("100"))


if __name__ == "__main__":
    unittest.main()
