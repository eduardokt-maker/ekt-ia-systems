import statement_structure


class _Page:
    def extract_text(self):
        return "\n".join([
            "EXTRATO BANCARIO",
            "Agencia: 1234 Conta corrente: 56789-0",
            "Periodo: 01/08/2026 a 23/08/2026",
            "COMPRA CARTAO DEBITO R$ 45,90",
        ])


class _Reader:
    pages = [_Page()]


def test_extracts_structure_from_bank_pdf(monkeypatch):
    monkeypatch.setattr(statement_structure, "PdfReader", lambda _: _Reader())
    result = statement_structure.analyze_pdf(b"%PDF", "extrato.pdf")
    assert result["document_type"] == "Extrato bancário"
    assert result["page_count"] == 1
    assert "EXTRATO BANCARIO" in result["headings"]
    assert "R$ 45,90" in result["amounts_found"]
    assert "Periodo" in result["field_labels"]
