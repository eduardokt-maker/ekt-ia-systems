import json

import flet as ft

from main import APP_VERSION, investment_db_status, main


flet_app = ft.run(main, assets_dir="assets", export_asgi_app=True)


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
    await flet_app(scope, receive, send)
