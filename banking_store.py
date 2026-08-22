from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from datetime import date, datetime
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from typing import Any
from zoneinfo import ZoneInfo

import main as main_module


DEFAULT_EXPENSE_CATEGORIES = (
    "Alimentação", "Supermercado", "Restaurantes", "Delivery",
    "Combustível", "Transporte", "Farmácia", "Saúde", "Educação",
    "Moradia", "Condomínio", "Energia", "Água", "Internet", "Telefone",
    "Assinaturas", "Streaming", "Vestuário", "Lazer", "Viagens", "Compras",
    "Manutenção", "Serviços", "Impostos", "Taxas", "Financeiro", "Juros",
    "Tarifas bancárias", "Outros",
)
DEFAULT_INCOME_CATEGORIES = (
    "Salário", "Aluguel", "Transferência recebida", "PIX recebido", "TED",
    "Depósito", "Rendimentos", "Dividendos", "Reembolso",
    "Receita de investimento", "Receita de Day Trade", "Venda",
    "Receita eventual", "Outros",
)
TRANSACTION_TYPES = {"INCOME", "EXPENSE", "TRANSFER"}


def _now() -> str:
    return datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat(timespec="seconds")


def _money_cents(value: object, *, allow_zero: bool = False) -> int:
    text = str(value or "").strip().replace("R$", "").replace(" ", "")
    if "," in text:
        text = text.replace(".", "").replace(",", ".")
    try:
        amount = Decimal(text).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    except InvalidOperation as exc:
        raise ValueError("Informe um valor monetário válido.") from exc
    if amount < 0 or (amount == 0 and not allow_zero):
        raise ValueError("Informe um valor maior que zero.")
    return int(amount * 100)


def _money_text(cents: int) -> str:
    amount = Decimal(int(cents)) / 100
    return f"{amount:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")


def _required(payload: dict, key: str, label: str, length: int = 140) -> str:
    value = str(payload.get(key, "")).strip()[:length]
    if not value:
        raise ValueError(f"Informe {label}.")
    return value


def _date(value: object, label: str = "uma data válida") -> str:
    try:
        return datetime.strptime(str(value or ""), "%Y-%m-%d").strftime("%Y-%m-%d")
    except ValueError as exc:
        raise ValueError(f"Informe {label}.") from exc


@contextmanager
def _connection():
    if main_module.use_postgres_investment_db():
        with main_module.investment_db_connection() as connection:
            yield connection
        return
    connection = sqlite3.connect(main_module.INVESTMENT_DB_PATH)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    try:
        yield connection
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def _postgres() -> bool:
    return main_module.use_postgres_investment_db()


