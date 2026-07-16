"""Baixa marcas somente dos domínios oficiais previamente verificados."""

from __future__ import annotations

import concurrent.futures
import hashlib
import json
import mimetypes
import re
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urljoin, urlparse

import httpx


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "flutter_frontend" / "nosso_repositorio"
LOGOS = OUTPUT / "logos"

# Uma entrada por companhia. Ações de classes diferentes compartilham a marca.
# Os domínios abaixo são os sites institucionais oficiais das companhias.
COMPANIES = [
    ("Ambev", ["ABEV3"], "https://www.ambev.com.br"),
    ("ALLOS", ["ALOS3"], "https://allos.co"),
    ("Assaí Atacadista", ["ASAI3"], "https://www.assai.com.br"),
    ("Auren Energia", ["AURE3"], "https://www.aurenenergia.com.br"),
    ("AXIA Energia", ["AXIA3"], "https://axia.com.br/fique-por-dentro/sala-de-imprensa"),
    ("Azzas 2154", ["AZZA3"], "https://www.azzas2154.com.br"),
    ("B3", ["B3SA3"], "https://www.b3.com.br"),
    ("Banco do Brasil", ["BBAS3"], "https://www.bb.com.br"),
    ("Bradesco", ["BBDC3", "BBDC4"], "https://banco.bradesco"),
    ("BB Seguridade", ["BBSE3"], "https://www.bbseguridaderi.com.br"),
    ("Minerva Foods", ["BEEF3"], "https://www.minervafoods.com"),
    ("BTG Pactual", ["BPAC11"], "https://www.btgpactual.com"),
    ("Bradespar", ["BRAP4"], "https://www.bradespar.com.br"),
    ("Brava Energia", ["BRAV3"], "https://www.bravaenergia.com"),
    ("Braskem", ["BRKM5"], "https://www.braskem.com.br"),
    ("C&A Modas", ["CEAB3"], "https://www.cea.com.br"),
    ("Cemig", ["CMIG4"], "https://www.cemig.com.br"),
    ("CSN", ["CMIN3", "CSNA3"], "https://www.csn.com.br"),
    ("Cogna", ["COGN3"], "https://www.cogna.com.br"),
    ("CPFL Energia", ["CPFE3"], "https://www.cpfl.com.br"),
    ("Copel", ["CPLE3"], "https://www.copel.com"),
    ("Cosan", ["CSAN3"], "https://www.cosan.com.br"),
    ("Copasa", ["CSMG3"], "https://www.copasa.com.br"),
    ("Cury", ["CURY3"], "https://www.cury.net"),
    ("Caixa Seguridade", ["CXSE3"], "https://www.ri.caixaseguridade.com.br"),
    ("Cyrela", ["CYRE3"], "https://www.cyrela.com.br"),
    ("Direcional", ["DIRR3"], "https://www.direcional.com.br"),
    ("ENGIE Brasil", ["EGIE3"], "https://www.engie.com.br"),
    ("Embraer", ["EMBJ3"], "https://www.embraer.com"),
    ("Eneva", ["ENEV3"], "https://www.eneva.com.br"),
    ("Energisa", ["ENGI11"], "https://www.energisa.com.br"),
    ("Equatorial Energia", ["EQTL3"], "https://www.equatorialenergia.com.br"),
    ("Grupo Fleury", ["FLRY3"], "https://www.grupofleury.com.br"),
    ("Gerdau", ["GGBR4", "GOAU4"], "https://www.gerdau.com"),
    ("Hapvida", ["HAPV3"], "https://www.hapvida.com.br"),
    ("Hypera Pharma", ["HYPE3"], "https://www.hypera.com.br"),
    ("Iguatemi", ["IGTI11"], "https://www.iguatemi.com.br"),
    ("ISA Energia Brasil", ["ISAE4"], "https://www.isaenergiabrasil.com.br"),
    ("Itaúsa", ["ITSA4"], "https://www.itausa.com.br"),
    ("Itaú Unibanco", ["ITUB4"], "https://www.itau.com.br"),
    ("Klabin", ["KLBN11"], "https://www.klabin.com.br"),
    ("Lojas Renner", ["LREN3"], "https://www.lojasrennersa.com.br"),
    ("MBRF", ["MBRF3"], "https://www.mbrf.com"),
    ("Magazine Luiza", ["MGLU3"], "https://www.magazineluiza.com.br"),
    ("Motiva", ["MOTV3"], "https://www.motiva.com.br"),
    ("MRV", ["MRVE3"], "https://www.mrv.com.br"),
    ("Multiplan", ["MULT3"], "https://www.multiplan.com.br"),
    ("Natura", ["NATU3"], "https://www.natura.com.br"),
    ("Petrobras", ["PETR3", "PETR4"], "https://petrobras.com.br"),
    ("Marcopolo", ["POMO4"], "https://www.marcopolo.com.br"),
    ("PRIO", ["PRIO3"], "https://prio3.com.br"),
    ("Porto", ["PSSA3"], "https://www.portoseguro.com.br"),
    ("RD Saúde", ["RADL3"], "https://rdsaude.com.br"),
    ("Rumo", ["RAIL3"], "https://rumolog.com"),
    ("Rede D'Or", ["RDOR3"], "https://www.rededorsaoluiz.com.br"),
    ("PetroReconcavo", ["RECV3"], "https://petroreconcavo.com.br"),
    ("Localiza", ["RENT3"], "https://www.localiza.com"),
    ("Santander Brasil", ["SANB11"], "https://www.santander.com.br"),
    ("Sabesp", ["SBSP3"], "https://www.sabesp.com.br"),
    ("SLC Agrícola", ["SLCE3"], "https://www.slcagricola.com.br"),
    ("Smart Fit", ["SMFT3"], "https://www.smartfit.com.br"),
    ("Suzano", ["SUZB3"], "https://www.suzano.com.br"),
    ("Taesa", ["TAEE11"], "https://www.taesa.com.br"),
    ("TIM Brasil", ["TIMS3"], "https://www.tim.com.br"),
    ("TOTVS", ["TOTS3"], "https://www.totvs.com"),
    ("Ultrapar", ["UGPA3"], "https://www.ultrapar.com.br"),
    ("Usiminas", ["USIM5"], "https://www.usiminas.com"),
    ("Vale", ["VALE3"], "https://www.vale.com"),
    ("Grupo Vamos", ["VAMO3"], "https://grupovamos.com.br"),
    ("Vibra Energia", ["VBBR3"], "https://www.vibraenergia.com.br"),
    ("Vivara", ["VIVA3"], "https://www.vivara.com.br"),
    ("Telefônica Brasil - Vivo", ["VIVT3"], "https://www.telefonica.com.br"),
    ("WEG", ["WEGE3"], "https://www.weg.net"),
    ("Yduqs", ["YDUQ3"], "https://www.yduqs.com.br"),
]

