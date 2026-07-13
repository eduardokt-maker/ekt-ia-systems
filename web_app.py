import json
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
main_module.APP_VERSION = "2026.07.13-investments-menu-v30"

APP_VERSION = main_module.APP_VERSION
budget_report_print_html = main_module.budget_report_print_html
investment_db_status = main_module.investment_db_status
main = main_module.main


flet_app = ft.app(
    target=main,
    assets_dir="assets",
    web_renderer=ft.WebRenderer.CANVAS_KIT,
    export_asgi_app=True,
)


async def app(scope, receive, send):
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
