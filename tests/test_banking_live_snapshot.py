import asyncio
import json

import web_app


def test_snapshot_reads_saved_expenses_without_reprocessing_uploads(monkeypatch):
    monkeypatch.setattr(web_app, "authenticated_owner_key", lambda scope: "owner")
    monkeypatch.setattr(web_app.bank_statement_lab, "list_test_files",
                        lambda owner: (_ for _ in ()).throw(AssertionError("snapshot must not parse files")))
    calls = []
    rows = [{"id": 7, "amount": 23.45}]

    def movements(owner, search):
        calls.append((owner, search))
        return rows

    monkeypatch.setattr(web_app.bank_outflow_store, "list_movements", movements)
    messages = []

    async def send(message):
        messages.append(message)

    async def receive():
        return {"type": "http.request", "body": b"", "more_body": False}

    asyncio.run(web_app._application({
        "type": "http", "method": "GET", "path": "/api/banking-lab/outflows",
        "query_string": b"snapshot=1&q=mercado", "headers": [],
    }, receive, send))
    assert messages[0]["status"] == 200
    body = json.loads(messages[1]["body"])
    assert calls == [("owner", "mercado")]
    assert body["outflows"] == rows
    assert body["summary"]["total"] == 23.45
    assert body["imported"] == 0


def test_snapshot_still_requires_login(monkeypatch):
    monkeypatch.setattr(web_app, "authenticated_owner_key", lambda scope: None)
    monkeypatch.setattr(web_app.bank_outflow_store, "list_movements",
                        lambda *args: (_ for _ in ()).throw(AssertionError("unauthenticated read")))
    messages = []

    async def send(message):
        messages.append(message)

    asyncio.run(web_app._application({
        "type": "http", "method": "GET", "path": "/api/banking-lab/outflows",
        "query_string": b"snapshot=1", "headers": [],
    }, None, send))
    assert messages[0]["status"] == 401