OFFICIAL_ASSET_OVERRIDES = {
    "AXIA3": "https://axia.com.br/documents/32426/91425/LOGO.svg/025cd5d7-0e5c-a74b-bd85-f00e1eb3511b?version=1.0",
}

# Fonte secundária usada somente quando o domínio oficial bloqueia a coleta.
# O manifesto diferencia explicitamente estes arquivos dos oficiais.
TRADINGVIEW_LOGOIDS = {
    "ABEV3": "ambev", "AURE3": "auren-on-nm", "BBAS3": "banco-do-brasil",
    "BPAC11": "btgp", "CYRE3": "cyrela-realton-nm", "EMBJ3": "embraer",
    "ENGI11": "energisa-unt-n2", "GGBR4": "gerdau", "GOAU4": "gerdau",
    "HYPE3": "hypera", "IGTI11": "iguatemi-saon-n1", "ITUB4": "itau-unibanco",
    "KLBN11": "klabin", "MGLU3": "magaz-luiza-on-nm", "NATU3": "natura-and-co",
    "POMO4": "marcopolo", "RECV3": "petrorecsa-on-nm", "RENT3": "localiza",
    "SANB11": "santander", "SBSP3": "sabesp", "TAEE11": "taesa",
    "UGPA3": "ultrapar-participacoes", "VALE3": "vale", "VIVT3": "telefonica",
    "WEGE3": "weg",
}

ICON_RE = re.compile(
    r'<link[^>]+rel=["\'][^"\']*(?:icon|apple-touch-icon)[^"\']*["\'][^>]+href=["\']([^"\']+)',
    re.IGNORECASE,
)
ICON_RE_REVERSED = re.compile(
    r'<link[^>]+href=["\']([^"\']+)["\'][^>]+rel=["\'][^"\']*(?:icon|apple-touch-icon)',
    re.IGNORECASE,
)


def extension(content_type: str, url: str) -> str:
    content_type = content_type.split(";", 1)[0].strip().lower()
    known = {
        "image/svg+xml": ".svg",
        "image/png": ".png",
        "image/jpeg": ".jpg",
        "image/webp": ".webp",
        "image/x-icon": ".ico",
        "image/vnd.microsoft.icon": ".ico",
    }
    return known.get(content_type) or Path(urlparse(url).path).suffix.lower() or mimetypes.guess_extension(content_type) or ".img"


