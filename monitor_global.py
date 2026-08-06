from __future__ import annotations

import math
import os
import re
import subprocess
import time
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import Any, Protocol
from zoneinfo import ZoneInfo


SAO_PAULO = ZoneInfo("America/Sao_Paulo")
DEFAULT_WORKBOOK = Path(__file__).with_name("integrations") / "profit_rtd" / "profit_market_data.xlsx"
POC_TICKERS = ("WIN", "WDO", "IBOV", "PETR4", "VALE3")
ERROR_TOKENS = {"#N/A", "#VALOR!", "#VALUE!", "#REF!", "#NOME?", "#NAME?", "#NUM!"}


class ProfitRTDProvider(Protocol):
    def snapshot(self) -> dict: ...


@dataclass
class MarketQuote:
    ticker: str
    name: str
    market: str
    price: float | None
    change_points: float | None
    change_percent: float | None
    open: float | None
    high: float | None
    low: float | None
    previous_close: float | None
    volume: float | None
    source_timestamp: str | None
    read_timestamp: str
    source: str
    data_status: str
    message: str
    age_seconds: float | None


def _process_running(pattern: str) -> bool:
    try:
        output = subprocess.check_output(
            ["tasklist", "/FO", "CSV", "/NH"], text=True, errors="ignore", timeout=4
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return re.search(pattern, output, flags=re.IGNORECASE) is not None


def _number(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        number = float(value)
        return number if math.isfinite(number) else None
    text = str(value).strip()
    if not text or text.upper() in ERROR_TOKENS:
        return None
    cleaned = text.replace("R$", "").replace("%", "").replace(" ", "")
    if "," in cleaned:
        cleaned = cleaned.replace(".", "").replace(",", ".")
    try:
        number = float(cleaned)
        return number if math.isfinite(number) else None
    except ValueError:
        return None


def _timestamp(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        return value.replace(tzinfo=value.tzinfo or SAO_PAULO).astimezone(SAO_PAULO)
    text = str(value or "").strip()
    for fmt in ("%d/%m/%Y %H:%M:%S", "%d/%m/%Y %H:%M", "%H:%M:%S", "%H:%M"):
        try:
            parsed = datetime.strptime(text, fmt)
            if fmt.startswith("%H"):
                now = datetime.now(SAO_PAULO)
                parsed = parsed.replace(year=now.year, month=now.month, day=now.day)
            return parsed.replace(tzinfo=SAO_PAULO)
        except ValueError:
            continue
    return None


class ExcelBridgeService:
    """Read calculated RTD values from an already-open Excel workbook via COM."""

    def __init__(self, workbook_path: Path | None = None):
        self.workbook_path = Path(os.getenv("PROFIT_RTD_WORKBOOK", workbook_path or DEFAULT_WORKBOOK))

    def read_rows(self) -> tuple[list[list[Any]], dict]:
        started = time.perf_counter()
        profit_running = _process_running(r"profit.*\.exe")
        excel_running = _process_running(r"excel\.exe")
        base = {
            "profit_running": profit_running,
            "excel_running": excel_running,
            "workbook_found": self.workbook_path.exists(),
            "workbook_path": str(self.workbook_path),
            "errors": [],
        }
        if not excel_running:
            base["errors"].append("Excel fechado")
            return [], self._finish(base, started)
        try:
            import win32com.client  # type: ignore
            excel = win32com.client.GetActiveObject("Excel.Application")
            workbook = next(
                (item for item in excel.Workbooks if Path(item.FullName).resolve() == self.workbook_path.resolve()),
                None,
            )
            if workbook is None:
                base["errors"].append("A pasta de trabalho não está aberta no Excel")
                return [], self._finish(base, started)
            sheet = workbook.Worksheets("MARKET_DATA")
            values = sheet.Range("A2:O201").Value
            rows = [list(row) for row in values if row and str(row[0] or "").strip()]
            return rows, self._finish(base, started)
        except ImportError:
            base["errors"].append("Conector COM indisponível; instale pywin32")
        except Exception as exc:
            base["errors"].append(f"Falha de leitura COM: {type(exc).__name__}")
        return [], self._finish(base, started)

    @staticmethod
    def _finish(data: dict, started: float) -> dict:
        data["read_at"] = datetime.now(SAO_PAULO).isoformat()
        data["latency_ms"] = round((time.perf_counter() - started) * 1000, 1)
        return data


class ExternalMarketProvider:
    def snapshot(self) -> dict[str, MarketQuote]:
        return {}


class MarketStatusService:
    def classify(self, source_time: datetime | None, stale_limit: int, bridge: dict) -> tuple[str, str, float | None]:
        if not bridge["profit_running"]:
            return "profit_closed", "Profit fechado", None
        if not bridge["excel_running"]:
            return "excel_closed", "Excel fechado", None
        if source_time is None:
            return "source_error", "Horário RTD indisponível", None
        age = max(0.0, (datetime.now(SAO_PAULO) - source_time).total_seconds())
        if age > stale_limit * 2:
            return "stale", f"Dado desatualizado — última leitura às {source_time:%H:%M:%S}", age
        if age > stale_limit:
            return "possibly_delayed", "Dado possivelmente atrasado", age
        return "updated", "Atualizado", age


class MarketDataService:
    def __init__(self, bridge: ExcelBridgeService | None = None):
        self.bridge = bridge or ExcelBridgeService()
        self.status_service = MarketStatusService()

    def snapshot(self) -> dict:
        rows, diagnostics = self.bridge.read_rows()
        read_time = datetime.now(SAO_PAULO).isoformat()
        quotes = []
        for row in rows:
            ticker = str(row[0] or "").strip().upper()
            if ticker not in POC_TICKERS:
                continue
            source_time = _timestamp(row[12])
            stale_limit = 15
            status, message, age = self.status_service.classify(source_time, stale_limit, diagnostics)
            quote = MarketQuote(
                ticker=ticker,
                name=str(row[1] or ticker), market=str(row[2] or ""), price=_number(row[3]),
                change_points=_number(row[4]), change_percent=_number(row[5]), open=_number(row[6]),
                high=_number(row[7]), low=_number(row[8]), previous_close=_number(row[9]),
                volume=_number(row[10]), source_timestamp=source_time.isoformat() if source_time else None,
                read_timestamp=read_time, source=str(row[14] or "Profit RTD"), data_status=status,
                message=message, age_seconds=round(age, 1) if age is not None else None,
            )
            quotes.append(asdict(quote))
        diagnostics["active_assets"] = len(quotes)
        diagnostics["stale_assets"] = sum(q["data_status"] in {"stale", "possibly_delayed"} for q in quotes)
        diagnostics["error_assets"] = sum(q["data_status"].endswith("closed") or q["data_status"] == "source_error" for q in quotes)
        diagnostics["message"] = (
            "Integração Profit RTD operacional."
            if diagnostics["profit_running"] and diagnostics["excel_running"] and quotes
            else "Fonte Profit indisponível. Abra o Profit e o Excel para iniciar as atualizações."
        )
        return {"ok": True, "quotes": quotes, "diagnostics": diagnostics, "poc_tickers": list(POC_TICKERS)}


market_data_service = MarketDataService()
