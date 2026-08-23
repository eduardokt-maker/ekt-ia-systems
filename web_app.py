import asyncio
import base64
import binascii
import hashlib
import hmac
import json
import logging
import os
import re
import secrets
import sqlite3
import threading
import time
from contextlib import contextmanager
from datetime import datetime
from zoneinfo import ZoneInfo
from decimal import Decimal, InvalidOperation
from urllib.parse import parse_qs

import flet as ft
import capital_flow_b3
import capital_flow_store
import bank_directory
import bank_statement_lab
import bank_santander_store
import statement_structure
import statement_outflows
import day_trade_store
import jex_news
import main as main_module
import monitor_global
from motor_analise import analysis_service


IBOV_MARKET_CACHE_TTL_SECONDS = 60
_IBOV_MARKET_CACHE: tuple[float, dict] | None = None
_IBOV_MARKET_CACHE_LOCK = threading.Lock()
_IBOV_MARKET_REFRESH_LOCK = threading.Lock()
_SANTANDER_IMPORT_LOCK = threading.Lock()
_SANTANDER_IMPORTS_RUNNING: set[str] = set()


def _santander_files_pending(owner_key: str) -> list[dict]:
    pending = []
    for stored in bank_statement_lab.list_test_files(owner_key):
        bank_text = f"{stored.get('bank_code') or ''} {stored.get('bank_name') or ''}".casefold()
        if "033" not in bank_text and "santander" not in bank_text:
            continue
        if not bank_santander_store.source_file_imported(owner_key, int(stored["id"])):
            pending.append(stored)
    return pending


def _import_santander_files(owner_key: str, pending: list[dict]) -> None:
    try:
        for stored in pending:
            item = bank_statement_lab.get_test_file(owner_key, int(stored["id"]))
            if item is None or not str(item["filename"]).lower().endswith(".pdf"):
                continue
            bank_santander_store.import_santander_file(
                owner_key, int(stored["id"]), item["filename"], item["content"]
            )
    except Exception:
        LOGGER.exception("Falha ao importar extratos Santander em segundo plano")
    finally:
        with _SANTANDER_IMPORT_LOCK:
            _SANTANDER_IMPORTS_RUNNING.discard(owner_key)


def _schedule_santander_import(owner_key: str) -> bool:
    pending = _santander_files_pending(owner_key)
    if not pending:
        return False
    with _SANTANDER_IMPORT_LOCK:
        if owner_key in _SANTANDER_IMPORTS_RUNNING:
            return True
        _SANTANDER_IMPORTS_RUNNING.add(owner_key)
    threading.Thread(
        target=_import_santander_files,
        args=(owner_key, pending),
        name=f"santander-import-{owner_key[:24]}",
        daemon=True,
    ).start()
    return True


@contextmanager
def _banking_reset_connection():
    if main_module.use_postgres_investment_db():
        with main_module.investment_db_connection() as connection:
            yield connection
        return
    main_module.INVESTMENT_DATA_DIR.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(main_module.INVESTMENT_DB_PATH)
    try:
        with connection:
            yield connection
    finally:
        connection.close()


def _reset_legacy_banking_module_once() -> None:
    """Permanently remove the retired banking module and its stored data once."""
    reset_key = "banking_module_zero_20260823"
    with _banking_reset_connection() as connection:
        connection.execute(
            "CREATE TABLE IF NOT EXISTS ekt_data_resets "
            "(reset_key TEXT PRIMARY KEY, completed_at TEXT NOT NULL)"
        )
        placeholder = "%s" if main_module.use_postgres_investment_db() else "?"
        if connection.execute(
            f"SELECT 1 FROM ekt_data_resets WHERE reset_key={placeholder}",
            (reset_key,),
        ).fetchone():
            return
        for table in (
            "bank_transactions",
            "bank_cards",
            "bank_categories",
            "bank_import_batches",
            "bank_accounts",
        ):
            suffix = " CASCADE" if main_module.use_postgres_investment_db() else ""
            connection.execute(f"DROP TABLE IF EXISTS {table}{suffix}")
        connection.execute(
            f"INSERT INTO ekt_data_resets(reset_key,completed_at) VALUES({placeholder},{placeholder})",
            (reset_key, datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat()),
        )


