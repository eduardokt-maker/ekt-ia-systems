from __future__ import annotations

import io
import re
import threading
import time
from calendar import monthrange
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import Any, Callable

import httpx
from pypdf import PdfReader

import capital_flow_store


B3_BASE_URL = "https://arquivos.b3.com.br/bdi"
B3_TABLE = "SharesInvesVolum"
B3_SOURCE = "B3 — Boletim Diário do Mercado (BDI)"
B3_LAG = "D-2 (dois pregões)"
_SYNC_TTL_SECONDS = 60 * 60
_sync_lock = threading.Lock()
_job_lock = threading.Lock()
_last_sync_at = 0.0
_sync_job: dict[str, Any] = {
    "status": "idle",
    "completed_months": 0,
    "total_months": 0,
    "processed_bulletins": 0,
    "total_bulletins": 0,
}


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


def _bulletin_dates(start: date, end: date) -> list[date]:
    # A margem final captura os últimos pregões do mês, publicados com defasagem.
    last = min(end + timedelta(days=7), date.today())
    return [
        start + timedelta(days=offset)
        for offset in range((last - start).days + 1)
        if (start + timedelta(days=offset)).weekday() < 5
    ]


def _fetch_snapshot(
    client: httpx.Client, bulletin_date: date
) -> dict[str, Any] | None:
    if (date.today() - bulletin_date).days > 21:
        return _fetch_pdf_snapshot(client, bulletin_date)
    try:
        response = client.post(
            f"{B3_BASE_URL}/table/export",
            json={
                "Name": B3_TABLE,
                "Date": bulletin_date.isoformat(),
                "FinalDate": bulletin_date.isoformat(),
                "ClientId": "",
                "Filters": {},
            },
        )
    except httpx.HTTPError:
        return None
    if response.status_code != 200:
        return None
    try:
        payload = response.json()
    except ValueError:
        return None
    if not payload.get("values"):
        return None
    try:
        reference_date = _reference_date(payload)
        cumulative = _cumulative_rows(payload)
    except ValueError:
        return None
    return {
        "reference_date": reference_date,
        "bulletin_date": bulletin_date.isoformat(),
        "cumulative": cumulative,
    }


def _pdf_amount(text: str) -> Decimal:
    return Decimal(text.replace(".", "")) * Decimal("1000")


def _fetch_pdf_snapshot(
    client: httpx.Client, bulletin_date: date
) -> dict[str, Any] | None:
    iso = bulletin_date.isoformat()
    compact = bulletin_date.strftime("%Y%m%d")
    try:
        response = client.get(
            f"{B3_BASE_URL}/download/bdi/{iso}/BDI_02_{compact}.pdf"
        )
    except httpx.HTTPError:
        return None
    if response.status_code != 200 or not response.content.startswith(b"%PDF"):
        return None
    try:
        reader = PdfReader(io.BytesIO(response.content))
        texts: list[str] = []
        # A seção oficial fica próxima da página 47. Alguns boletins anexavam
        # prospectos extensos, portanto a posição não pode ser calculada pelo fim.
        first_page = min(38, len(reader.pages))
        last_page = min(55, len(reader.pages))
        for page_index in range(first_page, last_page):
            text = reader.pages[page_index].extract_text() or ""
            if "Investidor Estrangeiro" in text and "Institucionais" in text:
                texts.append(text)
                break
        if not texts:
            return None
        text = texts[0]
        date_match = re.search(r"dia\s+(\d{2}/\d{2}/\d{4})", text)
        foreign = re.search(
            r"Investidor Estrangeiro\s+([\d.]+)\s+[\d,]+\s+([\d.]+)", text
        )
        institutional = re.search(
            r"Institucionais\s+([\d.]+)\s+[\d,]+\s+([\d.]+)", text
        )
        if not date_match or not foreign or not institutional:
            return None
        reference_date = datetime.strptime(
            date_match.group(1), "%d/%m/%Y"
        ).date().isoformat()
        return {
            "reference_date": reference_date,
            "bulletin_date": iso,
            "cumulative": {
                capital_flow_store.INVESTOR_FOREIGN: (
                    _pdf_amount(foreign.group(1)),
                    _pdf_amount(foreign.group(2)),
                ),
                capital_flow_store.INVESTOR_INSTITUTIONAL: (
                    _pdf_amount(institutional.group(1)),
                    _pdf_amount(institutional.group(2)),
                ),
            },
        }
    except Exception:
        return None


def fetch_b3_snapshots(
    date_from: date,
    date_to: date,
    progress: Callable[[date, int, int], None] | None = None,
) -> list[dict[str, Any]]:
    timeout = httpx.Timeout(30.0, connect=12.0)
    with httpx.Client(
        timeout=timeout,
        follow_redirects=True,
        headers={"accept": "application/json", "user-agent": "EKT-IA-Systems/1.0"},
    ) as client:
        snapshots: dict[str, dict[str, Any]] = {}
        failed: list[date] = []
        bulletins = _bulletin_dates(date_from, date_to)
        processed = 0
        with ThreadPoolExecutor(max_workers=6) as executor:
            futures = {
                executor.submit(_fetch_snapshot, client, bulletin): bulletin
                for bulletin in bulletins
            }
            for future in as_completed(futures):
                try:
                    snapshot = future.result()
                except Exception:
                    snapshot = None
                processed += 1
                if progress:
                    progress(futures[future], processed, len(bulletins))
                if snapshot is None:
                    failed.append(futures[future])
                    continue
                reference = date.fromisoformat(snapshot["reference_date"])
                if date_from <= reference <= date_to:
                    snapshots[snapshot["reference_date"]] = snapshot
        # A B3 pode limitar downloads paralelos. Uma segunda passagem sequencial
        # recupera boletins válidos sem repetir os que já foram obtidos.
        for bulletin in failed:
            snapshot = _fetch_snapshot(client, bulletin)
            if snapshot is None:
                continue
            reference = date.fromisoformat(snapshot["reference_date"])
            if date_from <= reference <= date_to:
                snapshots[snapshot["reference_date"]] = snapshot
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
    return result