def ensure_banking_db() -> None:
    if _postgres():
        main_module.ensure_postgres_investment_db()
    else:
        main_module.INVESTMENT_DATA_DIR.mkdir(parents=True, exist_ok=True)
        if (
            main_module.LEGACY_INVESTMENT_DB_PATH.exists()
            and not main_module.INVESTMENT_DB_PATH.exists()
        ):
            main_module.LEGACY_INVESTMENT_DB_PATH.replace(
                main_module.INVESTMENT_DB_PATH
            )
    serial = "BIGSERIAL" if _postgres() else "INTEGER"
    id_tail = "" if _postgres() else " AUTOINCREMENT"
    timestamp = "TIMESTAMPTZ NOT NULL DEFAULT NOW()" if _postgres() else "TEXT NOT NULL"
    boolean = "BOOLEAN" if _postgres() else "INTEGER"
    with _connection() as connection:
        connection.execute(f"""
            CREATE TABLE IF NOT EXISTS bank_accounts (
                id {serial} PRIMARY KEY{id_tail}, owner_key TEXT NOT NULL,
                bank_name TEXT NOT NULL, description TEXT NOT NULL,
                account_type TEXT NOT NULL, holder TEXT NOT NULL,
                agency TEXT NOT NULL DEFAULT '', account_last_digits TEXT NOT NULL DEFAULT '',
                opening_balance_cents BIGINT NOT NULL DEFAULT 0,
                opening_date DATE NOT NULL, active {boolean} NOT NULL DEFAULT TRUE,
                notes TEXT NOT NULL DEFAULT '', created_at {timestamp}, updated_at {timestamp}
            )
        """)
        connection.execute(f"""
            CREATE TABLE IF NOT EXISTS bank_cards (
                id {serial} PRIMARY KEY{id_tail}, owner_key TEXT NOT NULL,
                issuer TEXT NOT NULL, card_name TEXT NOT NULL, brand TEXT NOT NULL,
                last_four TEXT NOT NULL, holder TEXT NOT NULL,
                credit_limit_cents BIGINT NOT NULL DEFAULT 0,
                closing_day INTEGER NOT NULL, due_day INTEGER NOT NULL,
                payment_account_id BIGINT REFERENCES bank_accounts(id) ON DELETE SET NULL,
                visual_label TEXT NOT NULL DEFAULT '', active {boolean} NOT NULL DEFAULT TRUE,
                created_at {timestamp}, updated_at {timestamp}
            )
        """)
        connection.execute(f"""
            CREATE TABLE IF NOT EXISTS bank_categories (
                id {serial} PRIMARY KEY{id_tail}, owner_key TEXT NOT NULL,
                category_type TEXT NOT NULL CHECK (category_type IN ('INCOME','EXPENSE')),
                name TEXT NOT NULL, parent_id BIGINT REFERENCES bank_categories(id) ON DELETE SET NULL,
                active {boolean} NOT NULL DEFAULT TRUE, created_at {timestamp}, updated_at {timestamp},
                UNIQUE(owner_key, category_type, name)
            )
        """)
        connection.execute(f"""
            CREATE TABLE IF NOT EXISTS bank_transactions (
                id {serial} PRIMARY KEY{id_tail}, owner_key TEXT NOT NULL,
                transaction_date DATE NOT NULL,
                transaction_type TEXT NOT NULL CHECK (transaction_type IN ('INCOME','EXPENSE','TRANSFER')),
                description TEXT NOT NULL, counterparty TEXT NOT NULL DEFAULT '',
                category_id BIGINT REFERENCES bank_categories(id) ON DELETE SET NULL,
                amount_cents BIGINT NOT NULL CHECK (amount_cents > 0),
                payment_method TEXT NOT NULL DEFAULT '',
                account_id BIGINT REFERENCES bank_accounts(id) ON DELETE SET NULL,
                destination_account_id BIGINT REFERENCES bank_accounts(id) ON DELETE SET NULL,
                card_id BIGINT REFERENCES bank_cards(id) ON DELETE SET NULL,
                reference_month TEXT NOT NULL, source_type TEXT NOT NULL DEFAULT 'manual',
                external_id TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '',
                created_at {timestamp}, updated_at {timestamp}
            )
        """)
        if _postgres():
            connection.execute("ALTER TABLE bank_transactions ADD COLUMN IF NOT EXISTS source_type TEXT NOT NULL DEFAULT 'manual'")
            connection.execute("ALTER TABLE bank_transactions ADD COLUMN IF NOT EXISTS external_id TEXT NOT NULL DEFAULT ''")
        else:
            columns = {row[1] for row in connection.execute("PRAGMA table_info(bank_transactions)").fetchall()}
            if "source_type" not in columns:
                connection.execute("ALTER TABLE bank_transactions ADD COLUMN source_type TEXT NOT NULL DEFAULT 'manual'")
            if "external_id" not in columns:
                connection.execute("ALTER TABLE bank_transactions ADD COLUMN external_id TEXT NOT NULL DEFAULT ''")
        connection.execute("CREATE INDEX IF NOT EXISTS idx_bank_tx_owner_date ON bank_transactions(owner_key, transaction_date, id)")
        connection.execute("CREATE INDEX IF NOT EXISTS idx_bank_tx_owner_month ON bank_transactions(owner_key, reference_month, transaction_type)")


def _execute_insert(connection, sql: str, params: tuple) -> int:
    if _postgres():
        return int(connection.execute(sql + " RETURNING id", params).fetchone()[0])
    return int(connection.execute(sql, params).lastrowid)


def seed_categories(owner_key: str) -> None:
    ensure_banking_db()
    now = _now()
    with _connection() as connection:
        for category_type, names in (("INCOME", DEFAULT_INCOME_CATEGORIES), ("EXPENSE", DEFAULT_EXPENSE_CATEGORIES)):
            for name in names:
                if _postgres():
                    connection.execute(
                        "INSERT INTO bank_categories(owner_key,category_type,name,created_at,updated_at) VALUES(%s,%s,%s,NOW(),NOW()) ON CONFLICT(owner_key,category_type,name) DO NOTHING",
                        (owner_key, category_type, name),
                    )
                else:
                    connection.execute(
                        "INSERT OR IGNORE INTO bank_categories(owner_key,category_type,name,created_at,updated_at) VALUES(?,?,?,?,?)",
                        (owner_key, category_type, name, now, now),
                    )


