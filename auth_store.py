import base64
import hashlib
import hmac
import os
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone

import main as main_module


ROLES = {"admin", "operator", "viewer"}
ROLE_LABELS = {
    "admin": "Administrador",
    "operator": "Operador",
    "viewer": "Consulta",
}
ROLE_PERMISSIONS = {
    "admin": ["read", "write", "manage_users"],
    "operator": ["read", "write"],
    "viewer": ["read"],
}
SCRYPT_N = 2**14
SCRYPT_R = 8
SCRYPT_P = 1


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


@contextmanager
def _sqlite_connection():
    main_module.INVESTMENT_DATA_DIR.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(main_module.INVESTMENT_DB_PATH)
    connection.row_factory = sqlite3.Row
    try:
        yield connection
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def _connection():
    if main_module.use_postgres_investment_db():
        return main_module.investment_db_connection()
    return _sqlite_connection()


def _placeholder() -> str:
    return "%s" if main_module.use_postgres_investment_db() else "?"


def ensure_auth_db() -> None:
    postgres = main_module.use_postgres_investment_db()
    primary_key = "BIGSERIAL PRIMARY KEY" if postgres else "INTEGER PRIMARY KEY AUTOINCREMENT"
    boolean_type = "BOOLEAN" if postgres else "INTEGER"
    with _connection() as connection:
        connection.execute(
            f"""
            CREATE TABLE IF NOT EXISTS app_users (
                id {primary_key},
                login TEXT NOT NULL UNIQUE,
                display_name TEXT NOT NULL,
                password_hash TEXT NOT NULL,
                role TEXT NOT NULL,
                active {boolean_type} NOT NULL DEFAULT TRUE,
                token_version INTEGER NOT NULL DEFAULT 1,
                last_login_at TEXT,
                password_changed_at TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        connection.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS app_users_login_lower_idx ON app_users (LOWER(login))"
        )


def _hash_password(password: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.scrypt(
        password.encode("utf-8"), salt=salt, n=SCRYPT_N, r=SCRYPT_R, p=SCRYPT_P
    )
    return "$".join(
        (
            "scrypt",
            str(SCRYPT_N),
            str(SCRYPT_R),
            str(SCRYPT_P),
            base64.urlsafe_b64encode(salt).decode("ascii"),
            base64.urlsafe_b64encode(digest).decode("ascii"),
        )
    )


def _verify_password(password: str, encoded: str) -> bool:
    try:
        algorithm, n, r, p, salt_value, expected_value = encoded.split("$", 5)
        if algorithm != "scrypt":
            return False
        salt = base64.urlsafe_b64decode(salt_value)
        expected = base64.urlsafe_b64decode(expected_value)
        supplied = hashlib.scrypt(
            password.encode("utf-8"),
            salt=salt,
            n=int(n),
            r=int(r),
            p=int(p),
            dklen=len(expected),
        )
        return hmac.compare_digest(supplied, expected)
    except (ValueError, TypeError):
        return False


def _public_user(row) -> dict:
    if row is None:
        return {}
    values = dict(row) if hasattr(row, "keys") else row
    return {
        "id": int(values["id"]),
        "login": str(values["login"]),
        "display_name": str(values["display_name"]),
        "role": str(values["role"]),
        "role_label": ROLE_LABELS.get(str(values["role"]), str(values["role"])),
        "permissions": ROLE_PERMISSIONS.get(str(values["role"]), ["read"]),
        "active": bool(values["active"]),
        "token_version": int(values["token_version"]),
        "last_login_at": values.get("last_login_at") if isinstance(values, dict) else values["last_login_at"],
        "password_changed_at": str(values["password_changed_at"]),
        "created_at": str(values["created_at"]),
    }


def _fetch_user(login: str = "", user_id: int | None = None, include_hash: bool = False):
    ensure_auth_db()
    fields = "id, login, display_name, role, active, token_version, last_login_at, password_changed_at, created_at"
    if include_hash:
        fields += ", password_hash"
    placeholder = _placeholder()
    if user_id is not None:
        clause, value = f"id = {placeholder}", user_id
    else:
        clause, value = f"LOWER(login) = LOWER({placeholder})", login.strip()
    with _connection() as connection:
        cursor = connection.execute(f"SELECT {fields} FROM app_users WHERE {clause}", (value,))
        row = cursor.fetchone()
        if row is None:
            return None
        columns = [item.name if hasattr(item, "name") else item[0] for item in cursor.description]
        return dict(zip(columns, row)) if not hasattr(row, "keys") else dict(row)


def user_count() -> int:
    ensure_auth_db()
    with _connection() as connection:
        return int(connection.execute("SELECT COUNT(*) FROM app_users").fetchone()[0])


def bootstrap_legacy_admin(login: str, password: str) -> dict | None:
    if user_count() != 0 or not main_module.validate_investments_credentials(login, password):
        return None
    return create_user(login, login.strip() or "Administrador", password, "admin", allow_first=True)


def authenticate(login: str, password: str) -> dict | None:
    row = _fetch_user(login=login, include_hash=True)
    if row is None or not bool(row["active"]) or not _verify_password(password, row["password_hash"]):
        return None
    placeholder = _placeholder()
    last_login = _now()
    with _connection() as connection:
        connection.execute(
            f"UPDATE app_users SET last_login_at = {placeholder}, updated_at = {placeholder} WHERE id = {placeholder}",
            (last_login, last_login, row["id"]),
        )
    row["last_login_at"] = last_login
    return _public_user(row)


def get_user(user_id: int) -> dict | None:
    row = _fetch_user(user_id=user_id)
    return _public_user(row) if row else None


def list_users() -> list[dict]:
    ensure_auth_db()
    with _connection() as connection:
        cursor = connection.execute(
            "SELECT id, login, display_name, role, active, token_version, last_login_at, password_changed_at, created_at FROM app_users ORDER BY active DESC, display_name, login"
        )
        columns = [item.name if hasattr(item, "name") else item[0] for item in cursor.description]
        return [_public_user(dict(zip(columns, row))) for row in cursor.fetchall()]


def _validate_password(password: str) -> None:
    if len(password) < 12:
        raise ValueError("A senha deve possuir pelo menos 12 caracteres.")
    if len(password) > 128:
        raise ValueError("A senha deve possuir no máximo 128 caracteres.")


def create_user(login: str, display_name: str, password: str, role: str, allow_first: bool = False) -> dict:
    ensure_auth_db()
    login = login.strip().casefold()
    display_name = display_name.strip()
    role = role.strip().lower()
    if len(login) < 3 or len(login) > 120:
        raise ValueError("O login deve possuir entre 3 e 120 caracteres.")
    if not display_name:
        raise ValueError("Informe o nome do usuário.")
    if role not in ROLES:
        raise ValueError("Perfil de usuário inválido.")
    if not allow_first:
        _validate_password(password)
    now = _now()
    placeholder = _placeholder()
    try:
        with _connection() as connection:
            cursor = connection.execute(
                f"INSERT INTO app_users (login, display_name, password_hash, role, active, token_version, password_changed_at, created_at, updated_at) VALUES ({placeholder}, {placeholder}, {placeholder}, {placeholder}, {placeholder}, 1, {placeholder}, {placeholder}, {placeholder}) RETURNING id",
                (login, display_name, _hash_password(password), role, True, now, now, now),
            )
            user_id = int(cursor.fetchone()[0])
    except Exception as exc:
        if "unique" in str(exc).lower() or "duplicate" in str(exc).lower():
            raise ValueError("Este login já está cadastrado.") from exc
        raise
    return get_user(user_id) or {}


def update_user(user_id: int, display_name: str, role: str, active: bool) -> dict:
    current = get_user(user_id)
    if current is None:
        raise LookupError("Usuário não encontrado.")
    display_name = display_name.strip()
    role = role.strip().lower()
    if not display_name:
        raise ValueError("Informe o nome do usuário.")
    if role not in ROLES:
        raise ValueError("Perfil de usuário inválido.")
    placeholder = _placeholder()
    token_increment = 1 if role != current["role"] or bool(active) != current["active"] else 0
    with _connection() as connection:
        connection.execute(
            f"UPDATE app_users SET display_name = {placeholder}, role = {placeholder}, active = {placeholder}, token_version = token_version + {placeholder}, updated_at = {placeholder} WHERE id = {placeholder}",
            (display_name, role, bool(active), token_increment, _now(), user_id),
        )
    return get_user(user_id) or {}


def change_password(user_id: int, current_password: str, new_password: str) -> dict:
    row = _fetch_user(user_id=user_id, include_hash=True)
    if row is None or not bool(row["active"]):
        raise LookupError("Usuário não encontrado.")
    if not _verify_password(current_password, row["password_hash"]):
        raise ValueError("A senha atual está incorreta.")
    _validate_password(new_password)
    if _verify_password(new_password, row["password_hash"]):
        raise ValueError("A nova senha deve ser diferente da senha atual.")
    placeholder = _placeholder()
    now = _now()
    with _connection() as connection:
        connection.execute(
            f"UPDATE app_users SET password_hash = {placeholder}, token_version = token_version + 1, password_changed_at = {placeholder}, updated_at = {placeholder} WHERE id = {placeholder}",
            (_hash_password(new_password), now, now, user_id),
        )
    return get_user(user_id) or {}


def admin_set_password(user_id: int, new_password: str) -> dict:
    if get_user(user_id) is None:
        raise LookupError("Usuário não encontrado.")
    _validate_password(new_password)
    placeholder = _placeholder()
    now = _now()
    with _connection() as connection:
        connection.execute(
            f"UPDATE app_users SET password_hash = {placeholder}, token_version = token_version + 1, password_changed_at = {placeholder}, updated_at = {placeholder} WHERE id = {placeholder}",
            (_hash_password(new_password), now, now, user_id),
        )
    return get_user(user_id) or {}