def _month_windows(start: date, end: date) -> list[tuple[date, date]]:
    windows: list[tuple[date, date]] = []
    cursor = date(start.year, start.month, 1)
    while cursor <= end:
        month_end = date(
            cursor.year, cursor.month, monthrange(cursor.year, cursor.month)[1]
        )
        windows.append((cursor, month_end))
        cursor = month_end + timedelta(days=1)
    return windows


def _recently_checked(status: dict[str, Any] | None) -> bool:
    if not status:
        return False
    try:
        checked = datetime.fromisoformat(status["checked_at"])
        if checked.tzinfo is not None:
            checked = checked.astimezone().replace(tzinfo=None)
        return (datetime.now() - checked).total_seconds() < _SYNC_TTL_SECONDS
    except (TypeError, ValueError):
        return False


def sync_official_data(
    date_from: str | None = None,
    date_to: str | None = None,
    *,
    force: bool = False,
    progress: Callable[[dict[str, Any]], None] | None = None,
) -> dict[str, Any]:
    global _last_sync_at
    today = date.today()
    start = date.fromisoformat(date_from) if date_from else date(today.year, 1, 1)
    end = min(date.fromisoformat(date_to) if date_to else today, today)
    if start > end:
        return {"updated": 0, "cached": True}
    with _sync_lock:
        updated = 0
        scanned_months: list[str] = []
        cached_months: list[str] = []
        latest_snapshot: dict[str, Any] | None = None
        current_month = today.strftime("%Y-%m")
        windows = _month_windows(start, end)
        completed = 0
        for month_start, month_end in windows:
            month_key = month_start.strftime("%Y-%m")
            if progress:
                progress(
                    {
                        "current_month": month_key,
                        "completed_months": completed,
                        "total_months": len(windows),
                        "processed_bulletins": 0,
                        "total_bulletins": len(
                            _bulletin_dates(month_start, month_end)
                        ),
                    }
                )
            status = capital_flow_store.month_sync_status(month_key)
            if status and (
                status["is_complete"]
                or (
                    month_key == current_month
                    and not force
                    and _recently_checked(status)
                )
            ):
                cached_months.append(month_key)
                completed += 1
                if progress:
                    progress(
                        {
                            "current_month": month_key,
                            "completed_months": completed,
                            "total_months": len(windows),
                        }
                    )
                continue
            snapshots = fetch_b3_snapshots(
                month_start,
                month_end,
                progress=(
                    lambda bulletin, done, total, key=month_key: progress(
                        {
                            "current_month": key,
                            "current_bulletin": bulletin.isoformat(),
                            "completed_months": completed,
                            "total_months": len(windows),
                            "processed_bulletins": done,
                            "total_bulletins": total,
                        }
                    )
                    if progress
                    else None
                ),
            )
            if snapshots:
                latest_snapshot = snapshots[-1]
                updated += capital_flow_store.upsert_official_records(
                    _daily_records(snapshots)
                )
            if snapshots:
                capital_flow_store.mark_month_synced(
                    month_key,
                    complete=month_key < current_month and len(snapshots) >= 15,
                )
            scanned_months.append(month_key)
            completed += 1
            if progress:
                progress(
                    {
                        "current_month": month_key,
                        "completed_months": completed,
                        "total_months": len(windows),
                    }
                )
        _last_sync_at = time.monotonic()
        return {
            "updated": updated,
            "cached": not scanned_months,
            "scanned_months": scanned_months,
            "cached_months": cached_months,
            "reference_date": (
                latest_snapshot["reference_date"] if latest_snapshot else None
            ),
            "bulletin_date": (
                latest_snapshot["bulletin_date"] if latest_snapshot else None
            ),
        }


def sync_job_status() -> dict[str, Any]:
    with _job_lock:
        return dict(_sync_job)


def _update_job(values: dict[str, Any]) -> None:
    with _job_lock:
        _sync_job.update(values)


def start_background_sync(
    date_from: str, date_to: str, *, force: bool = False
) -> dict[str, Any]:
    with _job_lock:
        if _sync_job.get("status") == "running":
            return dict(_sync_job)
        if (
            not force
            and _sync_job.get("status") == "completed"
            and _sync_job.get("date_from") == date_from
            and _sync_job.get("date_to") == date_to
        ):
            return dict(_sync_job)
        _sync_job.clear()
        _sync_job.update(
            {
                "status": "running",
                "date_from": date_from,
                "date_to": date_to,
                "completed_months": 0,
                "total_months": len(
                    _month_windows(
                        date.fromisoformat(date_from),
                        min(date.fromisoformat(date_to), date.today()),
                    )
                ),
                "processed_bulletins": 0,
                "total_bulletins": 0,
                "updated": 0,
                "error": None,
            }
        )

    def run() -> None:
        try:
            result = sync_official_data(
                date_from,
                date_to,
                force=force,
                progress=lambda values: _update_job(
                    {"status": "running", **values}
                ),
            )
            _update_job(
                {
                    **result,
                    "status": "completed",
                    "completed_months": _sync_job.get("total_months", 0),
                }
            )
        except Exception as exc:
            _update_job(
                {
                    "status": "failed",
                    "error": str(exc)[:240],
                }
            )

    threading.Thread(
        target=run, name="capital-flow-history-sync", daemon=True
    ).start()
    return sync_job_status()
