from decimal import Decimal
from datetime import date
import threading
import time
import unittest
from unittest.mock import Mock, patch

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

    def test_recent_endpoint_receives_iso_date_format(self):
        bulletin = date.today()
        reference = bulletin.strftime("%d/%m/%Y")
        response = Mock()
        response.status_code = 200
        response.json.return_value = {
            "texts": [
                {
                    "textPt": (
                        f"Dados acumulados do início do mês até o dia {reference}."
                    )
                }
            ],
            "values": [
                ["Institucionais", 100, 1, 90, 1],
                ["Investidor Estrangeiro", 200, 2, 180, 2],
            ],
        }
        client = Mock()
        client.post.return_value = response

        snapshot = capital_flow_b3._fetch_snapshot(client, bulletin)

        self.assertEqual(snapshot["reference_date"], bulletin.isoformat())
        request = client.post.call_args.kwargs["json"]
        self.assertEqual(request["Date"], bulletin.isoformat())
        self.assertEqual(request["FinalDate"], bulletin.isoformat())

    def test_month_windows_expand_query_to_complete_months(self):
        self.assertEqual(
            capital_flow_b3._month_windows(
                date(2026, 1, 15), date(2026, 3, 2)
            ),
            [
                (date(2026, 1, 1), date(2026, 1, 31)),
                (date(2026, 2, 1), date(2026, 2, 28)),
                (date(2026, 3, 1), date(2026, 3, 31)),
            ],
        )

    def test_background_sync_returns_immediately_and_reports_completion(self):
        started = threading.Event()
        release = threading.Event()

        def fake_sync(*args, **kwargs):
            started.set()
            release.wait(timeout=2)
            return {"updated": 12, "cached": False}

        with capital_flow_b3._job_lock:
            capital_flow_b3._sync_job.clear()
            capital_flow_b3._sync_job["status"] = "idle"
        with patch.object(capital_flow_b3, "sync_official_data", fake_sync):
            status = capital_flow_b3.start_background_sync(
                "2026-01-01", "2026-01-31"
            )
            self.assertTrue(started.wait(timeout=1))
            self.assertEqual(status["status"], "running")
            release.set()
            deadline = time.monotonic() + 2
            while (
                capital_flow_b3.sync_job_status()["status"] == "running"
                and time.monotonic() < deadline
            ):
                time.sleep(0.01)
            finished = capital_flow_b3.sync_job_status()
            self.assertEqual(finished["status"], "completed")
            self.assertEqual(finished["updated"], 12)


if __name__ == "__main__":
    unittest.main()
