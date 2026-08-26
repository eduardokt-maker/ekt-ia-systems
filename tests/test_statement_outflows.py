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
def test_parse_santander_pix_receipt_text():
    text = """Comprovante do Pix
24/08/2026 - 17:53:46
Valor pago
R$ 1.000,00
Forma de pagamento
Ag 02968 Cc 2018924-1
Dados do recebedor
Para
DESTINATARIO TESTE
CPF
***.477.144-**
Dados do pagador
De
PAGADOR TESTE
ID/Transação
E9040088820260824205368445650491
Data e hora da transação
24/08/2026 - 17:53:46
Código de autenticação
A89AB73C24716D3C2768027
"""

    entries = statement_outflows._parse_santander_pix_receipt_text(
        text, "comprovante.pdf", 42
    )

    assert len(entries) == 1
    assert entries[0]["file_id"] == 42
    assert entries[0]["transaction_date"] == "24/08"
    assert entries[0]["type"] == "Pix enviado"
    assert entries[0]["destination"] == "DESTINATARIO TESTE"
    assert entries[0]["document"] == "E9040088820260824205368445650491"
    assert entries[0]["amount"] == 1000.0
    assert "Ag 02968 Cc 2018924-1" in entries[0]["notes"]


def test_parse_c6_pix_receipt_ocr_with_wrapped_transaction_id():
    text = """C6 BANK
Pix em andamento
24/08/2026 10:06
Pix realizado!
24/08/2026 10:06
ET
DESTINATARIO TESTE
Banco: 260 - NU PAGAMENTOS - IP
Agência: ****1
Conta: *****4-7
Código de autenticação
AUTENTICACAO123
ID da transação
E31872495202608241305G44flez8
Ye8
Chave
86714cb1-ced6-465b-b4c9-5edd03ba2f5b
CPF / CNPJ
***.477.144-**
Valor
R$ 21,00
Data e hora da transação
segunda-feira, 24 de agosto de 2026, 10:06
Conta de origem
ET
PAGADOR TESTE
Banco: 336 - Banco C6 S.A.
Agência: ****1
Conta: *****6-6
"""

    entries = statement_outflows.parse_c6_pix_receipt_text(
        text, "comprovante.jpeg", 81
    )

    assert len(entries) == 1
    assert entries[0]["transaction_date"] == "24/08"
    assert entries[0]["destination"] == "DESTINATARIO TESTE"
    assert entries[0]["document"] == "E31872495202608241305G44flez8Ye8"
    assert entries[0]["amount"] == 21.0
    assert "Banco C6" in entries[0]["notes"]
