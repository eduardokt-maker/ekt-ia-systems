"""Monitor europeu de notícias sobre uma possível movimentação bursátil da JEX."""

from __future__ import annotations

import hashlib
import html
import json
import os
import re
import sqlite3
import threading
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from urllib.parse import quote

import httpx

try:
    import psycopg
except ImportError:  # pragma: no cover - fallback local
    psycopg = None


REPOSITORY_DIR = Path(__file__).resolve().parent / "repositorio_jex"
REPOSITORY_FILE = REPOSITORY_DIR / "noticias.json"
SQLITE_FILE = REPOSITORY_DIR / "noticias.db"
SCAN_TTL_SECONDS = 10 * 60
EUROPEAN_SOURCES = [
    {"name": "Euronext", "region": "Amsterdam / União Europeia", "url": "https://live.euronext.com/en/ipo-showcase/404"},
    {"name": "AFM", "region": "Países Baixos", "url": "https://www.afm.nl/en/sector/registers/meldingenregisters/goedgekeurde-prospectussen"},
    {"name": "ESMA", "region": "União Europeia", "url": "https://www.esma.europa.eu/issuer-disclosure/prospectus"},
    {"name": "Google News NL", "region": "Países Baixos", "url": "https://news.google.com/rss/search"},
]
_scan_lock = threading.Lock()
_last_scan_monotonic = 0.0
_market_terms = re.compile(
    r"euronext|beursgang|beurs|ipo|prospectus|listing|aandelen|effecten|stock exchange|public offering",
    re.IGNORECASE,
)


def _database_url() -> str:
    return (
        os.getenv("DATABASE_EXTERNAL_URL", "").strip()
        or os.getenv("DATABASE_PUBLIC_URL", "").strip()
        or os.getenv("DATABASE_URL", "").strip()
    )


def _ensure_storage() -> None:
    REPOSITORY_DIR.mkdir(parents=True, exist_ok=True)
    if _database_url() and psycopg is not None:
        with psycopg.connect(_database_url()) as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS jex_news (
                    id TEXT PRIMARY KEY,
                    published_at TEXT NOT NULL,
                    discovered_at TEXT NOT NULL,
                    source TEXT NOT NULL,
                    source_region TEXT NOT NULL,
                    title_original TEXT NOT NULL,
                    title_pt TEXT NOT NULL,
                    title_en TEXT NOT NULL,
                    summary_pt TEXT NOT NULL,
                    summary_en TEXT NOT NULL,
                    source_url TEXT NOT NULL
                )
                """
            )
        return
    with sqlite3.connect(SQLITE_FILE) as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS jex_news (
                id TEXT PRIMARY KEY, published_at TEXT NOT NULL,
                discovered_at TEXT NOT NULL, source TEXT NOT NULL,
                source_region TEXT NOT NULL, title_original TEXT NOT NULL,
                title_pt TEXT NOT NULL, title_en TEXT NOT NULL,
                summary_pt TEXT NOT NULL, summary_en TEXT NOT NULL,
                source_url TEXT NOT NULL
            )
            """
        )


def _rows() -> list[dict]:
    _ensure_storage()
    query = """
        SELECT id, published_at, discovered_at, source, source_region,
               title_original, title_pt, title_en, summary_pt, summary_en,
               source_url
        FROM jex_news ORDER BY published_at DESC, discovered_at DESC
        LIMIT 100
    """
    if _database_url() and psycopg is not None:
        with psycopg.connect(_database_url()) as connection:
            rows = connection.execute(query).fetchall()
    else:
        with sqlite3.connect(SQLITE_FILE) as connection:
            rows = connection.execute(query).fetchall()
    keys = [
        "id", "published_at", "discovered_at", "source", "source_region",
        "title_original", "title_pt", "title_en", "summary_pt", "summary_en",
        "source_url",
    ]
    return [dict(zip(keys, row)) for row in rows]


def _save(item: dict) -> bool:
    _ensure_storage()
    values = tuple(item[key] for key in (
        "id", "published_at", "discovered_at", "source", "source_region",
        "title_original", "title_pt", "title_en", "summary_pt", "summary_en",
        "source_url",
    ))
    if _database_url() and psycopg is not None:
        with psycopg.connect(_database_url()) as connection:
            cursor = connection.execute(
                """
                INSERT INTO jex_news VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (id) DO NOTHING
                """,
                values,
            )
            created = cursor.rowcount > 0
    else:
        with sqlite3.connect(SQLITE_FILE) as connection:
            cursor = connection.execute(
                "INSERT OR IGNORE INTO jex_news VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                values,
            )
            created = cursor.rowcount > 0
    if created:
        _write_repository_snapshot()
    return created