def _rows(sql: str, params: tuple = ()) -> list[dict[str, Any]]:
    with _connection() as connection:
        cursor = connection.execute(sql, params)
        columns = [item[0] for item in cursor.description]
        return [dict(zip(columns, row)) for row in cursor.fetchall()]


def _params(count: int) -> str:
    return ",".join(["%s" if _postgres() else "?"] * count)


def _require_owned(connection, table: str, record_id: int | None, owner_key: str, label: str) -> None:
    if record_id is None:
        return
    p = "%s" if _postgres() else "?"
    row = connection.execute(
        f"SELECT 1 FROM {table} WHERE id={p} AND owner_key={p}",
        (record_id, owner_key),
    ).fetchone()
    if row is None:
        raise ValueError(f"{label} não pertence ao usuário autenticado.")


def save_account(owner_key: str, payload: dict, account_id: int | None = None) -> int:
    ensure_banking_db()
    values = (
        _required(payload, "bank_name", "o banco"),
        _required(payload, "description", "a descrição da conta"),
        _required(payload, "account_type", "o tipo da conta", 60),
        _required(payload, "holder", "o titular"),
        str(payload.get("agency", "")).strip()[:20],
        str(payload.get("account_last_digits", "")).strip()[-8:],
        _money_cents(payload.get("opening_balance", "0"), allow_zero=True),
        _date(payload.get("opening_date"), "a data do saldo inicial"),
        bool(payload.get("active", True)),
        str(payload.get("notes", "")).strip()[:1000],
    )
    now = _now()
    with _connection() as connection:
        if account_id is None:
            p = _params(13)
            return _execute_insert(connection, f"INSERT INTO bank_accounts(owner_key,bank_name,description,account_type,holder,agency,account_last_digits,opening_balance_cents,opening_date,active,notes,created_at,updated_at) VALUES({p})", (owner_key, *values, now, now))
        p = "%s" if _postgres() else "?"
        cursor = connection.execute(f"UPDATE bank_accounts SET bank_name={p},description={p},account_type={p},holder={p},agency={p},account_last_digits={p},opening_balance_cents={p},opening_date={p},active={p},notes={p},updated_at={p} WHERE id={p} AND owner_key={p}", (*values, now, account_id, owner_key))
        if cursor.rowcount == 0:
            raise LookupError("Conta não encontrada.")
        return account_id


def save_card(owner_key: str, payload: dict, card_id: int | None = None) -> int:
    ensure_banking_db()
    last_four = str(payload.get("last_four", "")).strip()
    if len(last_four) != 4 or not last_four.isdigit():
        raise ValueError("Informe somente os quatro últimos dígitos do cartão.")
    closing_day, due_day = int(payload.get("closing_day", 0)), int(payload.get("due_day", 0))
    if not 1 <= closing_day <= 31 or not 1 <= due_day <= 31:
        raise ValueError("Fechamento e vencimento devem estar entre 1 e 31.")
    account_id = int(payload["payment_account_id"]) if payload.get("payment_account_id") else None
    values = (_required(payload, "issuer", "o banco ou emissor"), _required(payload, "card_name", "o nome do cartão"), _required(payload, "brand", "a bandeira", 40), last_four, _required(payload, "holder", "o titular"), _money_cents(payload.get("credit_limit", "0"), allow_zero=True), closing_day, due_day, account_id, str(payload.get("visual_label", "")).strip()[:80], bool(payload.get("active", True)))
    now = _now()
    with _connection() as connection:
        _require_owned(connection, "bank_accounts", account_id, owner_key, "A conta")
        if card_id is None:
            return _execute_insert(connection, f"INSERT INTO bank_cards(owner_key,issuer,card_name,brand,last_four,holder,credit_limit_cents,closing_day,due_day,payment_account_id,visual_label,active,created_at,updated_at) VALUES({_params(14)})", (owner_key, *values, now, now))
        p = "%s" if _postgres() else "?"
        cursor = connection.execute(f"UPDATE bank_cards SET issuer={p},card_name={p},brand={p},last_four={p},holder={p},credit_limit_cents={p},closing_day={p},due_day={p},payment_account_id={p},visual_label={p},active={p},updated_at={p} WHERE id={p} AND owner_key={p}", (*values, now, card_id, owner_key))
        if cursor.rowcount == 0: raise LookupError("Cartão não encontrado.")
        return card_id