def apply_investments_menu_patch() -> None:
    responsive_item = main_module.responsive_item

    def investments_menu_view(on_back, on_my_investments, on_monthly_budget, on_day_trade) -> ft.Control:
        def menu_card(
            title: str,
            description: str,
            icon,
            on_click,
            accent: str,
            badge: str,
            primary: bool = False,
        ) -> ft.Control:
            return responsive_item(
                ft.Container(
                    height=178,
                    bgcolor="#FFFFFF",
                    border=ft.Border(
                        top=ft.BorderSide(3, accent),
                        right=ft.BorderSide(1, "#D8DEE6"),
                        bottom=ft.BorderSide(1, "#D8DEE6"),
                        left=ft.BorderSide(1, "#D8DEE6"),
                    ),
                    border_radius=10,
                    padding=ft.Padding(left=15, top=14, right=15, bottom=14),
                    on_click=on_click,
                    ink=True,
                    shadow=ft.BoxShadow(
                        blur_radius=14,
                        spread_radius=0,
                        color="#12000000",
                        offset=ft.Offset(0, 6),
                    ),
                    content=ft.Column(
                        [
                            ft.Row(
                                [
                                    ft.Container(
                                        width=42,
                                        height=42,
                                        border_radius=10,
                                        bgcolor="#FFF3DF" if primary else "#EEF3F8",
                                        alignment=ft.Alignment(0, 0),
                                        content=ft.Icon(icon, size=22, color=accent),
                                    ),
                                    ft.Container(
                                        bgcolor="#F5F7FA",
                                        border_radius=8,
                                        padding=ft.Padding(left=8, top=3, right=8, bottom=3),
                                        content=ft.Text(
                                            badge,
                                            size=8,
                                            color="#5F6873",
                                            weight=ft.FontWeight.BOLD,
                                        ),
                                    ),
                                ],
                                alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                                vertical_alignment=ft.CrossAxisAlignment.CENTER,
                            ),
                            ft.Column(
                                [
                                    ft.Text(title, size=16, weight=ft.FontWeight.BOLD, color="#20242B"),
                                    ft.Text(
                                        description,
                                        size=11,
                                        color="#5F6873",
                                        max_lines=3,
                                        overflow=ft.TextOverflow.ELLIPSIS,
                                    ),
                                ],
                                spacing=5,
                                expand=True,
                            ),
                            ft.Row(
                                [
                                    ft.Text("Abrir", size=12, weight=ft.FontWeight.BOLD, color=accent),
                                    ft.Icon(ft.Icons.ARROW_FORWARD, size=16, color=accent),
                                ],
                                spacing=4,
                                vertical_alignment=ft.CrossAxisAlignment.CENTER,
                            ),
                        ],
                        spacing=12,
                    ),
                ),
                xs=12,
                sm=12,
                md=4,
                lg=4,
            )

        return ft.Container(
            expand=True,
            bgcolor="#F3F6F9",
            padding=ft.Padding(left=16, top=14, right=16, bottom=20),
            content=ft.Column(
                [
                    ft.Row(
                        [
                            ft.IconButton(
                                icon=ft.Icons.ARROW_BACK,
                                tooltip="Voltar ao inicio",
                                icon_color="#12304A",
                                bgcolor="#E8EEF5",
                                on_click=lambda _event: on_back(),
                            ),
                            ft.Column(
                                [
                                    ft.Text(
                                        "Controle de investimentos",
                                        size=22,
                                        weight=ft.FontWeight.BOLD,
                                        color="#16202A",
                                    ),
                                    ft.Text(
                                        "Area logada | Painel de gestao financeira",
                                        size=12,
                                        color="#5F6873",
                                    ),
                                ],
                                spacing=1,
                            ),
                        ],
                        spacing=10,
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                    ft.Container(
                        bgcolor="#0F2235",
                        border=ft.Border(
                            top=ft.BorderSide(1, "#22384E"),
                            right=ft.BorderSide(1, "#22384E"),
                            bottom=ft.BorderSide(1, "#22384E"),
                            left=ft.BorderSide(1, "#22384E"),
                        ),
                        border_radius=12,
                        padding=ft.Padding(left=18, top=18, right=18, bottom=18),
                        shadow=ft.BoxShadow(
                            blur_radius=18,
                            spread_radius=0,
                            color="#18000000",
                            offset=ft.Offset(0, 8),
                        ),
                        content=ft.Column(
                            [
                                ft.Row(
                                    [
                                        ft.Column(
                                            [
                                                ft.Text(
                                                    "Painel logado",
                                                    size=12,
                                                    color="#A8B4C0",
                                                    weight=ft.FontWeight.BOLD,
                                                ),
                                                ft.Text(
                                                    "Escolha uma area para continuar",
                                                    size=20,
                                                    weight=ft.FontWeight.BOLD,
                                                    color="#FFFFFF",
                                                ),
                                            ],
                                            spacing=2,
                                            expand=True,
                                        ),
                                        ft.Container(
                                            bgcolor="#173552",
                                            border_radius=10,
                                            padding=ft.Padding(left=10, top=6, right=10, bottom=6),
                                            content=ft.Row(
                                                [
                                                    ft.Icon(ft.Icons.LOCK_OPEN, size=16, color="#8ED4FF"),
                                                    ft.Text(
                                                        "Sessao autorizada",
                                                        size=11,
                                                        color="#DCEAF5",
                                                        weight=ft.FontWeight.BOLD,
                                                    ),
                                                ],
                                                spacing=6,
                                                vertical_alignment=ft.CrossAxisAlignment.CENTER,
                                            ),
                                        ),
                                    ],
                                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                                ),
                                ft.Container(
                                    bgcolor="#F6F8FB",
                                    border_radius=12,
                                    padding=ft.Padding(left=12, top=12, right=12, bottom=12),
                                    content=ft.ResponsiveRow(
                                        [
                                            menu_card(
                                                "Meus investimentos",
                                                "Cadastre e acompanhe seus ativos, produtos e posicoes salvas.",
                                                ft.Icons.ACCOUNT_BALANCE_WALLET,
                                                on_my_investments,
                                                "#1F4E79",
                                                "CARTEIRA",
                                            ),
                                            menu_card(
                                                "Meu orcamento",
                                                "Controle receitas, despesas, vencimentos e saldo mensal previsto.",
                                                ft.Icons.ACCOUNT_BALANCE,
                                                on_monthly_budget,
                                                "#C76A00",
                                                "MENSAL",
                                                primary=True,
                                            ),
                                            menu_card(
                                                "Operacoes day trade",
                                                "Acesse a area operacional para registrar e acompanhar operacoes.",
                                                ft.Icons.SHOW_CHART,
                                                on_day_trade,
                                                "#167A4B",
                                                "TRADER",
                                            ),
                                        ],
                                        spacing=12,
                                        run_spacing=12,
                                    ),
                                ),
                            ],
                            spacing=16,
                        ),
                    ),
                ],
                spacing=16,
                scroll=ft.ScrollMode.AUTO,
            ),
        )

    main_module.investments_menu_view = investments_menu_view


apply_investments_menu_patch()
main_module.APP_VERSION = "2026.07.14-investment-statement-v47"

APP_VERSION = main_module.APP_VERSION
budget_report_print_html = main_module.budget_report_print_html
investment_db_status = main_module.investment_db_status
main = main_module.main


JSON_HEADERS = [
    (b"content-type", b"application/json; charset=utf-8"),
    (b"cache-control", b"no-store"),
    (b"access-control-allow-origin", b"*"),
    (b"access-control-allow-methods", b"GET, POST, PUT, PATCH, DELETE, OPTIONS"),
    (b"access-control-allow-headers", b"authorization, content-type"),
]

ACCESS_TOKEN_TTL_SECONDS = int(os.getenv("ACCESS_TOKEN_TTL_SECONDS", "900"))
REFRESH_TOKEN_TTL_SECONDS = int(
    os.getenv("REFRESH_TOKEN_TTL_SECONDS", str(30 * 24 * 60 * 60))
)
# Kept as an alias for callers and older tests.
BUDGET_API_SESSION_TTL_SECONDS = ACCESS_TOKEN_TTL_SECONDS
LOGGER = logging.getLogger("ekt.api")


def _budget_session_secret() -> bytes:
    secret = os.getenv("BUDGET_SESSION_SECRET", "").strip() or os.getenv(
        "INVESTMENTS_PASSWORD", ""
    )
    if not secret:
        raise RuntimeError("Segredo de sessão não configurado.")
    return secret.encode("utf-8")


def _urlsafe_encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def _urlsafe_decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def _create_session_token(token_type: str, ttl_seconds: int, user: str = "") -> str:
    payload = {
        "exp": int(time.time()) + ttl_seconds,
        "iat": int(time.time()),
        "nonce": secrets.token_urlsafe(12),
        "type": token_type,
        "user": user,
    }
    encoded = _urlsafe_encode(
        json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    )
    signature = hmac.new(
        _budget_session_secret(), encoded.encode("ascii"), hashlib.sha256
    ).digest()
    return f"{encoded}.{_urlsafe_encode(signature)}"


def create_budget_api_session(user: str = "") -> str:
    return _create_session_token("access", ACCESS_TOKEN_TTL_SECONDS, user)


def create_budget_refresh_token(user: str = "") -> str:
    return _create_session_token("refresh", REFRESH_TOKEN_TTL_SECONDS, user)


def _session_claims_from_token(token: str, expected_type: str) -> dict | None:
    try:
        encoded, supplied_signature = token.split(".", 1)
        expected_signature = hmac.new(
            _budget_session_secret(), encoded.encode("ascii"), hashlib.sha256
        ).digest()
        if not hmac.compare_digest(
            _urlsafe_decode(supplied_signature), expected_signature
        ):
            return None
        payload = json.loads(_urlsafe_decode(encoded))
        if payload.get("type", "access") != expected_type:
            return None
        if int(payload["exp"]) <= int(time.time()):
            return None
        return payload
    except (
        binascii.Error,
        json.JSONDecodeError,
        KeyError,
        TypeError,
        UnicodeDecodeError,
        ValueError,
    ):
        return None


def _bearer_token(scope) -> str:
    headers = {key.lower(): value for key, value in scope.get("headers", [])}
    authorization = headers.get(b"authorization", b"").decode("utf-8", errors="ignore")
    if not authorization.startswith("Bearer "):
        return ""
    return authorization.removeprefix("Bearer ").strip()


def has_valid_budget_api_session(scope) -> bool:
    return _session_claims_from_token(_bearer_token(scope), "access") is not None


def authenticated_owner_key(scope) -> str | None:
    claims = _session_claims_from_token(_bearer_token(scope), "access")
    if claims is None:
        return None
    return str(claims.get("user") or main_module.DEFAULT_BUDGET_OWNER_KEY)[:120]


def normalize_budget_amount(value: object) -> str:
    cleaned = str(value or "").strip().replace("R$", "").replace(" ", "")
    if "," in cleaned:
        cleaned = cleaned.replace(".", "").replace(",", ".")
    try:
        amount = Decimal(cleaned)
    except InvalidOperation as exc:
        raise ValueError("Informe um valor valido.") from exc
    if amount <= 0:
        raise ValueError("Informe um valor maior que zero.")
    formatted = f"{amount.quantize(Decimal('0.01')):,.2f}"
    return formatted.replace(",", "X").replace(".", ",").replace("X", ".")


def normalize_optional_budget_amount(value: object) -> tuple[str, Decimal]:
    cleaned = str(value or "").strip().replace("R$", "").replace(" ", "") or "0"
    if "," in cleaned:
        cleaned = cleaned.replace(".", "").replace(",", ".")
    try:
        amount = Decimal(cleaned)
    except InvalidOperation as exc:
        raise ValueError("Informe um valor recebido valido.") from exc
    if amount < 0:
        raise ValueError("O valor recebido nao pode ser negativo.")
    amount = amount.quantize(Decimal("0.01"))
    formatted = f"{amount:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return formatted, amount


def normalize_budget_date(value: object, *, required: bool) -> str | None:
    text = str(value or "").strip()
    if not text and not required:
        return None
    try:
        return datetime.strptime(text, "%Y-%m-%d").strftime("%Y-%m-%d")
    except ValueError as exc:
        raise ValueError("Informe uma data valida.") from exc


def validated_budget_payload(payload: dict) -> dict:
    item_type = str(payload.get("item_type", "")).strip()
    if item_type not in {"Receita", "Despesa"}:
        raise ValueError("Selecione receita ou despesa.")
    reference_month = str(payload.get("reference_month", "")).strip()
    reference_match = re.fullmatch(
        r"(\d{4})-(0[1-9]|1[0-2])", reference_month
    )
    if reference_match is None or not 2000 <= int(reference_match.group(1)) <= 2100:
        if item_type == "Despesa":
            raise ValueError("Informe o mês de referência da despesa.")
        raise ValueError("Escolha um mês de referência válido.")
    tipo_receita = None
    tipo_receita_outros = None
    expense_nature_id = None
    if item_type == "Receita":
        raw_tipo_receita = payload.get("tipo_receita")
        if raw_tipo_receita is None or not str(raw_tipo_receita).strip():
            raise ValueError("Selecione o tipo de receita.")
        tipo_receita = str(raw_tipo_receita).strip().upper()
        if tipo_receita not in {"ALUGUEL", "DAY_TRADE", "OUTROS"}:
            raise ValueError("Tipo de receita inválido.")
        if tipo_receita == "OUTROS":
            tipo_receita_outros = str(
                payload.get("tipo_receita_outros", "")
            ).strip()
            if not tipo_receita_outros:
                raise ValueError("Especifique o tipo de receita.")
            if len(tipo_receita_outros) > 80:
                raise ValueError(
                    "O tipo de receita deve possuir no máximo 80 caracteres."
                )
    else:
        active_natures = [item for item in main_module.list_expense_natures() if item["active"]]
        raw_nature_id = payload.get("expense_nature_id")
        if active_natures and raw_nature_id in (None, ""):
            raise ValueError("Informe a natureza da despesa.")
        if raw_nature_id not in (None, ""):
            try:
                expense_nature_id = int(raw_nature_id)
            except (TypeError, ValueError) as exc:
                raise ValueError("Informe a natureza da despesa.") from exc
            if not any(item["id"] == expense_nature_id and item["active"] for item in active_natures):
                raise ValueError("Selecione uma natureza ativa.")
    description = str(payload.get("description", "")).strip().upper()[:15]
    if not description:
        raise ValueError("Informe a descricao.")
    observation = str(payload.get("observation", ""))
    if len(observation) > 500:
        raise ValueError("A observacao deve possuir no maximo 500 caracteres.")
    amount_text = normalize_budget_amount(payload.get("amount_text"))
    _, total_amount = normalize_optional_budget_amount(amount_text)
    received_amount_text, received_amount = normalize_optional_budget_amount(
        payload.get("received_amount_text") if item_type == "Receita" else 0
    )
    settled = bool(payload.get("settled", False))
    if item_type == "Receita":
        if received_amount > total_amount:
            raise ValueError("O valor recebido nao pode superar o valor total.")
        if settled:
            received_amount = total_amount
            received_amount_text = amount_text
        settled = received_amount == total_amount
    payment_date = normalize_budget_date(payload.get("payment_date"), required=False)
    if (settled or received_amount > 0) and not payment_date:
        payment_date = datetime.now().strftime("%Y-%m-%d")
    if not settled and received_amount == 0:
        payment_date = None
    return {
        "reference_month": reference_month,
        "item_type": item_type,
        "tipo_receita": tipo_receita,
        "tipo_receita_outros": tipo_receita_outros,
        "expense_nature_id": expense_nature_id,
        "description": description,
        "observation": observation,
        "amount_text": amount_text,
        "received_amount_text": received_amount_text,
        "due_date": normalize_budget_date(payload.get("due_date"), required=True),
        "payment_date": payment_date,
        "settled": settled,
    }


def budget_payload(reference_month: str | None = None) -> dict:
    period_statuses = main_module.list_monthly_budget_period_statuses()
    return {
        "ok": True,
        "reference_month": reference_month,
        "month_status": period_statuses.get(reference_month or "", "open"),
        "month_statuses": period_statuses,
        "month_imports": main_module.list_monthly_budget_period_imports(),
        "items": main_module.load_monthly_budget_items(reference_month),
        "months": main_module.list_monthly_budget_months(),
        "expense_description_suggestions": main_module.list_budget_expense_descriptions(),
        "expense_natures": main_module.list_expense_natures(),
    }


def normalize_investment_amount(value: object) -> str:
    cleaned = str(value or "0").strip().replace("R$", "").replace(" ", "") or "0"
    if "," in cleaned:
        cleaned = cleaned.replace(".", "").replace(",", ".")
    try:
        amount = Decimal(cleaned)
    except InvalidOperation as exc:
        raise ValueError("Informe um valor aplicado valido.") from exc
    if amount < 0:
        raise ValueError("O valor aplicado nao pode ser negativo.")
    formatted = f"{amount.quantize(Decimal('0.01')):,.2f}"
    return formatted.replace(",", "X").replace(".", ",").replace("X", ".")


def validated_investment_payload(payload: dict) -> dict[str, str]:
    name = str(payload.get("name", "")).strip()[:120]
    if not name:
        raise ValueError("Informe o nome do investimento.")
    return {
        "name": name,
        "issuer": str(payload.get("issuer", "")).strip()[:120] or "Nao informado",
        "category": str(payload.get("category", "")).strip()[:80] or "Investimento",
        "indexer": str(payload.get("indexer", "")).strip()[:80] or "Nao informado",
        "maturity": str(payload.get("maturity", "")).strip()[:120] or "Nao informado",
        "source": str(payload.get("source", "")).strip()[:120] or "Cadastro manual",
    }


def investments_payload() -> dict:
    summary = day_trade_store.capital_summary()
    capital_text = summary["capital_text"]
    capital_value = day_trade_store.decimal_value(capital_text)
    if capital_value >= 0 and day_trade_store.decimal_value(
        summary["initial_capital_text"]
    ) > 0:
        main_module.save_day_trade_investment_amount(
            normalize_investment_amount(capital_text)
        )
    displayed_capital = f"{capital_value.quantize(Decimal('0.01')):,.2f}"
    displayed_capital = (
        displayed_capital.replace(",", "X").replace(".", ",").replace("X", ".")
    )
    items = main_module.load_saved_investment_records()
    for item in items:
        if (
            str(item["name"]) == main_module.DAY_TRADE_INVESTMENT_NAME
            and str(item["source"]) == "Controle Day Trade"
        ):
            item["amount_text"] = displayed_capital
            item["initial_capital_text"] = summary["initial_capital_text"]
            item["growth_amount_text"] = summary["growth_amount_text"]
            item["growth_percent"] = summary["growth_percent"]
            item["contributed_capital_text"] = summary[
                "contributed_capital_text"
            ]
            item["external_net_text"] = summary["external_net_text"]
            item["day_trade_result_text"] = summary["day_trade_result_text"]
            item["automatic_day_trade_result_text"] = summary[
                "automatic_day_trade_result_text"
            ]
            item["manual_day_trade_adjustment_text"] = summary[
                "manual_day_trade_adjustment_text"
            ]
            item["operational_return_percent"] = summary[
                "operational_return_percent"
            ]
            item["day_trade_share_global_percent"] = summary[
                "day_trade_share_global_percent"
            ]
    return {
        "ok": True,
        "items": items,
        "options": main_module.SANTANDER_FIXED_INCOME_OPTIONS,
    }


def investments_statement_payload() -> dict:
    portfolio = investments_payload()
    items = portfolio["items"]
    total = sum(
        (day_trade_store.decimal_value(item.get("amount_text", "0")) for item in items),
        Decimal("0"),
    )
    total_text = f"{total.quantize(Decimal('0.01')):,.2f}"
    total_text = total_text.replace(",", "X").replace(".", ",").replace("X", ".")
    return {
        "ok": True,
        "total_applied_text": total_text,
        "investments": [
            {
                "id": item["id"],
                "name": item["name"],
                "category": item["category"],
                "source": item["source"],
                "amount_text": item["amount_text"],
                "is_day_trade": (
                    str(item["name"]) == main_module.DAY_TRADE_INVESTMENT_NAME
                    and str(item["source"]) == "Controle Day Trade"
                ),
            }
            for item in items
        ],
        "day_trade": day_trade_store.capital_statement(),
    }


def investments_dashboard_payload() -> dict:
    return {
        "title": "Controle de investimentos",
        "subtitle": "Area logada | Painel de gestao financeira",
        "status": "Sessao autorizada",
        "actions": [
            {
                "id": "banking",
                "title": "Controle bancário e cartões",
                "description": "Contas, cartões, entradas, despesas e movimentações em uma visão segura.",
                "badge": "BANCOS",
                "accent": "#0F766E",
            },
            {
                "id": "investments",
                "title": "Meus investimentos",
                "description": "Cadastre e acompanhe seus ativos, produtos e posicoes salvas.",
                "badge": "CARTEIRA",
                "accent": "#1F4E79",
            },
            {
                "id": "budget",
                "title": "Meu orcamento",
                "description": "Controle receitas, despesas, vencimentos e saldo mensal previsto.",
                "badge": "MENSAL",
                "accent": "#C76A00",
            },
            {
                "id": "day_trade",
                "title": "Operacoes day trade",
                "description": "Acesse a area operacional para registrar e acompanhar operacoes.",
                "badge": "TRADER",
                "accent": "#167A4B",
            },
        ],
    }


def normalize_positive_trade_value(value: object, label: str, *, allow_zero: bool = False) -> str:
    amount = day_trade_store.decimal_value(value)
    if amount < 0 or (not allow_zero and amount == 0):
        comparison = "zero ou maior" if allow_zero else "maior que zero"
        raise ValueError(f"{label} deve ser {comparison}.")
    return day_trade_store.decimal_text(amount)


def normalize_trade_date(value: object) -> str:
    text = str(value or "").strip()
    try:
        return datetime.strptime(text, "%Y-%m-%d").strftime("%Y-%m-%d")
    except ValueError as exc:
        raise ValueError("Informe uma data de operacao valida.") from exc


def normalize_trade_time(value: object, label: str) -> str:
    text = str(value or "").strip()
    try:
        return datetime.strptime(text, "%H:%M").strftime("%H:%M")
    except ValueError as exc:
        raise ValueError(f"Informe um {label} valido.") from exc


def trade_weekday(trade_date: str) -> str:
    names = (
        "segunda-feira",
        "terça-feira",
        "quarta-feira",
        "quinta-feira",
        "sexta-feira",
        "sábado",
        "domingo",
    )
    return names[datetime.strptime(trade_date, "%Y-%m-%d").weekday()]


def validated_day_trade_payload(payload: dict) -> dict:
    asset = str(payload.get("asset", "")).strip().upper()[:20]
    if not asset:
        raise ValueError("Informe o ativo.")
    market = str(payload.get("market", "")).strip()[:40]
    if not market:
        raise ValueError("Selecione o mercado.")
    direction = str(payload.get("direction", "")).strip()
    if direction not in {"Compra", "Venda"}:
        raise ValueError("Selecione compra ou venda.")
    try:
        quantity = int(payload.get("quantity", 0))
    except (TypeError, ValueError) as exc:
        raise ValueError("Informe uma quantidade valida.") from exc
    if quantity <= 0 or quantity > 1000000:
        raise ValueError("A quantidade deve ser maior que zero.")
    operation_result = str(payload.get("operation_result", "")).strip()
    if operation_result not in {"stop loss", "Gain", "BREAK_EVEN"}:
        raise ValueError("Marque Gain, Stop loss ou Break Even.")
    is_break_even = operation_result == "BREAK_EVEN"
    if is_break_even:
        for field in ("points_result", "gross_result", "operational_result"):
            if field in payload and day_trade_store.decimal_value(payload.get(field)) != 0:
                raise ValueError("Break Even deve possuir resultado operacional igual a zero.")
    entry_text = str(payload.get("entry_price_text") or "").strip()
    entry_price = day_trade_store.decimal_value(entry_text) if entry_text else Decimal("0")
    if entry_text and entry_price <= 0:
        raise ValueError("O preco de entrada deve ser maior que zero quando informado.")
    stop_price = day_trade_store.decimal_value(payload.get("stop_price_text"))
    target_price = day_trade_store.decimal_value(payload.get("target_price_text"))
    if day_trade_store.is_mini_dollar(asset, market):
        point_value = day_trade_store.WDO_POINT_VALUE
    elif market == "Mini índice":
        point_value = Decimal("0.20")
    else:
        point_value = day_trade_store.decimal_value(payload.get("point_value_text", "1"))
    if not is_break_even and min(entry_price, stop_price, target_price) <= 0:
        raise ValueError("Entrada, stop e alvo devem ser maiores que zero.")
    if not is_break_even and direction == "Compra" and not (stop_price < entry_price < target_price):
        raise ValueError("Na compra, o stop deve ficar abaixo da entrada e o alvo acima.")
    if not is_break_even and direction == "Venda" and not (target_price < entry_price < stop_price):
        raise ValueError("Na venda, o alvo deve ficar abaixo da entrada e o stop acima.")
    strategy = str(payload.get("strategy", "")).strip()[:80]
    if not strategy:
        raise ValueError("Informe a estrategia utilizada.")
    normalized_date = normalize_trade_date(payload.get("trade_date"))
    entry_time = normalize_trade_time(payload.get("entry_time"), "horario de entrada")
    exit_time = normalize_trade_time(
        payload.get("exit_time") or entry_time, "horario de saida"
    )
    return {
        "trade_date": normalized_date,
        "trade_weekday": trade_weekday(normalized_date),
        "entry_time": entry_time,
        "exit_time": exit_time,
        "asset": asset,
        "market": market,
        "direction": direction,
        "quantity": quantity,
        "entry_price_text": day_trade_store.decimal_text(entry_price) if entry_text else "",
        "point_value_text": normalize_positive_trade_value(point_value, "Valor por ponto"),
        "stop_price_text": "" if is_break_even else day_trade_store.decimal_text(stop_price),
        "target_price_text": "" if is_break_even else day_trade_store.decimal_text(target_price),
        "costs_text": normalize_positive_trade_value(
            payload.get("costs_text", "0"), "Custos", allow_zero=True
        ),
        "strategy": strategy,
        "operation_result": operation_result,
        "notes": str(payload.get("notes", "")).strip()[:500],
    }


def validated_day_trade_close_payload(payload: dict) -> dict:
    reason = str(payload.get("exit_reason", "")).strip()[:80]
    if not reason:
        raise ValueError("Informe o motivo da saida.")
    return {
        "exit_price_text": normalize_positive_trade_value(
            payload.get("exit_price_text"), "Preco de saida"
        ),
        "exit_time": normalize_trade_time(payload.get("exit_time"), "horario de saida"),
        "costs_text": normalize_positive_trade_value(
            payload.get("costs_text", "0"), "Custos", allow_zero=True
        ),
        "exit_reason": reason,
    }


def validated_day_trade_settings(payload: dict) -> dict:
    try:
        max_operations = int(payload.get("max_operations", 0))
    except (TypeError, ValueError) as exc:
        raise ValueError("Informe um limite de operacoes valido.") from exc
    if max_operations < 1 or max_operations > 100:
        raise ValueError("O limite diario deve ficar entre 1 e 100 operacoes.")
    return {
        "capital_text": normalize_positive_trade_value(payload.get("capital_text"), "Capital"),
        "daily_loss_limit_text": normalize_positive_trade_value(
            payload.get("daily_loss_limit_text"), "Limite de perda diaria"
        ),
        "daily_target_text": normalize_positive_trade_value(
            payload.get("daily_target_text"), "Meta diaria"
        ),
        "max_operations": max_operations,
        "risk_per_trade_text": normalize_positive_trade_value(
            payload.get("risk_per_trade_text"), "Risco por operacao"
        ),
    }


async def read_json_body(receive) -> dict:
    body = b""
    more_body = True
    while more_body:
        message = await receive()
        body += message.get("body", b"")
        more_body = message.get("more_body", False)
    if not body:
        return {}
    try:
        return json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return {}


async def send_json(send, payload: dict, status: int = 200) -> None:
    await send(
        {
            "type": "http.response.start",
            "status": status,
            "headers": JSON_HEADERS,
        }
    )
    await send({"type": "http.response.body", "body": json.dumps(payload, ensure_ascii=True).encode("utf-8")})


def market_quote_payload(quote, portfolio: dict | None = None) -> dict:
    portfolio = portfolio or {}
    is_stale = main_module.is_brazil_quote_stale(quote.market_time)
    market_state = (
        "STALE"
        if is_stale
        else "REGULAR"
        if main_module.is_brazil_market_open()
        else "CLOSED"
    )
    return {
        "symbol": quote.symbol,
        "name": str(portfolio.get("asset") or quote.name or quote.symbol),
        "price": quote.price,
        "change": quote.change,
        "change_percent": quote.change_percent,
        "volume": quote.volume,
        "market_time": quote.market_time,
        "logo_url": quote.logo_url,
        "market_state": market_state,
        "is_stale": is_stale,
        "currency": quote.currency or "BRL",
        "weight": portfolio.get("weight"),
        "sector": main_module.IBOV_SECTOR_BY_SYMBOL.get(quote.symbol, "Outros"),
        "day_open": quote.day_open,
        "day_high": quote.day_high,
        "day_low": quote.day_low,
        "market_cap": quote.market_cap,
        "financial_volume": (
            quote.price * quote.volume
            if quote.price is not None and quote.volume is not None
            else None
        ),
        "intraday_prices": quote.intraday_prices or [],
    }


def _fetch_ibovespa_market_payload() -> dict:
    portfolio = main_module.fetch_ibovespa_portfolio()
    tickers = ",".join(portfolio) if portfolio else main_module.IBOVESPA_FALLBACK_TICKERS
    quotes = []
    _count, source = main_module.stream_brazil_market_quotes(
        tickers,
        lambda quote: quotes.append(market_quote_payload(quote, portfolio.get(quote.symbol))),
    )
    try:
        index = market_quote_payload(main_module.fetch_ibov_dashboard_quote())
    except Exception:
        index = None
    return {
        "ok": True,
        "source": source,
        "fetched_at": datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(),
        "index": index,
        "quotes": quotes,
    }


def _store_ibovespa_market_cache(payload: dict) -> dict:
    global _IBOV_MARKET_CACHE
    with _IBOV_MARKET_CACHE_LOCK:
        _IBOV_MARKET_CACHE = (time.monotonic(), payload)
    return payload


def _refresh_ibovespa_market_cache() -> None:
    if not _IBOV_MARKET_REFRESH_LOCK.acquire(blocking=False):
        return
    try:
        _store_ibovespa_market_cache(_fetch_ibovespa_market_payload())
    except Exception:
        # A última resposta válida continua disponível se uma fonte externa falhar.
        return
    finally:
        _IBOV_MARKET_REFRESH_LOCK.release()


def _schedule_ibovespa_market_refresh() -> None:
    threading.Thread(
        target=_refresh_ibovespa_market_cache,
        name="ibovespa-market-refresh",
        daemon=True,
    ).start()


def ibovespa_market_payload() -> dict:
    with _IBOV_MARKET_CACHE_LOCK:
        cached = _IBOV_MARKET_CACHE
    if cached is not None:
        cached_at, payload = cached
        age = max(0.0, time.monotonic() - cached_at)
        if age > IBOV_MARKET_CACHE_TTL_SECONDS:
            _schedule_ibovespa_market_refresh()
        cache_stale = age > max(IBOV_MARKET_CACHE_TTL_SECONDS * 3, 180)
        market_open = main_module.is_brazil_market_open()
        quotes = []
        for quote in payload.get("quotes") or []:
            quote_stale = market_open and (cache_stale or quote.get("is_stale") is True)
            quotes.append({
                **quote,
                "is_stale": quote_stale,
                "market_state": (
                    "STALE" if quote_stale else "REGULAR" if market_open else "CLOSED"
                ),
            })
        return {
            **payload,
            "quotes": quotes,
            "cache_age_seconds": round(age, 1),
            "cache_stale": cache_stale,
        }

    # Apenas a primeira requisição de um processo aguarda as fontes externas.
    # As demais compartilham o resultado e as atualizações passam a ser assíncronas.
    with _IBOV_MARKET_REFRESH_LOCK:
        with _IBOV_MARKET_CACHE_LOCK:
            cached = _IBOV_MARKET_CACHE
        if cached is not None:
            return {**cached[1], "cache_age_seconds": 0.0, "cache_stale": False}
        return {
            **_store_ibovespa_market_cache(_fetch_ibovespa_market_payload()),
            "cache_age_seconds": 0.0,
            "cache_stale": False,
        }


def ibovespa_analysis_payload(symbol: str) -> dict:
    normalized = re.sub(r"[^A-Z0-9]", "", symbol.upper())
    if not normalized:
        raise ValueError("Ativo invalido.")
    quote_holder = []
    main_module.stream_brazil_market_quotes(normalized, quote_holder.append)
    if not quote_holder:
        raise ValueError("Ativo nao encontrado.")
    quote = quote_holder[0]
    candles = main_module.fetch_yahoo_candles_cached(
        main_module.yahoo_symbol_for_search(normalized, quote), interval="1wk", range_="5y"
    )
    return {
        "ok": True,
        "quote": market_quote_payload(quote),
        "interval": "1wk",
        "range": "5y",
        "source": "Yahoo Finance",
        "candles": [
            {"time": item.time_label, "open": item.open, "high": item.high, "low": item.low, "close": item.close}
            for item in candles
        ],
    }


def jex_payload() -> dict:
    return {
        "ok": True,
        "company": {
            "name": "JEX Nederland B.V.", "legal_type": "Besloten vennootschap (B.V.)",
            "kvk": "85002976", "establishment": "000051083825",
            "headquarters": "Rotterdam, Paises Baixos", "address": "Nassaukade 5, 3071 JL Rotterdam",
            "activity": "Software, recrutamento, backoffice e solucoes de vendas com IA.",
            "market_status": "Empresa privada. Sem ticker publico."
        },
        "timeline": [
            {"year": "2020", "title": "Origem da marca", "description": "Fundacao com foco inicial no mercado de trabalho neerlandes."},
            {"year": "2021", "title": "Constituicao", "description": "Constituicao da JEX Nederland B.V. e registro comercial em Rotterdam."},
            {"year": "2023", "title": "Expansao", "description": "Operacao ampliada no antigo edificio da Unilever em Rotterdam."},
            {"year": "2024", "title": "Marca e parcerias", "description": "Novas iniciativas de marca, eventos e parceria com o Feyenoord."},
            {"year": "2025", "title": "Meta de equilibrio financeiro", "description": "A administracao projetou meses positivos no fim de 2025, mas ainda nao foi localizado resultado anual publicado que confirme a meta."},
            {"year": "2026", "title": "Divulgacao financeira pendente", "description": "A pesquisa publica mais recente ainda nao localizou demonstracoes consolidadas e auditadas de 2025."},
            {"year": "Atual", "title": "Software com IA", "description": "JEX CORE Sales, automacao de prospeccao, leads e dashboards."}
        ],
        "financial": {"revenue_2023": 112.0, "loss_2023": 24.5, "working_capital_deficit": 44.0, "tax_debt": 25.0, "additional_capital": 13.0},
        "reporting_update": {
            "verified_at": "17/07/2026",
            "latest_verified_year": "2023",
            "items": [
                {
                    "year": "2023", "status": "verified", "status_label": "Verificado",
                    "title": "Ultima fotografia detalhada publica",
                    "description": "Receita de EUR 112 mi, prejuizo de EUR 24,5 mi, patrimonio liquido negativo de EUR 15 mi, deficit de capital de giro de EUR 44 mi e divida tributaria superior a EUR 25 mi.",
                    "source_label": "Accountant.nl",
                    "portuguese_summary": [
                        "O contador da JEX declarou abstencao de opiniao sobre o relatorio anual de 2023 e apontou incerteza relevante sobre a continuidade da empresa.",
                        "A receita informada foi de EUR 112 milhoes e o prejuizo chegou a EUR 24,5 milhoes.",
                        "No fim de 2023, o patrimonio liquido era negativo em EUR 15 milhoes, o deficit de capital de giro era de EUR 44 milhoes e a divida tributaria superava EUR 25 milhoes.",
                        "Segundo a administracao, os deficits seriam cobertos por investimentos e emprestimos; naquele momento ainda havia conversas com novos financiadores."
                    ]
                },
                {
                    "year": "2024", "status": "preliminary", "status_label": "Preliminar",
                    "title": "Receita declarada pela administracao",
                    "description": "A administracao informou receita aproximada de EUR 220 mi e resultado ainda fortemente deficitario. O valor foi apresentado como nao formalizado nas contas.",
                    "source_label": "De Ondernemer",
                    "portuguese_summary": [
                        "O diretor-presidente declarou que a receita de 2024 teria aumentado para aproximadamente EUR 220 milhoes.",
                        "Ele ressaltou que o numero ainda nao estava formalizado nas demonstracoes contabeis.",
                        "Apesar do crescimento da receita, a empresa teria permanecido fortemente deficitaria em 2024.",
                        "Por essa razao, o valor deve ser tratado como informacao preliminar da administracao, e nao como resultado auditado."
                    ]
                },
                {
                    "year": "2025", "status": "unconfirmed", "status_label": "Nao confirmado",
                    "title": "Projecao de equilibrio",
                    "description": "A direcao projetou equilibrio e meses finais positivos, mas nao foi localizada publicacao posterior que confirme o resultado realizado em 2025.",
                    "source_label": "De Ondernemer",
                    "portuguese_summary": [
                        "A administracao projetava aproximar a empresa do ponto de equilibrio durante 2025.",
                        "A expectativa divulgada era encerrar 2025 ainda com prejuizo, mas apresentar meses positivos no fim do ano.",
                        "Essa declaracao era uma previsao feita pela direcao, nao um resultado financeiro ja realizado.",
                        "A pesquisa publica revisada em julho de 2026 nao localizou demonstracao consolidada posterior que confirme o cumprimento da meta."
                    ]
                }
            ],
            "note": "Bases empresariais indicam registros de 2025 para entidades relacionadas, mas valores fechados e dados de subsidiarias nao substituem demonstracoes consolidadas do grupo."
        },
        "assessment": {
            "sentiment": "Cauteloso / especulativo",
            "summary": "Perfil de crescimento agressivo com risco financeiro elevado. A evolucao depende de margem recorrente e geracao sustentavel de caixa.",
            "ipo": "Existe mencao publica a um possivel IPO, mas nao ha bolsa, cronograma ou prospecto confirmados."
        }
    }


flet_app = ft.app(
    target=main,
    assets_dir="assets",
    web_renderer=ft.WebRenderer.CANVAS_KIT,
    export_asgi_app=True,
)


async def _application(scope, receive, send):
    if scope["type"] == "lifespan":
        while True:
            message = await receive()
            if message["type"] == "lifespan.startup":
                await asyncio.to_thread(_reset_legacy_banking_module_once)
                await asyncio.to_thread(bank_statement_lab.ensure_lab_db)
                await asyncio.to_thread(bank_santander_store.ensure_db)
                try:
                    await asyncio.to_thread(bank_directory.sync_bank_directory)
                except Exception:
                    LOGGER.exception("Falha ao atualizar diretorio oficial de bancos; mantendo cache local")
                _schedule_ibovespa_market_refresh()
                await send({"type": "lifespan.startup.complete"})
            elif message["type"] == "lifespan.shutdown":
                await send({"type": "lifespan.shutdown.complete"})
                return

    if scope["type"] == "http" and scope.get("method") == "OPTIONS" and scope.get("path", "").startswith("/api/"):
        await send(
            {
                "type": "http.response.start",
                "status": 204,
                "headers": JSON_HEADERS,
            }
        )
        await send({"type": "http.response.body", "body": b""})
        return
    if scope["type"] == "http" and scope.get("path") == "/api/market/ibovespa":
        try:
            await send_json(send, await asyncio.to_thread(ibovespa_market_payload))
        except Exception as exc:
            await send_json(send, {"ok": False, "message": f"Nao foi possivel carregar o Ibovespa: {exc}"}, status=503)
        return
    if scope["type"] == "http" and scope.get("path", "").startswith("/api/market/ibovespa/"):
        symbol = scope.get("path", "").rsplit("/", 1)[-1]
        try:
            await send_json(send, await asyncio.to_thread(ibovespa_analysis_payload, symbol))
        except ValueError as exc:
            await send_json(send, {"ok": False, "message": str(exc)}, status=404)
        except Exception as exc:
            await send_json(send, {"ok": False, "message": f"Analise indisponivel: {exc}"}, status=503)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/jex/news":
        try:
            params = parse_qs(scope.get("query_string", b"").decode("utf-8"))
            force = (params.get("refresh") or [""])[0].lower() in {"1", "true", "yes"}
            payload = await asyncio.to_thread(jex_news.scan_and_archive, force)
            await send_json(send, payload)
        except Exception as exc:
            await send_json(send, {"ok": False, "message": f"Monitor JEX indisponivel: {exc}"}, status=503)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/jex":
        await send_json(send, jex_payload())
        return
    if scope["type"] == "http" and scope.get("path") == "/api/capital-flow":
        method = scope.get("method")
        if method == "GET":
            query = parse_qs((scope.get("query_string") or b"").decode("utf-8", errors="ignore"))
            today = datetime.now().strftime("%Y-%m-%d")
            date_from = (query.get("from") or [f"{datetime.now().year}-01-01"])[0]
            date_to = (query.get("to") or [today])[0]
            try:
                force = (query.get("refresh") or [""])[0].lower() in {"1", "true", "yes"}
                try:
                    sync = capital_flow_b3.start_background_sync(
                        date_from,
                        date_to,
                        force=force,
                    )
                except Exception as sync_error:
                    sync = {
                        "updated": 0,
                        "error": "A fonte oficial está temporariamente indisponível.",
                        "detail": str(sync_error)[:180],
                    }
                result = capital_flow_store.build_payload(date_from, date_to)
                result["sync"] = sync
                await send_json(send, result)
            except ValueError as exc:
                await send_json(send, {"ok": False, "message": str(exc)}, status=400)
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel carregar o fluxo de capital."}, status=500)
            return
        if method == "POST":
            if not has_valid_budget_api_session(scope):
                await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
                return
            try:
                item_id = capital_flow_store.save_record(await read_json_body(receive))
                await send_json(send, {"ok": True, "id": item_id}, status=201)
            except ValueError as exc:
                await send_json(send, {"ok": False, "message": str(exc)}, status=400)
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel salvar o registro."}, status=500)
            return
        await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        return
    if scope["type"] == "http" and scope.get("path", "").startswith("/api/capital-flow/"):
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        try:
            item_id = int(scope.get("path", "").rsplit("/", 1)[-1])
            if scope.get("method") == "PUT":
                capital_flow_store.save_record(await read_json_body(receive), item_id)
                await send_json(send, {"ok": True})
                return
            if scope.get("method") == "DELETE":
                deleted = capital_flow_store.delete_record(item_id)
                await send_json(send, {"ok": deleted}, status=200 if deleted else 404)
                return
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        except ValueError as exc:
            await send_json(send, {"ok": False, "message": str(exc)}, status=400)
        except LookupError as exc:
            await send_json(send, {"ok": False, "message": str(exc)}, status=404)
        except Exception:
            await send_json(send, {"ok": False, "message": "Nao foi possivel alterar o registro."}, status=500)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/investments/login":
        if scope.get("method") != "POST":
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
            return
        payload = await read_json_body(receive)
        if not main_module.investments_credentials_configured():
            await send_json(send, {"ok": False, "message": "Credenciais de investimentos nao configuradas."}, status=503)
            return
        if main_module.validate_investments_credentials(payload.get("login", ""), payload.get("password", "")):
            try:
                main_module.prepare_budget_storage_after_login()
                day_trade_store.ensure_day_trade_db()
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel preparar o banco financeiro."}, status=500)
                return
            await send_json(
                send,
                {
                    "ok": True,
                    "session_token": create_budget_api_session(payload.get("login", "").strip()),
                    "refresh_token": create_budget_refresh_token(payload.get("login", "").strip()),
                    "expires_in": ACCESS_TOKEN_TTL_SECONDS,
                    "dashboard": investments_dashboard_payload(),
                },
            )
            return
        await send_json(send, {"ok": False, "message": "Login ou senha invalidos."}, status=401)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/banking-lab/banks":
        owner_key = authenticated_owner_key(scope)
        if owner_key is None:
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        if scope.get("method") != "GET":
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
            return
        try:
            banks = await asyncio.to_thread(bank_directory.list_banks)
            await send_json(send, {
                "ok": True,
                "banks": banks,
                "source": "Banco Central do Brasil - Participantes do STR",
                "source_url": bank_directory.BCB_STR_CSV_URL,
            })
        except Exception:
            LOGGER.exception("Falha ao listar diretorio local de bancos")
            await send_json(send, {"ok": False, "message": "Nao foi possivel carregar a lista de bancos."}, status=500)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/banking-santander":
        owner_key = authenticated_owner_key(scope)
        if owner_key is None:
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        if scope.get("method") == "GET":
            try:
                import_processing = await asyncio.to_thread(_schedule_santander_import, owner_key)
                result = bank_santander_store.payload(owner_key)
                result["import_processing"] = import_processing
                await send_json(send, result)
            except Exception:
                LOGGER.exception("Falha ao carregar CRUD Santander")
                await send_json(send, {"ok": False, "message": "Nao foi possivel carregar os lancamentos Santander."}, status=500)
            return
        if scope.get("method") == "POST":
            try:
                saved = bank_santander_store.save_outflow(owner_key, await read_json_body(receive))
                await send_json(send, {"ok": True, **saved}, status=201)
            except ValueError as exc:
                await send_json(send, {"ok": False, "message": str(exc)}, status=400)
            except Exception:
                LOGGER.exception("Falha ao criar lancamento Santander")
                await send_json(send, {"ok": False, "message": "Nao foi possivel salvar o lancamento."}, status=500)
            return
        await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        return
    if scope["type"] == "http" and scope.get("path", "").startswith("/api/banking-santander/outflows/"):
        owner_key = authenticated_owner_key(scope)
        if owner_key is None:
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        try:
            outflow_id = int(scope.get("path", "").rsplit("/", 1)[-1])
            if scope.get("method") == "PUT":
                saved = bank_santander_store.save_outflow(owner_key, await read_json_body(receive), outflow_id)
                await send_json(send, {"ok": True, **saved})
                return
            if scope.get("method") == "DELETE":
                deleted = bank_santander_store.delete_outflow(owner_key, outflow_id)
                await send_json(send, {"ok": deleted}, status=200 if deleted else 404)
                return
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        except ValueError as exc:
            await send_json(send, {"ok": False, "message": str(exc)}, status=400)
        except LookupError as exc:
            await send_json(send, {"ok": False, "message": str(exc)}, status=404)
        except Exception:
            LOGGER.exception("Falha ao alterar lancamento Santander")
            await send_json(send, {"ok": False, "message": "Nao foi possivel alterar o lancamento."}, status=500)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/banking-santander/categories":
        owner_key = authenticated_owner_key(scope)
        if owner_key is None:
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        if scope.get("method") == "GET":
            await send_json(send, {"ok": True, "categories": bank_santander_store.list_categories(owner_key)})
            return
        if scope.get("method") == "POST":
            try:
                saved = bank_santander_store.save_category(owner_key, await read_json_body(receive))
                await send_json(send, {"ok": True, **saved}, status=201)
            except ValueError as exc:
                await send_json(send, {"ok": False, "message": str(exc)}, status=400)
            except Exception:
                LOGGER.exception("Falha ao criar categoria bancaria")
                await send_json(send, {"ok": False, "message": "Nao foi possivel salvar a categoria."}, status=500)
            return
        await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        return
    if scope["type"] == "http" and scope.get("path", "").startswith("/api/banking-santander/categories/"):
        owner_key = authenticated_owner_key(scope)
        if owner_key is None:
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        try:
            category_id = int(scope.get("path", "").rsplit("/", 1)[-1])
            if scope.get("method") == "PUT":
                saved = bank_santander_store.save_category(owner_key, await read_json_body(receive), category_id)
                await send_json(send, {"ok": True, **saved})
                return
            if scope.get("method") == "DELETE":
                deleted = bank_santander_store.delete_category(owner_key, category_id)
                await send_json(send, {"ok": deleted}, status=200 if deleted else 404)
                return
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        except ValueError as exc:
            await send_json(send, {"ok": False, "message": str(exc)}, status=400)
        except LookupError as exc:
            await send_json(send, {"ok": False, "message": str(exc)}, status=404)
        except Exception:
            LOGGER.exception("Falha ao alterar categoria bancaria")
            await send_json(send, {"ok": False, "message": "Nao foi possivel alterar a categoria."}, status=500)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/banking-lab/outflows":
        owner_key = authenticated_owner_key(scope)
        if owner_key is None:
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        if scope.get("method") != "GET":
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
            return
        try:
            entries = []
            ignored = []
            for stored in bank_statement_lab.list_test_files(owner_key):
                item = bank_statement_lab.get_test_file(owner_key, int(stored["id"]))
                if item is None or not str(item["filename"]).lower().endswith(".pdf"):
                    ignored.append(stored["filename"])
                    continue
                try:
                    entries.extend(statement_outflows.parse_santander_outflows(
                        item["content"], item["filename"], int(stored["id"])
                    ))
                except Exception:
                    LOGGER.exception("Falha ao extrair saidas do arquivo %s", stored["id"])
                    ignored.append(stored["filename"])
            await send_json(send, {
                "ok": True,
                "outflows": entries,
                "summary": statement_outflows.summarize_outflows(entries),
                "ignored_files": ignored,
            })
        except Exception:
            LOGGER.exception("Falha ao consolidar saidas bancarias")
            await send_json(send, {"ok": False, "message": "Nao foi possivel consolidar as saidas."}, status=500)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/banking-lab":
        owner_key = authenticated_owner_key(scope)
        if owner_key is None:
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        if scope.get("method") != "GET":
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
            return
        try:
            await send_json(send, {"ok": True, "files": bank_statement_lab.list_test_files(owner_key)})
        except Exception:
            LOGGER.exception("Falha ao listar arquivos do laboratorio de extratos")
            await send_json(send, {"ok": False, "message": "Nao foi possivel carregar os arquivos."}, status=500)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/banking-lab/upload":
        owner_key = authenticated_owner_key(scope)
        if owner_key is None:
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        if scope.get("method") != "POST":
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
            return
        try:
            result = bank_statement_lab.save_test_file(owner_key, await read_json_body(receive))
            await send_json(send, result, status=201)
        except ValueError as exc:
            await send_json(send, {"ok": False, "message": str(exc)}, status=400)
        except Exception:
            LOGGER.exception("Falha ao salvar arquivo no laboratorio de extratos")
            await send_json(send, {"ok": False, "message": "Nao foi possivel armazenar o arquivo."}, status=500)
        return
    if scope["type"] == "http" and scope.get("path", "").startswith("/api/banking-lab/files/"):
        owner_key = authenticated_owner_key(scope)
        if owner_key is None:
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        parts = scope.get("path", "").strip("/").split("/")
        try:
            file_id = int(parts[3])
        except (IndexError, ValueError):
            await send_json(send, {"ok": False, "message": "Arquivo invalido."}, status=400)
            return
        if len(parts) == 5 and parts[4] == "download" and scope.get("method") == "GET":
            item = bank_statement_lab.get_test_file(owner_key, file_id)
            if item is None:
                await send_json(send, {"ok": False, "message": "Arquivo nao encontrado."}, status=404)
                return
            safe_name = str(item["filename"]).replace('"', '')
            await send({"type": "http.response.start", "status": 200, "headers": [
                (b"content-type", str(item["mime_type"]).encode("latin-1", errors="ignore")),
                (b"content-disposition", f'attachment; filename="{safe_name}"'.encode("latin-1", errors="ignore")),
                (b"cache-control", b"no-store"),
                (b"access-control-allow-origin", b"*"),
            ]})
            await send({"type": "http.response.body", "body": item["content"]})
            return
        if len(parts) == 5 and parts[4] == "structure" and scope.get("method") == "GET":
            item = bank_statement_lab.get_test_file(owner_key, file_id)
            if item is None:
                await send_json(send, {"ok": False, "message": "Arquivo nao encontrado."}, status=404)
                return
            try:
                structure = await asyncio.to_thread(statement_structure.analyze_file, item)
                await send_json(send, {"ok": True, "structure": structure})
            except ValueError as exc:
                await send_json(send, {"ok": False, "message": str(exc)}, status=400)
            except Exception:
                LOGGER.exception("Falha ao estudar estrutura do extrato")
                await send_json(send, {"ok": False, "message": "Nao foi possivel ler a estrutura do arquivo."}, status=500)
            return
        if len(parts) == 4 and scope.get("method") == "DELETE":
            deleted = bank_statement_lab.delete_test_file(owner_key, file_id)
            await send_json(send, {"ok": deleted}, status=200 if deleted else 404)
            return
        await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/investments/refresh":
        if scope.get("method") != "POST":
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
            return
        payload = await read_json_body(receive)
        claims = _session_claims_from_token(
            str(payload.get("refresh_token", "")), "refresh"
        )
        if claims is None:
            await send_json(
                send,
                {"ok": False, "message": "Sua sessao expirou. Faca login novamente."},
                status=401,
            )
            return
        user = str(claims.get("user", ""))
        await send_json(
            send,
            {
                "ok": True,
                "session_token": create_budget_api_session(user),
                "refresh_token": create_budget_refresh_token(user),
                "expires_in": ACCESS_TOKEN_TTL_SECONDS,
            },
        )
        return
    if scope["type"] == "http" and scope.get("path") == "/api/investments/dashboard":
        await send_json(send, {"ok": True, "dashboard": investments_dashboard_payload()})
        return
    if scope["type"] == "http" and scope.get("path") == "/api/investments":
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        method = scope.get("method")
        if method == "GET":
            try:
                await send_json(send, investments_payload())
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel carregar os investimentos."}, status=500)
            return
        if method == "POST":
            try:
                option = validated_investment_payload(await read_json_body(receive))
                inserted = main_module.save_investment_option(option)
                if not inserted:
                    await send_json(send, {"ok": False, "message": f"{option['name']} ja estava cadastrado."}, status=409)
                    return
                await send_json(send, investments_payload(), status=201)
            except ValueError as exc:
                await send_json(send, {"ok": False, "message": str(exc)}, status=400)
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel salvar o investimento."}, status=500)
            return
        await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/investments/statement":
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        if scope.get("method") != "GET":
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
            return
        try:
            await send_json(send, investments_statement_payload())
        except Exception:
            await send_json(send, {"ok": False, "message": "Nao foi possivel carregar o extrato dos investimentos."}, status=500)
        return
    if scope["type"] == "http" and scope.get("path", "").startswith("/api/investments/"):
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        method = scope.get("method")
        path_parts = scope.get("path", "").strip("/").split("/")
        try:
            item_id = str(int(path_parts[2]))
        except (IndexError, ValueError):
            await send_json(send, {"ok": False, "message": "Investimento invalido."}, status=400)
            return
        if len(path_parts) == 3 and method == "PUT":
            try:
                payload = await read_json_body(receive)
                existing = next(
                    (
                        item
                        for item in main_module.load_saved_investment_records()
                        if int(item["id"]) == int(item_id)
                    ),
                    None,
                )
                if existing is None:
                    await send_json(send, {"ok": False}, status=404)
                    return
                is_day_trade = (
                    str(existing["name"]) == main_module.DAY_TRADE_INVESTMENT_NAME
                    and str(existing["source"]) == "Controle Day Trade"
                )
                if is_day_trade:
                    capital_text = normalize_positive_trade_value(
                        payload.get("amount_text"), "Capital alocado"
                    )
                    day_trade_store.save_initial_capital(capital_text)
                    amount_text = normalize_investment_amount(capital_text)
                else:
                    amount_text = normalize_investment_amount(payload.get("amount_text"))
                updated = main_module.update_saved_investment_amount(item_id, amount_text)
                await send_json(send, {"ok": updated}, status=200 if updated else 404)
            except ValueError as exc:
                await send_json(send, {"ok": False, "message": str(exc)}, status=400)
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel salvar o valor aplicado."}, status=500)
            return
        if len(path_parts) == 3 and method == "DELETE":
            try:
                existing = next(
                    (
                        item
                        for item in main_module.load_saved_investment_records()
                        if int(item["id"]) == int(item_id)
                    ),
                    None,
                )
                deleted = main_module.delete_saved_investment_by_id(item_id)
                if (
                    deleted
                    and existing is not None
                    and str(existing["name"]) == main_module.DAY_TRADE_INVESTMENT_NAME
                    and str(existing["source"]) == "Controle Day Trade"
                ):
                    day_trade_store.reset_capital()
                await send_json(send, {"ok": deleted}, status=200 if deleted else 404)
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel excluir o investimento."}, status=500)
            return
        await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/day-trade/capital":
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        method = scope.get("method")
        if method == "GET":
            await send_json(send, {"ok": True, **day_trade_store.capital_summary()})
            return
        if method == "PUT":
            try:
                payload = await read_json_body(receive)
                capital_text = normalize_positive_trade_value(
                    payload.get("capital_text"), "Capital alocado"
                )
                settings = day_trade_store.save_initial_capital(capital_text)
                summary = day_trade_store.capital_summary()
                main_module.save_day_trade_investment_amount(
                    normalize_investment_amount(summary["capital_text"])
                )
                await send_json(
                    send,
                    {"ok": True, **summary},
                )
            except ValueError as exc:
                await send_json(send, {"ok": False, "message": str(exc)}, status=400)
            except Exception:
                await send_json(
                    send,
                    {"ok": False, "message": "Nao foi possivel salvar o capital alocado."},
                    status=500,
                )
            return
        await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/day-trade/capital/deposits":
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        method = scope.get("method")
        if method == "GET":
            await send_json(send, {"ok": True, **day_trade_store.capital_summary()})
            return
        if method == "POST":
            try:
                payload = await read_json_body(receive)
                if day_trade_store.decimal_value(
                    day_trade_store.capital_summary()["initial_capital_text"]
                ) <= 0:
                    raise ValueError("Cadastre o capital inicial antes de depositar.")
                movement_type = str(payload.get("movement_type", "")).strip()
                if movement_type == "Subtração":
                    movement_type = "Subtracao"
                if movement_type not in {"Entrada", "Subtracao"}:
                    raise ValueError("Selecione entrada ou subtracao.")
                source_type = str(payload.get("source_type", "")).strip()
                if source_type not in {"Capital extra", "Day Trade"}:
                    raise ValueError("Selecione a origem do deposito.")
                source_description = str(
                    payload.get("source_description", "")
                ).strip()[:120]
                if source_type == "Capital extra" and not source_description:
                    raise ValueError("Informe a origem do capital extra.")
                if source_type == "Day Trade":
                    source_description = "Ajuste manual Day Trade"
                amount_text = normalize_positive_trade_value(
                    payload.get("amount_text"), "Valor da movimentacao"
                )
                current_capital = day_trade_store.decimal_value(
                    day_trade_store.capital_summary()["capital_text"]
                )
                if (
                    movement_type == "Subtracao"
                    and day_trade_store.decimal_value(amount_text) > current_capital
                ):
                    raise ValueError(
                        "A subtracao nao pode ser maior que o capital atual."
                    )
                summary = day_trade_store.add_capital_deposit(
                    normalize_trade_date(payload.get("deposit_date")),
                    movement_type,
                    source_type,
                    source_description,
                    amount_text,
                )
                main_module.save_day_trade_investment_amount(
                    normalize_investment_amount(summary["capital_text"])
                )
                await send_json(send, {"ok": True, **summary}, status=201)
            except ValueError as exc:
                await send_json(send, {"ok": False, "message": str(exc)}, status=400)
            except Exception:
                await send_json(
                    send,
                    {"ok": False, "message": "Nao foi possivel depositar o capital."},
                    status=500,
                )
            return
        await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/day-trade/settings":
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        if scope.get("method") != "PUT":
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
            return
        try:
            settings = day_trade_store.save_settings(
                validated_day_trade_settings(await read_json_body(receive))
            )
            await send_json(send, {"ok": True, "settings": settings})
        except ValueError as exc:
            await send_json(send, {"ok": False, "message": str(exc)}, status=400)
        except Exception:
            await send_json(send, {"ok": False, "message": "Nao foi possivel salvar o plano de risco."}, status=500)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/day-trade/bi":
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        if scope.get("method") != "GET":
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
            return
        query = parse_qs((scope.get("query_string") or b"").decode("utf-8", errors="ignore"))
        date_from = (query.get("from") or [datetime.now().strftime("%Y-%m-%d")])[0]
        date_to = (query.get("to") or [date_from])[0]
        try:
            date_from = normalize_trade_date(date_from)
            date_to = normalize_trade_date(date_to)
            if date_from > date_to:
                raise ValueError("Periodo de consulta invalido.")
            await send_json(send, day_trade_store.build_bi_payload(date_from, date_to))
        except ValueError as exc:
            await send_json(send, {"ok": False, "message": str(exc)}, status=400)
        except Exception:
            await send_json(send, {"ok": False, "message": "Nao foi possivel carregar o BI."}, status=500)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/day-trade/navigation":
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        if scope.get("method") != "GET":
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
            return
        try:
            await send_json(
                send,
                {
                    "ok": True,
                    "account_type": "REAL",
                    "items": day_trade_store.list_all_operations(),
                },
            )
        except Exception:
            await send_json(send, {"ok": False, "message": "Nao foi possivel carregar a navegacao."}, status=500)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/day-trade":
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        method = scope.get("method")
        if method == "GET":
            query = parse_qs((scope.get("query_string") or b"").decode("utf-8", errors="ignore"))
            trade_date = (query.get("date") or [datetime.now().strftime("%Y-%m-%d")])[0]
            try:
                await send_json(send, day_trade_store.build_payload(normalize_trade_date(trade_date)))
            except ValueError as exc:
                await send_json(send, {"ok": False, "message": str(exc)}, status=400)
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel carregar as operacoes."}, status=500)
            return
        if method == "POST":
            try:
                item = validated_day_trade_payload(await read_json_body(receive))
                item_id = day_trade_store.create_operation(item)
                await send_json(
                    send,
                    {"ok": True, "id": item_id, **day_trade_store.build_payload(item["trade_date"])},
                    status=201,
                )
            except ValueError as exc:
                await send_json(send, {"ok": False, "message": str(exc)}, status=400)
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel salvar a operacao."}, status=500)
            return
        await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        return
    if scope["type"] == "http" and scope.get("path", "").startswith("/api/day-trade/"):
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        method = scope.get("method")
        path_parts = scope.get("path", "").strip("/").split("/")
        try:
            item_id = str(int(path_parts[2]))
        except (IndexError, ValueError):
            await send_json(send, {"ok": False, "message": "Operacao invalida."}, status=400)
            return
        if len(path_parts) == 4 and path_parts[3] == "close" and method == "PATCH":
            try:
                item = validated_day_trade_close_payload(await read_json_body(receive))
                updated = day_trade_store.close_operation(item_id, **item)
                await send_json(send, {"ok": updated}, status=200 if updated else 404)
            except ValueError as exc:
                await send_json(send, {"ok": False, "message": str(exc)}, status=400)
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel encerrar a operacao."}, status=500)
            return
        if len(path_parts) == 3 and method == "PATCH":
            try:
                item = validated_day_trade_payload(await read_json_body(receive))
                updated = day_trade_store.update_operation(item_id, item)
                await send_json(send, {"ok": updated}, status=200 if updated else 404)
            except ValueError as exc:
                await send_json(send, {"ok": False, "message": str(exc)}, status=400)
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel editar a operacao."}, status=500)
            return
        if len(path_parts) == 3 and method == "DELETE":
            try:
                deleted = day_trade_store.delete_operation(item_id)
                await send_json(send, {"ok": deleted}, status=200 if deleted else 404)
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel excluir a operacao."}, status=500)
            return
        await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/cash":
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        if scope.get("method") != "GET":
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
            return
        try:
            await send_json(send, {"ok": True, "items": main_module.load_caixa_entries()})
        except Exception:
            await send_json(send, {"ok": False, "message": "Nao foi possivel carregar o Caixa."}, status=500)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/budget/expense-natures":
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        method = scope.get("method")
        try:
            if method == "GET":
                await send_json(send, {"ok": True, "items": main_module.list_expense_natures()})
                return
            if method == "POST":
                nature_id = main_module.save_expense_nature((await read_json_body(receive)).get("name"))
                await send_json(send, {"ok": True, "id": nature_id, "message": "Natureza cadastrada com sucesso.", "items": main_module.list_expense_natures()}, status=201)
                return
        except ValueError as exc:
            await send_json(send, {"ok": False, "message": str(exc)}, status=400)
            return
        except Exception:
            await send_json(send, {"ok": False, "message": "Nao foi possivel administrar as naturezas."}, status=500)
            return
        await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        return
    if scope["type"] == "http" and scope.get("path", "").startswith("/api/b3-investor-flow/"):
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        path = scope.get("path", "")
        method = scope.get("method")
        query = parse_qs((scope.get("query_string") or b"").decode("utf-8", errors="ignore"))
        today = datetime.now().strftime("%Y-%m-%d")
        date_from = (query.get("from") or ["2026-04-01"])[0]
        date_to = (query.get("to") or [today])[0]
        if method == "GET" and path in {
            "/api/b3-investor-flow/latest", "/api/b3-investor-flow/history",
            "/api/b3-investor-flow/summary", "/api/b3-investor-flow/status",
        }:
            try:
                result = capital_flow_store.build_payload(date_from, date_to)
                if path.endswith("/latest"):
                    latest_date = result.get("latest_trade_date")
                    result["items"] = [item for item in result["items"] if item["reference_date"] == latest_date]
                result["automation"] = capital_flow_b3.sync_job_status()
                await send_json(send, result)
            except ValueError as exc:
                await send_json(send, {"ok": False, "message": str(exc)}, status=400)
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel consultar o fluxo de investidores B3."}, status=500)
            return
        if method == "POST" and path in {
            "/api/b3-investor-flow/backfill", "/api/b3-investor-flow/reprocess",
        }:
            payload = await read_json_body(receive)
            start = str(payload.get("start") or "2026-04-01")
            end = str(payload.get("end") or today)
            job = capital_flow_b3.start_background_sync(start, end, force=path.endswith("/reprocess"))
            await send_json(send, {"ok": True, "job": job}, status=202)
            return
        await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        return
    if scope["type"] == "http" and scope.get("path") in {
        "/api/market-global/status",
        "/api/market-global/quotes",
        "/api/market-global/diagnostics",
    }:
        payload = await asyncio.to_thread(monitor_global.market_data_service.snapshot)
        path = scope.get("path")
        if path.endswith("/quotes"):
            payload = {
                "ok": payload["ok"],
                "quotes": payload["quotes"],
                "model": payload["model"],
            }
        elif path.endswith("/diagnostics"):
            payload = {
                "ok": payload["ok"],
                "diagnostics": payload["diagnostics"],
            }
        await send_json(send, payload)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/analysis-engine/status":
        if scope.get("method") != "GET":
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
            return
        query = parse_qs((scope.get("query_string") or b"").decode("utf-8"))
        period = (query.get("period") or ["15m"])[0]
        payload = await asyncio.to_thread(analysis_service.snapshot, period)
        await send_json(send, payload)
        return
    if scope["type"] == "http" and scope.get("path", "").startswith("/api/budget/expense-natures/"):
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        try:
            nature_id = int(scope.get("path", "").rstrip("/").split("/")[-1])
            method = scope.get("method")
            if method == "PUT":
                payload = await read_json_body(receive)
                updated = main_module.update_expense_nature(nature_id, name=payload.get("name"))
                await send_json(send, {"ok": updated, "message": "Natureza atualizada com sucesso.", "items": main_module.list_expense_natures()}, status=200 if updated else 404)
                return
        except ValueError as exc:
            await send_json(send, {"ok": False, "message": str(exc)}, status=400)
            return
        except Exception:
            await send_json(send, {"ok": False, "message": "Nao foi possivel administrar a natureza."}, status=500)
            return
        await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/budget/categorize-expenses":
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        if scope.get("method") != "POST":
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
            return
        try:
            payload = await read_json_body(receive)
            updated = main_module.categorize_expenses(payload.get("item_ids") or [], int(payload.get("expense_nature_id")))
            await send_json(send, {"ok": True, "updated": updated, "message": f"Natureza aplicada com sucesso a {updated} despesas."})
        except (ValueError, TypeError) as exc:
            await send_json(send, {"ok": False, "message": str(exc)}, status=400)
        except Exception:
            await send_json(send, {"ok": False, "message": "Nao foi possivel categorizar as despesas."}, status=500)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/budget/import-previous-month-preview":
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        if scope.get("method") != "POST":
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
            return
        try:
            payload = await read_json_body(receive)
            target_month = str(payload.get("target_month") or "").strip()
            result = main_module.preview_previous_month_budget_import(target_month)
            await send_json(send, {"ok": True, **result})
        except ValueError as exc:
            await send_json(send, {"ok": False, "message": str(exc)}, status=400)
        except Exception:
            await send_json(send, {"ok": False, "message": "Nao foi possivel revisar a importacao."}, status=500)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/budget/import-previous-month":
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        if scope.get("method") != "POST":
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
            return
        try:
            payload = await read_json_body(receive)
            target_month = str(payload.get("target_month") or "").strip()
            result = main_module.import_previous_month_budget_expenses(target_month)
            await send_json(send, {"ok": True, **result, **budget_payload(target_month)})
        except PermissionError as exc:
            await send_json(send, {"ok": False, "message": str(exc)}, status=409)
        except ValueError as exc:
            await send_json(send, {"ok": False, "message": str(exc)}, status=400)
        except Exception:
            await send_json(send, {"ok": False, "message": "Nao foi possivel importar o mes anterior."}, status=500)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/budget/month-status":
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        if scope.get("method") != "PATCH":
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
            return
        try:
            payload = await read_json_body(receive)
            reference_month = str(payload.get("reference_month") or "").strip()
            period_status = str(payload.get("status") or "").strip()
            main_module.set_monthly_budget_period_status(reference_month, period_status)
            await send_json(send, {
                "ok": True,
                "reference_month": reference_month,
                "status": period_status,
                "import_allowed": main_module.monthly_budget_period_allows_import(reference_month),
                "month_statuses": main_module.list_monthly_budget_period_statuses(),
            })
        except ValueError as exc:
            await send_json(send, {"ok": False, "message": str(exc)}, status=400)
        except Exception:
            await send_json(send, {"ok": False, "message": "Nao foi possivel alterar o status mensal."}, status=500)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/budget":
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        method = scope.get("method")
        if method == "GET":
            query = parse_qs((scope.get("query_string") or b"").decode("utf-8", errors="ignore"))
            reference_month = (query.get("month") or [None])[0]
            if reference_month is not None and not re.fullmatch(
                r"\d{4}-(0[1-9]|1[0-2])", reference_month
            ):
                await send_json(send, {"ok": False, "message": "Mes de referencia invalido."}, status=400)
                return
            try:
                await send_json(send, budget_payload(reference_month))
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel carregar o orcamento."}, status=500)
            return
        if method == "POST":
            try:
                item = validated_budget_payload(await read_json_body(receive))
                item_id = main_module.save_monthly_budget_item(**item)
                await send_json(send, {"ok": True, "id": item_id, **budget_payload(item["reference_month"])}, status=201)
            except ValueError as exc:
                await send_json(send, {"ok": False, "message": str(exc)}, status=400)
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel salvar o lancamento."}, status=500)
            return
        await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/budget/bi":
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        if scope.get("method") != "GET":
            await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
            return
        query = parse_qs((scope.get("query_string") or b"").decode("utf-8", errors="ignore"))
        year_text = (query.get("year") or [str(datetime.now().year)])[0]
        if not re.fullmatch(r"\d{4}", year_text):
            await send_json(send, {"ok": False, "message": "Ano invalido."}, status=400)
            return
        try:
            items = main_module.load_yearly_budget_items(int(year_text))
            await send_json(send, {"ok": True, "year": int(year_text), "items": items})
        except Exception:
            await send_json(send, {"ok": False, "message": "Nao foi possivel carregar o BI do orcamento."}, status=500)
        return
    if scope["type"] == "http" and scope.get("path", "").startswith("/api/budget/"):
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        method = scope.get("method")
        path_parts = scope.get("path", "").strip("/").split("/")
        try:
            item_id = str(int(path_parts[2]))
        except (IndexError, ValueError):
            await send_json(send, {"ok": False, "message": "Lancamento invalido."}, status=400)
            return
        if len(path_parts) == 4 and path_parts[3] == "status" and method == "PATCH":
            payload = await read_json_body(receive)
            if not isinstance(payload.get("settled"), bool):
                await send_json(send, {"ok": False, "message": "Status invalido."}, status=400)
                return
            try:
                updated = main_module.update_monthly_budget_item_status(item_id, payload["settled"])
                await send_json(send, {"ok": updated}, status=200 if updated else 404)
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel alterar o status."}, status=500)
            return
        if len(path_parts) == 3 and method == "PUT":
            try:
                item = validated_budget_payload(await read_json_body(receive))
                updated = main_module.update_monthly_budget_item(item_id, **item)
                await send_json(send, {"ok": updated, **budget_payload(item["reference_month"])}, status=200 if updated else 404)
            except ValueError as exc:
                await send_json(send, {"ok": False, "message": str(exc)}, status=400)
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel alterar o lancamento."}, status=500)
            return
        if len(path_parts) == 3 and method == "DELETE":
            try:
                deleted = main_module.delete_monthly_budget_item(item_id)
                await send_json(send, {"ok": deleted}, status=200 if deleted else 404)
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel excluir o lancamento."}, status=500)
            return
        await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        return
    if scope["type"] == "http" and scope.get("path") == "/_app-version":
        payload = json.dumps(
            {"version": APP_VERSION, "theme": "light-cream"},
            ensure_ascii=True,
        ).encode("utf-8")
        await send(
            {
                "type": "http.response.start",
                "status": 200,
                "headers": [
                    (b"content-type", b"application/json; charset=utf-8"),
                    (b"cache-control", b"no-store"),
                ],
            }
        )
        await send({"type": "http.response.body", "body": payload})
        return
    if scope["type"] == "http" and scope.get("path") == "/_db-status":
        payload = json.dumps(investment_db_status(), ensure_ascii=True).encode("utf-8")
        await send(
            {
                "type": "http.response.start",
                "status": 200,
                "headers": [
                    (b"content-type", b"application/json; charset=utf-8"),
                    (b"cache-control", b"no-store"),
                ],
            }
        )
        await send({"type": "http.response.body", "body": payload})
        return
    if scope["type"] == "http" and scope.get("path") == "/_budget-report-print":
        query = parse_qs((scope.get("query_string") or b"").decode("utf-8", errors="ignore"))
        token = (query.get("token") or [""])[0]
        html_content = budget_report_print_html(token)
        if html_content is None:
            await send(
                {
                    "type": "http.response.start",
                    "status": 403,
                    "headers": [
                        (b"content-type", b"text/plain; charset=utf-8"),
                        (b"cache-control", b"no-store"),
                    ],
                }
            )
            await send({"type": "http.response.body", "body": b"Relatorio expirado ou invalido."})
            return
        await send(
            {
                "type": "http.response.start",
                "status": 200,
                "headers": [
                    (b"content-type", b"text/html; charset=utf-8"),
                    (b"cache-control", b"no-store"),
                ],
            }
        )
        await send({"type": "http.response.body", "body": html_content.encode("utf-8")})
        return
    await flet_app(scope, receive, send)


async def app(scope, receive, send):
    """ASGI boundary with one structured audit log for every HTTP request."""
    if scope.get("type") != "http":
        await _application(scope, receive, send)
        return

    started = time.perf_counter()
    status_code = 500
    claims = _session_claims_from_token(_bearer_token(scope), "access") or {}
    user = str(claims.get("user", "anonymous"))

    async def logged_send(message):
        nonlocal status_code
        if message.get("type") == "http.response.start":
            status_code = int(message.get("status", 500))
        await send(message)

    try:
        await _application(scope, receive, logged_send)
    except Exception:
        LOGGER.exception(
            "request_failed user=%s method=%s endpoint=%s elapsed_ms=%.1f",
            user,
            scope.get("method", ""),
            scope.get("path", ""),
            (time.perf_counter() - started) * 1000,
        )
        raise
    finally:
        LOGGER.info(
            "request_complete user=%s method=%s endpoint=%s status=%s elapsed_ms=%.1f",
            user,
            scope.get("method", ""),
            scope.get("path", ""),
            status_code,
            (time.perf_counter() - started) * 1000,
        )
