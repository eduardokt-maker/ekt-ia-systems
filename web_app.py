import json
from urllib.parse import parse_qs

import flet as ft

from main import APP_VERSION, budget_report_print_html, investment_db_status, main


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