def save_category(owner_key: str, payload: dict, category_id: int | None = None) -> int:
    ensure_banking_db()
    category_type = str(payload.get("category_type", "")).upper()
    if category_type not in {"INCOME", "EXPENSE"}: raise ValueError("Selecione Entrada ou Saída.")
    name = _required(payload, "name", "o nome da categoria", 80)
    parent_id = int(payload["parent_id"]) if payload.get("parent_id") else None
    now = _now()
    with _connection() as connection:
        _require_owned(connection, "bank_categories", parent_id, owner_key, "A categoria principal")
        if category_id is None:
            try:
                return _execute_insert(connection, f"INSERT INTO bank_categories(owner_key,category_type,name,parent_id,active,created_at,updated_at) VALUES({_params(7)})", (owner_key, category_type, name, parent_id, True, now, now))
            except Exception as exc:
                raise ValueError("Esta categoria já está cadastrada.") from exc
        p = "%s" if _postgres() else "?"
        cursor = connection.execute(f"UPDATE bank_categories SET category_type={p},name={p},parent_id={p},updated_at={p} WHERE id={p} AND owner_key={p}", (category_type, name, parent_id, now, category_id, owner_key))
        if cursor.rowcount == 0: raise LookupError("Categoria não encontrada.")
        return category_id


def save_transaction(owner_key: str, payload: dict, transaction_id: int | None = None) -> int:
    ensure_banking_db()
    transaction_type = str(payload.get("transaction_type", "")).upper()
    if transaction_type not in TRANSACTION_TYPES: raise ValueError("Selecione Entrada, Saída ou Transferência.")
    account_id = int(payload["account_id"]) if payload.get("account_id") else None
    destination_id = int(payload["destination_account_id"]) if payload.get("destination_account_id") else None
    card_id = int(payload["card_id"]) if payload.get("card_id") else None
    category_id = int(payload["category_id"]) if payload.get("category_id") else None
    if not account_id:
        raise ValueError("Toda movimentação deve estar vinculada a uma conta bancária.")
    if transaction_type == "TRANSFER" and (not destination_id or account_id == destination_id):
        raise ValueError("Selecione contas de origem e destino diferentes.")
    transaction_date = _date(payload.get("transaction_date"))
    reference_month = str(payload.get("reference_month", "")).strip()
    try: datetime.strptime(reference_month, "%Y-%m")
    except ValueError as exc: raise ValueError("Informe o mês de referência.") from exc
    source_type = str(payload.get("source_type", "manual")).strip().lower()
    if source_type not in {"manual", "statement", "receipt", "invoice", "other"}:
        raise ValueError("Origem da movimentação inválida.")
    values = (transaction_date, transaction_type, _required(payload, "description", "a descrição"), str(payload.get("counterparty", "")).strip()[:140], category_id, _money_cents(payload.get("amount")), str(payload.get("payment_method", "")).strip()[:60], account_id, destination_id, card_id, reference_month, source_type, str(payload.get("external_id", "")).strip()[:120], str(payload.get("notes", "")).strip()[:1000])
    now = _now()
    with _connection() as connection:
        _require_owned(connection, "bank_accounts", account_id, owner_key, "A conta")
        _require_owned(connection, "bank_accounts", destination_id, owner_key, "A conta de destino")
        _require_owned(connection, "bank_cards", card_id, owner_key, "O cartão")
        _require_owned(connection, "bank_categories", category_id, owner_key, "A categoria")
        if transaction_id is None:
            return _execute_insert(connection, f"INSERT INTO bank_transactions(owner_key,transaction_date,transaction_type,description,counterparty,category_id,amount_cents,payment_method,account_id,destination_account_id,card_id,reference_month,source_type,external_id,notes,created_at,updated_at) VALUES({_params(17)})", (owner_key, *values, now, now))
        p = "%s" if _postgres() else "?"
        cursor = connection.execute(f"UPDATE bank_transactions SET transaction_date={p},transaction_type={p},description={p},counterparty={p},category_id={p},amount_cents={p},payment_method={p},account_id={p},destination_account_id={p},card_id={p},reference_month={p},source_type={p},external_id={p},notes={p},updated_at={p} WHERE id={p} AND owner_key={p}", (*values, now, transaction_id, owner_key))
        if cursor.rowcount == 0: raise LookupError("Movimentação não encontrada.")
        return transaction_id


