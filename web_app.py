import json
import re
import secrets
import time
from datetime import datetime
from decimal import Decimal, InvalidOperation
from urllib.parse import parse_qs

import flet as ft
import main as main_module


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
main_module.APP_VERSION = "2026.07.13-flutter-post-login-v33"

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

BUDGET_API_SESSION_TTL_SECONDS = 8 * 60 * 60
BUDGET_API_SESSIONS: dict[str, float] = {}


def create_budget_api_session() -> str:
    now = time.time()
    for token, expires_at in list(BUDGET_API_SESSIONS.items()):
        if expires_at <= now:
            BUDGET_API_SESSIONS.pop(token, None)
    token = secrets.token_urlsafe(32)
    BUDGET_API_SESSIONS[token] = now + BUDGET_API_SESSION_TTL_SECONDS
    return token


def has_valid_budget_api_session(scope) -> bool:
    headers = {key.lower(): value for key, value in scope.get("headers", [])}
    authorization = headers.get(b"authorization", b"").decode("utf-8", errors="ignore")
    if not authorization.startswith("Bearer "):
        return False
    token = authorization.removeprefix("Bearer ").strip()
    expires_at = BUDGET_API_SESSIONS.get(token, 0)
    if expires_at <= time.time():
        BUDGET_API_SESSIONS.pop(token, None)
        return False
    return True


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


def normalize_budget_date(value: object, *, required: bool) -> str | None:
    text = str(value or "").strip()
    if not text and not required:
        return None
    try:
        return datetime.strptime(text, "%Y-%m-%d").strftime("%Y-%m-%d")
    except ValueError as exc:
        raise ValueError("Informe uma data valida.") from exc


def validated_budget_payload(payload: dict) -> dict:
    reference_month = str(payload.get("reference_month", "")).strip()
    if not re.fullmatch(r"\d{4}-(0[1-9]|1[0-2])", reference_month):
        raise ValueError("Escolha um mes de referencia.")
    item_type = str(payload.get("item_type", "")).strip()
    if item_type not in {"Receita", "Despesa"}:
        raise ValueError("Selecione receita ou despesa.")
    description = str(payload.get("description", "")).strip().upper()[:15]
    if not description:
        raise ValueError("Informe a descricao.")
    settled = bool(payload.get("settled", False))
    payment_date = normalize_budget_date(payload.get("payment_date"), required=False)
    if item_type == "Despesa" and settled and not payment_date:
        raise ValueError("Informe a data do pagamento.")
    return {
        "reference_month": reference_month,
        "item_type": item_type,
        "description": description,
        "amount_text": normalize_budget_amount(payload.get("amount_text")),
        "due_date": normalize_budget_date(payload.get("due_date"), required=True),
        "payment_date": payment_date,
        "settled": settled,
    }


def budget_payload(reference_month: str) -> dict:
    return {
        "ok": True,
        "reference_month": reference_month,
        "items": main_module.load_monthly_budget_items(reference_month),
        "months": main_module.list_monthly_budget_months(),
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
    return {
        "ok": True,
        "items": main_module.load_saved_investment_records(),
        "options": main_module.SANTANDER_FIXED_INCOME_OPTIONS,
    }


def investments_dashboard_payload() -> dict:
    return {
        "title": "Controle de investimentos",
        "subtitle": "Area logada | Painel de gestao financeira",
        "status": "Sessao autorizada",
        "actions": [
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


flet_app = ft.app(
    target=main,
    assets_dir="assets",
    web_renderer=ft.WebRenderer.CANVAS_KIT,
    export_asgi_app=True,
)


async def app(scope, receive, send):
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
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel preparar o banco do orcamento."}, status=500)
                return
            await send_json(
                send,
                {
                    "ok": True,
                    "session_token": create_budget_api_session(),
                    "dashboard": investments_dashboard_payload(),
                },
            )
            return
        await send_json(send, {"ok": False, "message": "Login ou senha invalidos."}, status=401)
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
                deleted = main_module.delete_saved_investment_by_id(item_id)
                await send_json(send, {"ok": deleted}, status=200 if deleted else 404)
            except Exception:
                await send_json(send, {"ok": False, "message": "Nao foi possivel excluir o investimento."}, status=500)
            return
        await send_json(send, {"ok": False, "message": "Metodo nao permitido."}, status=405)
        return
    if scope["type"] == "http" and scope.get("path") == "/api/budget":
        if not has_valid_budget_api_session(scope):
            await send_json(send, {"ok": False, "message": "Sessao expirada. Entre novamente."}, status=401)
            return
        method = scope.get("method")
        if method == "GET":
            query = parse_qs((scope.get("query_string") or b"").decode("utf-8", errors="ignore"))
            reference_month = (query.get("month") or [datetime.now().strftime("%Y-%m")])[0]
            if not re.fullmatch(r"\d{4}-(0[1-9]|1[0-2])", reference_month):
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