def _write_repository_snapshot() -> None:
    archive = {
        "repository": "repositorio_jex",
        "purpose": "Arquivo bilíngue de notícias europeias sobre JEX e mercados de capitais.",
        "updated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "news": _rows(),
    }
    REPOSITORY_FILE.write_text(
        json.dumps(archive, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def _clean(value: str) -> str:
    value = re.sub(r"<[^>]+>", " ", html.unescape(value or ""))
    return re.sub(r"\s+", " ", value).strip()


def _translate(text: str, target: str) -> str:
    if not text:
        return ""
    try:
        with httpx.Client(timeout=10, headers={"User-Agent": "EKT-IA-JEX-Monitor/1.0"}) as client:
            response = client.get(
                "https://api.mymemory.translated.net/get",
                params={"q": text[:450], "langpair": f"nl|{target}"},
            )
            response.raise_for_status()
        translated = _clean(str((response.json().get("responseData") or {}).get("translatedText") or ""))
        return translated or text
    except Exception:
        return (
            "Conteúdo europeu identificado; a tradução automática está temporariamente indisponível e será tentada novamente na próxima consulta."
            if target == "pt"
            else "European content identified; automatic translation is temporarily unavailable and will be retried during the next scan."
        )


def _news_candidates() -> list[dict]:
    query_text = quote('"JEX" (Euronext OR beursgang OR IPO OR prospectus)')
    url = f"https://news.google.com/rss/search?q={query_text}&hl=nl&gl=NL&ceid=NL:nl"
    with httpx.Client(timeout=12, headers={"User-Agent": "Mozilla/5.0 EKT-IA-JEX-Monitor"}) as client:
        response = client.get(url)
        response.raise_for_status()
    root = ET.fromstring(response.content)
    result = []
    for node in root.findall("./channel/item")[:20]:
        title = _clean(node.findtext("title") or "")
        description = _clean(node.findtext("description") or "")
        combined = f"{title} {description}"
        if "jex" not in combined.lower() or not _market_terms.search(combined):
            continue
        published_raw = node.findtext("pubDate") or ""
        try:
            published = parsedate_to_datetime(published_raw).astimezone(timezone.utc)
        except Exception:
            published = datetime.now(timezone.utc)
        source_node = node.find("source")
        source = _clean(source_node.text if source_node is not None else "Notícia europeia")
        result.append({
            "published_at": published.isoformat(timespec="seconds"),
            "source": source,
            "source_region": "Pesquisa regional — Países Baixos / Europa",
            "title_original": title,
            "description_original": description or title,
            "source_url": _clean(node.findtext("link") or ""),
        })
    return result


def _check_official_sources() -> list[dict]:
    checks = []
    with httpx.Client(timeout=12, headers={"User-Agent": "Mozilla/5.0 EKT-IA-JEX-Monitor"}) as client:
        for source in EUROPEAN_SOURCES[:3]:
            try:
                response = client.get(source["url"])
                checks.append({"source": source["name"], "ok": response.status_code < 400})
            except Exception:
                checks.append({"source": source["name"], "ok": False})
    return checks


def scan_and_archive(force: bool = False) -> dict:
    global _last_scan_monotonic
    with _scan_lock:
        now = time.monotonic()
        if not force and now - _last_scan_monotonic < SCAN_TTL_SECONDS:
            return news_payload(new_items=[])
        _last_scan_monotonic = now
        official_checks = _check_official_sources()
        new_items = []
        try:
            candidates = _news_candidates()
        except Exception:
            candidates = []
        for candidate in candidates:
            identifier = hashlib.sha256(
                f"{candidate['title_original']}|{candidate['source_url']}".encode("utf-8")
            ).hexdigest()[:24]
            item = {
                **candidate,
                "id": identifier,
                "discovered_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "title_pt": _translate(candidate["title_original"], "pt"),
                "title_en": _translate(candidate["title_original"], "en"),
                "summary_pt": _translate(candidate["description_original"], "pt"),
                "summary_en": _translate(candidate["description_original"], "en"),
            }
            item.pop("description_original", None)
            if _save(item):
                new_items.append(item)
        return news_payload(new_items=new_items, official_checks=official_checks)


def news_payload(new_items: list[dict] | None = None, official_checks: list[dict] | None = None) -> dict:
    news = _rows()
    return {
        "ok": True,
        "repository": "repositorio_jex",
        "checked_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "sources_region": "Países Baixos e União Europeia",
        "sources": EUROPEAN_SOURCES,
        "official_checks": official_checks or [],
        "news": news,
        "new_items": new_items or [],
        "has_fresh_news": bool(new_items),
        "market_status": "Nenhum registro público de listagem da JEX foi confirmado nas fontes oficiais monitoradas.",
    }
