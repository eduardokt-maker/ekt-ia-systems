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


def _next_value(lines: list[str], label: str, start: int = 0) -> str:
    wanted = _plain(label)
    for index in range(start, len(lines) - 1):
        if _plain(lines[index]) == wanted:
            return lines[index + 1]
    return ""


def _parse_santander_pix_receipt_text(
    text: str, filename: str, file_id: int
) -> list[dict[str, Any]]:
    lines = [_clean(line) for line in text.splitlines() if _clean(line)]
    plain = _plain("\n".join(lines))
    if "COMPROVANTE DO PIX" not in plain or "VALOR PAGO" not in plain:
        return []

    amount_text = _next_value(lines, "Valor pago").replace("R$", "")
    amount_match = re.search(r"(\d{1,3}(?:\.\d{3})*,\d{2})", amount_text)
    if amount_match is None:
        return []

    date_match = re.search(
        r"\b(\d{2}/\d{2})/\d{4}\s*-\s*(\d{2}:\d{2}:\d{2})\b", text
    )
    transaction_date = date_match.group(1) if date_match else ""
    transaction_id = _next_value(lines, "ID/Transação")
    if not transaction_id:
        transaction_id = _next_value(lines, "ID/Transa��o")

    receiver = _next_value(lines, "Para") or "Não identificado"
    account = _next_value(lines, "Forma de pagamento")
    details = ["Comprovante Pix Santander"]
    if account:
        details.append(account)
    authentication = _next_value(lines, "Código de autenticação")
    if not authentication:
        authentication = _next_value(lines, "C�digo de autentica��o")
    if authentication:
        details.append(f"Autenticação {authentication}")

    return [{
        "id": f"{file_id}-1",
        "file_id": file_id,
        "filename": filename,
        "page": 1,
        "posting_date": transaction_date,
        "transaction_date": transaction_date,
        "type": "Pix enviado",
        "description": "Comprovante do Pix",
        "destination": receiver,
        "document": transaction_id,
        "amount": float(_amount(amount_match.group(1))),
        "notes": " | ".join(details),
    }]


def parse_pdf_outflows(
    content: bytes, filename: str, file_id: int
) -> list[dict[str, Any]]:
    """Select the supported PDF layout without treating document text as commands."""
    reader = PdfReader(BytesIO(content))
    text = "\n".join(page.extract_text() or "" for page in reader.pages)
    receipt = _parse_santander_pix_receipt_text(text, filename, file_id)
    if receipt:
        return receipt
    return parse_santander_outflows(content, filename, file_id)


def parse_c6_pix_receipt_text(
    text: str, filename: str, file_id: int
) -> list[dict[str, Any]]:
    """Parse on-device OCR from a C6 Bank Pix receipt image."""
    lines = [_clean(line) for line in text.splitlines() if _clean(line)]
    plain = _plain("\n".join(lines))
    if "PIX" not in plain or not any(
        marker in plain
        for marker in ("PIX REALIZAD", "CONTA DE ORIGEM", "ID DA TRANS")
    ):
        return []

    amount_area = ""
    for index, line in enumerate(lines):
        if _plain(line).startswith("VALOR"):
            amount_area = " ".join(lines[index:index + 3])
            break
    amount_match = re.search(
        r"(?:R\s*[$S]?\s*)?(\d{1,3}(?:[.\s]\d{3})*[,\.]\d{2})",
        amount_area,
        re.IGNORECASE,
    )
    if amount_match is None:
        return []
    amount_value = amount_match.group(1).replace(" ", "")
    if "," not in amount_value and amount_value.count(".") == 1:
        amount_value = amount_value.replace(".", ",")

    date_match = re.search(r"\b(\d{2}\s*/\s*\d{2})\s*/\s*\d{4}\b", text)
    transaction_date = re.sub(r"\s+", "", date_match.group(1)) if date_match else ""

    transaction_id = ""
    for index, line in enumerate(lines):
        normalized_label = _plain(line)
        if normalized_label.startswith("ID") and "TRANS" in normalized_label:
            pieces = []
            for value in lines[index + 1:]:
                normalized_value = _plain(value)
                if normalized_value.startswith(("CHAVE", "CPF", "VALOR")):
                    break
                pieces.append(re.sub(r"\s+", "", value))
            transaction_id = "".join(pieces)[:120]
            break

    receiver = "Não identificado"
    origin_index = next(
        (i for i, line in enumerate(lines) if _plain(line) == "CONTA DE ORIGEM"),
        len(lines),
    )
    bank_index = next(
        (
            i
            for i, line in enumerate(lines[:origin_index])
            if _plain(line).startswith("BANCO:")
        ),
        -1,
    )
    if bank_index > 0:
        candidates = []
        for value in reversed(lines[:bank_index]):
            normalized = _plain(value)
            if normalized in {"PIX REALIZADO!", "PIX REALIZADO", "PIX EM ANDAMENTO"}:
                if candidates:
                    break
                continue
            if re.fullmatch(r"[A-Z]{1,3}", normalized):
                if candidates:
                    break
                continue
            if re.search(r"\d{2}/\d{2}/\d{4}|\d{2}:\d{2}", value):
                continue
            if normalized.startswith(("C6 BANK", "COMPROVANTE")):
                continue
            candidates.append(value)
            if len(candidates) >= 2:
                break
        if candidates:
            receiver = " ".join(reversed(candidates))

    authentication = _next_value(lines, "Código de autenticação")
    origin_index = next(
        (i for i, line in enumerate(lines) if _plain(line) == "CONTA DE ORIGEM"),
        -1,
    )
    origin = " | ".join(lines[origin_index + 1:origin_index + 6]) if origin_index >= 0 else ""
    notes = ["Comprovante Pix C6 Bank"]
    if authentication:
        notes.append(f"Autenticação {authentication}")
    if origin:
        notes.append(origin)

    return [{
        "id": f"{file_id}-1",
        "file_id": file_id,
        "filename": filename,
        "page": 1,
        "posting_date": transaction_date,
        "transaction_date": transaction_date,
        "type": "Pix enviado",
        "description": "Comprovante do Pix",
        "destination": receiver,
        "document": transaction_id,
        "amount": float(_amount(amount_value)),
        "notes": " | ".join(notes),
    }]


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
