from __future__ import annotations

import re
import unicodedata
from decimal import Decimal
from io import BytesIO
from typing import Any

from pypdf import PdfReader


DATE = re.compile(r"^(?:(\d{2}/\d{2})\s+)?")
MONEY = re.compile(r"(?<![\d.,])(\d{1,3}(?:\.\d{3})*,\d{2})(-?)(?![\d.,])")
TRANSACTION = re.compile(
    r"^(?:(\d{2}/\d{2})\s+)?(PIX ENVIADO|PIX RECEBIDO|DEBITO VISA ELECTRON BRASIL|"
    r"PAGAMENTO DE BOLETO(?: OUTROS BANCOS)?|JUROS SALDO UTILIZ ATE LIMITE|"
    r"IOF IMPOSTO OPERACOES FINANCEIRAS|IOF ADICIONAL - AUTOMATICO|"
    r"RESGATE CDB/RDB|CREDITO LIBERADO PARA PIX|DEBITO AUT\. TELEFONE CELULAR|"
    r"MENSALIDADE DE SEGURO|DEBITO AUTOMATICO|TARIFA[^\n]*)(?:\s+(.*))?$",
    re.IGNORECASE,
)


def _clean(value: str) -> str:
    return re.sub(r"\s+", " ", value.replace("�", "")).strip()


def _plain(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    return "".join(char for char in normalized if not unicodedata.combining(char)).upper()


def _amount(value: str) -> Decimal:
    return Decimal(value.replace(".", "").replace(",", "."))


def _kind(description: str) -> str:
    text = _plain(description)
    if text.startswith("DEBITO VISA"):
        return "Cartão de débito"
    if text.startswith("PIX ENVIADO"):
        return "Pix enviado"
    if text.startswith("PAGAMENTO DE BOLETO"):
        return "Boleto"
    if text.startswith("DEBITO AUT") or text.startswith("DEBITO AUTOMATICO"):
        return "Débito automático"
    if text.startswith("JUROS"):
        return "Juros"
    if text.startswith("IOF"):
        return "IOF"
    if text.startswith("MENSALIDADE"):
        return "Seguro"
    if text.startswith("TARIFA"):
        return "Tarifa"
    return "Outras saídas"


def _destination(kind: str, description: str, details: list[str]) -> str:
    candidates = []
    for line in details:
        value = MONEY.sub("", line)
        value = re.sub(r"^\d{2}/\d{2}\s+", "", value)
        value = re.sub(r"^[-\d\s.]+$", "", value).strip(" -")
        if value and not value.upper().startswith("PERIODO:"):
            candidates.append(value)
    if candidates:
        return _clean(candidates[0])
    if kind in {"Juros", "IOF", "Tarifa"}:
        return "Santander"
    return _clean(description)


def parse_santander_outflows(content: bytes, filename: str, file_id: int) -> list[dict[str, Any]]:
    reader = PdfReader(BytesIO(content))
    lines: list[tuple[int, str]] = []
    active = False
    finished = False
    for page_number, page in enumerate(reader.pages, start=1):
        for raw in (page.extract_text() or "").splitlines():
            line = _clean(raw)
            if not active and line == "Movimentação" and page_number <= 3:
                active = True
                continue
            if active and (line.startswith("Saldos por Período") or line.startswith("Compras com Cartão de Débito")):
                finished = True
                break
            if active:
                lines.append((page_number, line))
        if finished:
            break

    entries: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    posting_date = ""

    def finish() -> None:
        nonlocal current
        if current is None:
            return
        text = " ".join(current["details"])
        matches = list(MONEY.finditer(" ".join([current["tail"], text])))
        description = current["description"]
        outgoing = description.upper() not in {
            "PIX RECEBIDO", "RESGATE CDB/RDB", "CREDITO LIBERADO PARA PIX"
        }
        if matches and outgoing:
            first = matches[0]
            value = _amount(first.group(1))
            kind = _kind(description)
            purchase_date = ""
            for detail in current["details"]:
                found = re.match(r"^(\d{2}/\d{2})\b", detail)
                if found:
                    purchase_date = found.group(1)
                    break
            document = ""
            for detail in reversed([current["tail"], *current["details"]]):
                found = re.search(r"\b(\d{6})\b", detail)
                if found:
                    document = found.group(1)
                    break
            entries.append({
                "id": f"{file_id}-{len(entries) + 1}",
                "file_id": file_id,
                "filename": filename,
                "page": current["page"],
                "posting_date": current["posting_date"],
                "transaction_date": purchase_date or current["posting_date"],
                "type": kind,
                "description": description.title(),
                "destination": _destination(
                    kind, description, [current["tail"], *current["details"]]
                ),
                "document": document,
                "amount": float(value),
            })
        current = None

    for page, line in lines:
        if not line or line.startswith(("Data Descrição", "Data Descri", "SALDO EM")):
            continue
        match = TRANSACTION.match(line)
        if match:
            finish()
            if match.group(1):
                posting_date = match.group(1)
            current = {
                "page": page,
                "posting_date": posting_date,
                "description": match.group(2).upper(),
                "tail": match.group(3) or "",
                "details": [],
            }
        elif current is not None:
            current["details"].append(line)
    finish()
    return entries


def summarize_outflows(entries: list[dict[str, Any]]) -> dict[str, Any]:
    by_type: dict[str, dict[str, Any]] = {}
    by_destination: dict[str, dict[str, Any]] = {}
    for item in entries:
        for target, key in ((by_type, item["type"]), (by_destination, item["destination"])):
            bucket = target.setdefault(key, {"name": key, "count": 0, "amount": 0.0})
            bucket["count"] += 1
            bucket["amount"] = round(bucket["amount"] + item["amount"], 2)
    return {
        "count": len(entries),
        "total": round(sum(item["amount"] for item in entries), 2),
        "by_type": sorted(by_type.values(), key=lambda row: row["amount"], reverse=True),
        "by_destination": sorted(by_destination.values(), key=lambda row: row["amount"], reverse=True)[:20],
    }
