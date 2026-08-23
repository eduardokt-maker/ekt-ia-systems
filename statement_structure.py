from __future__ import annotations

import re
from io import BytesIO
from typing import Any

from pypdf import PdfReader


DATE_RE = re.compile(r"\b(?:[0-3]?\d/[01]?\d/(?:\d{2}|\d{4})|[0-3]?\d/[01]?\d)\b")
MONEY_RE = re.compile(r"(?<!\d)(?:R\$\s*)?-?\d{1,3}(?:\.\d{3})*,\d{2}(?!\d)")
ACCOUNT_RE = re.compile(r"(?i)\b(?:ag[eê]ncia|conta(?: corrente)?)\b[^\n]{0,45}")


def analyze_pdf(content: bytes, filename: str) -> dict[str, Any]:
    reader = PdfReader(BytesIO(content))
    pages: list[dict[str, Any]] = []
    all_lines: list[str] = []
    for number, page in enumerate(reader.pages, start=1):
        text = (page.extract_text() or "").replace("\x00", "").strip()
        lines = [re.sub(r"\s+", " ", line).strip() for line in text.splitlines()]
        lines = [line for line in lines if line]
        all_lines.extend(lines)
        pages.append({
            "number": number,
            "line_count": len(lines),
            "text": "\n".join(lines),
        })

    joined = "\n".join(all_lines)
    upper = joined.upper()
    kind = "Extrato bancário"
    if "COMPROVANTE" in upper and "EXTRATO" not in upper:
        kind = "Comprovante bancário"
    elif "FATURA" in upper:
        kind = "Fatura"

    headings = []
    for line in all_lines:
        letters = re.sub(r"[^A-Za-zÀ-ÖØ-öø-ÿ]", "", line)
        if 3 <= len(line) <= 80 and letters and line == line.upper():
            if line not in headings:
                headings.append(line)

    labels = []
    for line in all_lines:
        if ":" in line:
            label = line.split(":", 1)[0].strip()
            if 2 <= len(label) <= 45 and label not in labels:
                labels.append(label)

    dates = list(dict.fromkeys(DATE_RE.findall(joined)))
    amounts = list(dict.fromkeys(MONEY_RE.findall(joined)))
    accounts = list(dict.fromkeys(match.group(0).strip() for match in ACCOUNT_RE.finditer(joined)))
    return {
        "filename": filename,
        "document_type": kind,
        "page_count": len(pages),
        "text_extractable": bool(joined),
        "line_count": len(all_lines),
        "headings": headings[:30],
        "field_labels": labels[:60],
        "dates_found": dates[:60],
        "amounts_found": amounts[:80],
        "account_references": accounts[:20],
        "pages": pages,
        "notes": [] if joined else [
            "O PDF não possui camada de texto; será necessário OCR para leitura."
        ],
    }


def analyze_file(item: dict[str, Any]) -> dict[str, Any]:
    filename = str(item["filename"])
    if filename.lower().endswith(".pdf"):
        return analyze_pdf(item["content"], filename)
    raise ValueError("A análise estrutural inicial está disponível para PDF.")
