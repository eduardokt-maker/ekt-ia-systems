import statement_outflows


class _Page:
    def __init__(self, text):
        self._text = text

    def extract_text(self):
        return self._text


class _Reader:
    pages = [
        _Page(""),
        _Page("""Conta Corrente
Movimentação
Data Descrição Nº Documento Movimento (R$) Saldo (R$)
01/07 PIX ENVIADO Maria da Silva 654321 100,00-
PIX RECEBIDO
Empresa Teste
- 500,00
DEBITO VISA ELECTRON BRASIL
01/07 MERCADO TESTE
123456 25,50-
IOF ADICIONAL - AUTOMATICO
PERIODO: 01/06 A 30/06/26
- 4,50- 130,00-
Saldos por Período"""),
    ]


def test_extracts_only_outflows_without_duplicate_sections(monkeypatch):
    monkeypatch.setattr(statement_outflows, "PdfReader", lambda _: _Reader())
    entries = statement_outflows.parse_santander_outflows(
        b"%PDF", "extrato.pdf", 7
    )
    assert [item["type"] for item in entries] == [
        "Pix enviado", "Cartão de débito", "IOF"
    ]
    assert entries[0]["destination"] == "Maria da Silva 654321"
    assert entries[0]["document"] == "654321"
    assert statement_outflows.summarize_outflows(entries)["total"] == 130.0