def delete_record(owner_key: str, resource: str, record_id: int) -> bool:
    table = {"accounts": "bank_accounts", "cards": "bank_cards", "categories": "bank_categories", "transactions": "bank_transactions"}.get(resource)
    if not table: raise ValueError("Recurso bancário inválido.")
    p = "%s" if _postgres() else "?"
    with _connection() as connection:
        try:
            return connection.execute(f"DELETE FROM {table} WHERE id={p} AND owner_key={p}", (record_id, owner_key)).rowcount > 0
        except Exception as exc:
            raise ValueError("O registro está em uso. Inative-o ou remova os vínculos primeiro.") from exc


def import_transactions(owner_key: str, payload: dict[str, Any]) -> dict[str, Any]:
    account_id = int(payload.get("account_id") or 0)
    source_type = str(payload.get("document_kind", "statement"))
    items = payload.get("items")
    if not account_id or not isinstance(items, list) or not items:
        raise ValueError("Selecione a conta e ao menos uma movimentação.")
    seed_categories(owner_key)
    saved = skipped = 0
    p = "%s" if _postgres() else "?"
    with _connection() as connection:
        _require_owned(connection, "bank_accounts", account_id, owner_key, "A conta")
    for raw in items:
        if not isinstance(raw, dict) or raw.get("selected") is False:
            continue
        transaction_type = str(raw.get("transaction_type", "")).upper()
        category_id = None
        if transaction_type in {"INCOME", "EXPENSE"}:
            category = _rows(
                f"SELECT id FROM bank_categories WHERE owner_key={p} AND category_type={p} AND LOWER(name)=LOWER({p}) LIMIT 1",
                (owner_key, transaction_type, str(raw.get("category_hint", "Outros"))),
            )
            category_id = int(category[0]["id"]) if category else None
        external_id = str(raw.get("external_id", "")).strip()[:120]
        tx_date = _date(raw.get("transaction_date"))
        amount_cents = _money_cents(raw.get("amount"))
        description = _required(raw, "description", "a descrição")
        duplicate = _rows(
            f"SELECT id FROM bank_transactions WHERE owner_key={p} AND account_id={p} AND ((external_id<>'' AND external_id={p}) OR (transaction_date={p} AND amount_cents={p} AND LOWER(description)=LOWER({p}))) LIMIT 1",
            (owner_key, account_id, external_id, tx_date, amount_cents, description),
        )
        if duplicate:
            skipped += 1
            continue
        save_transaction(owner_key, {
            **raw,
            "account_id": account_id,
            "category_id": category_id,
            "source_type": source_type,
            "external_id": external_id,
            "notes": f"Importado de {payload.get('filename', 'arquivo')}. Linha original: {str(raw.get('source_line', ''))[:500]}",
        })
        saved += 1
    return {"ok": True, "saved": saved, "duplicates_skipped": skipped}


