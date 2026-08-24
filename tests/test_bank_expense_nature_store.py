import pytest

import bank_expense_nature_store as store


def _local_db(monkeypatch, tmp_path):
    monkeypatch.setattr(store.main_module, "INVESTMENT_DB_PATH", tmp_path / "natures.db")
    monkeypatch.setattr(store.main_module, "INVESTMENT_DATA_DIR", tmp_path)
    monkeypatch.setattr(store.main_module, "use_postgres_investment_db", lambda: False)


def test_nature_crud_and_automatic_code(monkeypatch, tmp_path):
    _local_db(monkeypatch, tmp_path)
    first = store.create_nature("owner", {"name": "Educação"})
    second = store.create_nature("owner", {"name": "Saúde"})
    assert first["code"] == 1
    assert second["code"] == 2
    assert store.next_code("owner") == 3
    assert [item["name"] for item in store.list_natures("owner")] == ["Educação", "Saúde"]

    assert store.update_nature("owner", second["id"], {"name": "Feira"})
    assert store.list_natures("owner")[1]["name"] == "Feira"
    assert store.delete_nature("owner", first["id"])
    assert [item["code"] for item in store.list_natures("owner")] == [2]
    assert store.create_nature("owner", {"name": "Transporte"})["code"] == 3


def test_nature_name_is_required_and_unique_for_active_rows(monkeypatch, tmp_path):
    _local_db(monkeypatch, tmp_path)
    with pytest.raises(ValueError):
        store.create_nature("owner", {"name": " "})
    item = store.create_nature("owner", {"name": "Saúde"})
    with pytest.raises(ValueError):
        store.create_nature("owner", {"name": "saúde"})
    assert store.delete_nature("owner", item["id"])
    assert store.create_nature("owner", {"name": "Saúde"})["code"] == 2