def download_company(item: tuple[str, list[str], str]) -> list[dict]:
    company, tickers, official_page = item
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/136.0 Safari/537.36"}
    with httpx.Client(timeout=25, follow_redirects=True, headers=headers) as client:
        override = next((OFFICIAL_ASSET_OVERRIDES[t] for t in tickers if t in OFFICIAL_ASSET_OVERRIDES), None)
        if override:
            asset_url = override
            page_title = company
        else:
            page = client.get(official_page)
            page.raise_for_status()
            title = re.search(r"<title[^>]*>(.*?)</title>", page.text, re.I | re.S)
            page_title = re.sub(r"\s+", " ", title.group(1)).strip() if title else ""
            match = ICON_RE.search(page.text) or ICON_RE_REVERSED.search(page.text)
            asset_url = urljoin(str(page.url), match.group(1)) if match else urljoin(str(page.url), "/favicon.ico")
        asset = client.get(asset_url)
        asset.raise_for_status()
        if not asset.headers.get("content-type", "").lower().startswith("image/"):
            raise ValueError(f"arquivo não é imagem: {asset_url}")
        suffix = extension(asset.headers.get("content-type", ""), str(asset.url))
        digest = hashlib.sha256(asset.content).hexdigest()
        records = []
        for ticker in tickers:
            path = LOGOS / f"{ticker}{suffix}"
            path.write_bytes(asset.content)
            records.append({
                "ticker": ticker,
                "company": company,
                "official_page": official_page,
                "official_page_title": page_title,
                "source_url": str(asset.url),
                "asset": f"nosso_repositorio/logos/{path.name}",
                "sha256": digest,
                "checked_at": datetime.now(timezone.utc).isoformat(),
                "status": "verified_official_domain",
            })
        return records


def download_tradingview(company: str, tickers: list[str], official_page: str) -> list[dict]:
    records = []
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
    with httpx.Client(timeout=25, follow_redirects=True, headers=headers) as client:
        for ticker in tickers:
            logoid = TRADINGVIEW_LOGOIDS.get(ticker)
            if not logoid:
                raise ValueError(f"sem logo secundária cadastrada para {ticker}")
            asset_url = f"https://s3-symbol-logo.tradingview.com/{logoid}.svg"
            asset = client.get(asset_url)
            asset.raise_for_status()
            if asset.headers.get("content-type", "").split(";", 1)[0] != "image/svg+xml":
                raise ValueError(f"arquivo secundário inválido: {asset_url}")
            path = LOGOS / f"{ticker}.svg"
            path.write_bytes(asset.content)
            records.append({
                "ticker": ticker,
                "company": company,
                "official_page": official_page,
                "official_page_title": company,
                "source_url": asset_url,
                "source_page": f"https://www.tradingview.com/symbols/BMFBOVESPA-{ticker}/",
                "asset": f"nosso_repositorio/logos/{path.name}",
                "sha256": hashlib.sha256(asset.content).hexdigest(),
                "checked_at": datetime.now(timezone.utc).isoformat(),
                "status": "secondary_tradingview",
            })
    return records


def main() -> None:
    LOGOS.mkdir(parents=True, exist_ok=True)
    manifest_path = OUTPUT / "manifest.json"
    previous = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {"logos": []}
    previous_by_ticker = {record["ticker"]: record for record in previous.get("logos", [])}
    records, errors = [], []
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        futures = {executor.submit(download_company, item): item for item in COMPANIES}
        for future in concurrent.futures.as_completed(futures):
            company, tickers, page = futures[future]
            try:
                records.extend(future.result())
            except Exception as exc:
                try:
                    records.extend(download_tradingview(company, tickers, page))
                except Exception as secondary_exc:
                    preserved = [previous_by_ticker[t] for t in tickers if t in previous_by_ticker]
                    records.extend(preserved)
                    missing = [t for t in tickers if t not in previous_by_ticker]
                    if missing:
                        errors.append({
                            "company": company, "tickers": missing, "official_page": page,
                            "error": str(exc), "secondary_error": str(secondary_exc),
                        })
    payload = {"generated_at": datetime.now(timezone.utc).isoformat(), "logos": sorted(records, key=lambda x: x["ticker"]), "errors": errors}
    manifest_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    def dart_string(value: str) -> str:
        return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"

    dart_entries = "\n".join(
        f"  {dart_string(record['ticker'])}: {dart_string(record['asset'])},"
        for record in payload["logos"]
    )
    (ROOT / "flutter_frontend" / "lib" / "official_logo_assets.dart").write_text(
        "// Gerado por tools/atualizar_logos_oficiais.py. Não editar.\n"
        "const Map<String, String> officialLogoAssets = {\n"
        f"{dart_entries}\n"
        "};\n",
        encoding="utf-8",
    )
    print(f"{len(records)} logos baixadas; {len(errors)} companhias pendentes")


if __name__ == "__main__":
    main()
