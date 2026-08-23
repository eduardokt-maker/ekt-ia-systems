from datetime import datetime, timezone

import bank_directory


def _official_csv(total=101):
    header = (
        "ISPB,Nome_Reduzido,Número_Código,Participa_da_Compe,"
        "Acesso_Principal,Nome_Extenso,Início_da_Operação\n"
    )
    rows = [
        f"{index:08d},BANCO {index},{index % 1000:03d},Sim,RSFN,"
        f"Banco Oficial {index} S.A.,22/04/2002"
        for index in range(total)
    ]
    return (header + "\n".join(rows)).encode("utf-8")


def test_downloads_official_directory_and_keeps_local_cache(tmp_path, monkeypatch):
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.setattr(bank_directory.main_module, "INVESTMENT_DATA_DIR", tmp_path)
    monkeypatch.setattr(
        bank_directory.main_module, "INVESTMENT_DB_PATH", tmp_path / "banks.db"
    )
    monkeypatch.setattr(bank_directory, "_download_official_csv", _official_csv)

    result = bank_directory.sync_bank_directory(force=True)
    assert result["updated"] is True
    assert result["count"] == 101
    assert bank_directory.list_banks()[1]["bank_code"] == "001"

    monkeypatch.setattr(
        bank_directory,
        "_download_official_csv",
        lambda: (_ for _ in ()).throw(AssertionError("não deveria baixar novamente")),
    )
    cached = bank_directory.sync_bank_directory()
    assert cached == {"updated": False, "count": 101}
