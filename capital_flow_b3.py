from __future__ import annotations

import re
import threading
import time
from datetime import date, datetime
from decimal import Decimal
from typing import Any

import httpx

import capital_flow_store


B3_BASE_URL = "https://arquivos.b3.com.br/bdi"
B3_TABLE = "SharesInvesVolum"
B3_SOURCE = "B3 — Boletim Diário do Mercado (BDI)"
B3_LAG = "D-2 (dois pregões)"
_SYNC_TTL_SECONDS = 60 * 60
_sync_lock = threading.Lock()
_last_sync_at = 0.0


def _reference_date(payload: dict[str, Any]) -> str:
    texts = " ".join(
        str(text.get("textPt") or text.get("text") or "")
        for text in payload.get("texts", [])
        if isinstance(text, dict)
    )
    match = re.search(r"até o dia\s+(\d{2}/\d{2}/\d{4})", texts, re.IGNORECASE)
    if not match:
        raise ValueError("A B3 não informou a data de referência da tabela.")
    return datetime.strptime(match.group(1), "%d/%m/%Y").date().isoformat()


def _cumulative_rows(payload: dict[str, Any]) -> dict[str, tuple[Decimal, Decimal]]:
    rows: dict[str, tuple[Decimal, Decimal]] = {}
    for values in payload.get("values", []):
        if not isinstance(values, list) or len(values) < 4:
            continue
        label = str(values[0])
        investor = {
            "Investidor Estrangeiro": capital_flow_store.INVESTOR_FOREIGN,
            "Institucionais": capital_flow_store.INVESTOR_INSTITUTIONAL,
        }.get(label)
        if investor:
            # A tabela oficial é divulgada em R$ mil.
            rows[investor] = (
                Decimal(str(values[1])) * Decimal("1000"),
                Decimal(str(values[3])) * Decimal("1000"),
            )
    if set(rows) != capital_flow_store.INVESTOR_TYPES:
        raise ValueError("A tabela da B3 não contém todos os perfis esperados.")
    return rows


def fetch_b3_snapshots() -> list[dict[str, Any]]:
    today = date.today().isoformat()
    timeout = httpx.Timeout(30.0, connect=12.0)
    with httpx.Client(
        timeout=timeout,
        follow_redirects=True,
        headers={"accept": "application/json", "user-agent": "EKT-IA-Systems/1.0"},
    ) as client:
        workdays_response = client.get(
            f"{B3_BASE_URL}/table/workdays",
            params={"date": today, "limitDate": "D-21"},
        )
        workdays_response.raise_for_status()
        workdays = [
            str(item).split("T", 1)[0] for item in workdays_response.json()
        ]
        snapshots: dict[str, dict[str, Any]] = {}
        for bulletin_date in reversed(workdays):
            response = client.post(
                f"{B3_BASE_URL}/table/export",
                json={
                    "Name": B3_TABLE,
                    "Date": bulletin_date,
                    "FinalDate": bulletin_date,
                    "ClientId": "",
                    "Filters": {},
                },
            )
            if response.status_code != 200:
                continue
            payload = response.json()
            if not payload.get("values"):
                continue
            try:
                reference_date = _reference_date(payload)
                cumulative = _cumulative_rows(payload)
            except ValueError:
                continue
            snapshots[reference_date] = {
                "reference_date": reference_date,
                "bulletin_date": bulletin_date,
                "cumulative": cumulative,
            }
    return [snapshots[key] for key in sorted(snapshots)]


def _daily_records(snapshots: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    previous: dict[str, Any] | None = None
    for snapshot in snapshots:
        current_date = date.fromisoformat(snapshot["reference_date"])
        previous_date = (
            date.fromisoformat(previous["reference_date"]) if previous else None
        )
        same_month = bool(
            previous_date
            and previous_date.year == current_date.year
            and previous_date.month == current_date.month
        )
        for investor, (cumulative_in, cumulative_out) in snapshot[
            "cumulative"
        ].items():
            previous_values = (
                previous["cumulative"].get(investor) if same_month and previous else None
            )
            inflow = cumulative_in - previous_values[0] if previous_values else cumulative_in
            outflow = cumulative_out - previous_values[1] if previous_values else cumulative_out
            if inflow < 0 or outflow < 0:
                # Uma republicação pode revisar o acumulado. Não grave um diário inválido.
                continue
            result.append(
                {
                    "reference_date": snapshot["reference_date"],
                    "investor_type": investor,
                    "inflow": inflow,
                    "outflow": outflow,
                    "source": B3_SOURCE,
                    "source_lag": B3_LAG,
                    "notes": (
                        "Calculado pela diferença entre os acumulados oficiais do BDI. "
                        f"Boletim consultado: {snapshot['bulletin_date']}."
                    ),
                }
            )
        previous = snapshot
    # O primeiro snapshot só serve como base, exceto quando já é o primeiro pregão do mês.
    if snapshots:
        first = date.fromisoformat(snapshots[0]["reference_date"])
        if first.day > 4:
            result = [
                item for item in result if item["reference_date"] != first.isoformat()
            ]
    return result


def sync_official_data(*, force: bool = False) -> dict[str, Any]:
    global _last_sync_at
    if not force and time.monotonic() - _last_sync_at < _SYNC_TTL_SECONDS:
        return {"updated": 0, "cached": True}
    with _sync_lock:
        if not force and time.monotonic() - _last_sync_at < _SYNC_TTL_SECONDS:
            return {"updated": 0, "cached": True}
        snapshots = fetch_b3_snapshots()
        records = _daily_records(snapshots)
        updated = capital_flow_store.upsert_official_records(records)
        _last_sync_at = time.monotonic()
        return {
            "updated": updated,
            "cached": False,
            "reference_date": snapshots[-1]["reference_date"] if snapshots else None,
            "bulletin_date": snapshots[-1]["bulletin_date"] if snapshots else None,
        }