def banking_payload(
    owner_key: str,
    reference_month: str | None = None,
    search: str = "",
    account_id: int | None = None,
) -> dict:
    seed_categories(owner_key)
    month = reference_month or date.today().strftime("%Y-%m")
    try: period = datetime.strptime(month, "%Y-%m")
    except ValueError as exc: raise ValueError("Período inválido.") from exc
    next_month = date(period.year + (1 if period.month == 12 else 0), 1 if period.month == 12 else period.month + 1, 1).isoformat()
    p = "%s" if _postgres() else "?"
    accounts = _rows(f"SELECT id,bank_name,description,account_type,holder,agency,account_last_digits,opening_balance_cents,opening_date,active,notes FROM bank_accounts WHERE owner_key={p} ORDER BY active DESC,bank_name,description", (owner_key,))
    account_ids = {int(item["id"]) for item in accounts}
    if account_id is not None and account_id not in account_ids:
        raise ValueError("A conta selecionada não pertence ao usuário autenticado.")
    cards = _rows(f"SELECT c.id,c.issuer,c.card_name,c.brand,c.last_four,c.holder,c.credit_limit_cents,c.closing_day,c.due_day,c.payment_account_id,c.visual_label,c.active,a.bank_name AS payment_bank_name,a.description AS payment_account_name FROM bank_cards c LEFT JOIN bank_accounts a ON a.id=c.payment_account_id WHERE c.owner_key={p} ORDER BY c.active DESC,c.issuer,c.card_name", (owner_key,))
    categories = _rows(f"SELECT id,category_type,name,parent_id,active FROM bank_categories WHERE owner_key={p} ORDER BY category_type,name", (owner_key,))
    params: list[Any] = [owner_key, month]
    where = f"t.owner_key={p} AND t.reference_month={p}"
    if account_id is not None:
        where += f" AND (t.account_id={p} OR (t.transaction_type='TRANSFER' AND t.destination_account_id={p}))"
        params.extend([account_id, account_id])
    if search.strip():
        like = f"%{search.strip()}%"
        where += f" AND (LOWER(t.description) LIKE LOWER({p}) OR LOWER(t.counterparty) LIKE LOWER({p}) OR LOWER(COALESCE(c.name,'')) LIKE LOWER({p}))"
        params.extend([like, like, like])
    transactions = _rows(f"""SELECT t.id,t.transaction_date,t.transaction_type,t.description,t.counterparty,t.category_id,c.name AS category_name,t.amount_cents,t.payment_method,t.account_id,a.bank_name AS bank_name,a.description AS account_name,t.destination_account_id,d.bank_name AS destination_bank_name,d.description AS destination_account_name,t.card_id,k.card_name,t.reference_month,t.source_type,t.external_id,t.notes FROM bank_transactions t LEFT JOIN bank_categories c ON c.id=t.category_id LEFT JOIN bank_accounts a ON a.id=t.account_id LEFT JOIN bank_accounts d ON d.id=t.destination_account_id LEFT JOIN bank_cards k ON k.id=t.card_id WHERE {where} ORDER BY t.transaction_date DESC,t.id DESC""", tuple(params))
    income = sum(int(item["amount_cents"]) for item in transactions if item["transaction_type"] == "INCOME")
    expenses = sum(int(item["amount_cents"]) for item in transactions if item["transaction_type"] == "EXPENSE")
    transfer_in = sum(int(item["amount_cents"]) for item in transactions if item["transaction_type"] == "TRANSFER" and account_id is not None and int(item["destination_account_id"]) == account_id)
    transfer_out = sum(int(item["amount_cents"]) for item in transactions if item["transaction_type"] == "TRANSFER" and account_id is not None and int(item["account_id"]) == account_id)
    balance_rows = _rows(
        f"SELECT transaction_type,account_id,destination_account_id,amount_cents FROM bank_transactions WHERE owner_key={p} AND transaction_date < {p}",
        (owner_key, next_month),
    )
    balances = {int(item["id"]): int(item["opening_balance_cents"]) for item in accounts}
    for item in balance_rows:
        amount = int(item["amount_cents"])
        source = int(item["account_id"])
        if item["transaction_type"] == "INCOME":
            balances[source] += amount
        elif item["transaction_type"] == "EXPENSE":
            balances[source] -= amount
        else:
            balances[source] -= amount
            balances[int(item["destination_account_id"])] += amount
    account_summaries = []
    for account in accounts:
        balance = balances[int(account["id"])]
        account["available_balance_text"] = _money_text(balance)
        account_summaries.append({
            "account_id": account["id"],
            "bank_name": account["bank_name"],
            "account_name": account["description"],
            "available_balance_text": _money_text(balance),
        })
    visible_accounts = accounts if account_id is None else [item for item in accounts if int(item["id"]) == account_id]
    opening = sum(balances[int(item["id"])] for item in visible_accounts)
    for item in transactions:
        item["transfer_identifier"] = f"TRANSFER-{item['id']}" if item["transaction_type"] == "TRANSFER" else None
        if item["transaction_type"] == "TRANSFER" and account_id is not None:
            item["transfer_direction"] = "IN" if int(item["destination_account_id"]) == account_id else "OUT"
    for collection, keys in ((accounts, ("opening_balance_cents",)), (cards, ("credit_limit_cents",)), (transactions, ("amount_cents",))):
        for item in collection:
            for key in keys: item[key.replace("_cents", "_text")] = _money_text(int(item[key]))
    selected_account = next((item for item in accounts if int(item["id"]) == account_id), None)
    return {"ok": True, "reference_month": month, "selected_account_id": account_id, "selected_account": selected_account, "view_mode": "individual" if account_id is not None else "consolidated", "summary": {"income_text": _money_text(income), "expenses_text": _money_text(expenses), "transfer_in_text": _money_text(transfer_in), "transfer_out_text": _money_text(transfer_out), "result_text": _money_text(income - expenses), "account_period_result_text": _money_text(income - expenses + transfer_in - transfer_out), "available_balance_text": _money_text(opening), "commitment_percent": float(Decimal(expenses * 100) / income) if income else 0.0, "remaining_percent": float(Decimal((income - expenses) * 100) / income) if income else 0.0}, "account_summaries": account_summaries, "accounts": accounts, "cards": cards, "categories": categories, "transactions": transactions}
