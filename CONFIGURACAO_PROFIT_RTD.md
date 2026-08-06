# Configuração Profit Pro → RTD → Excel → Monitor Global

## Pré-requisitos

- Windows, Profit Pro e Microsoft Excel instalados.
- Profit e Excel executados com o mesmo nível de permissão. Não execute um como administrador e o outro como usuário comum.
- Pasta `integrations/profit_rtd/profit_market_data.xlsx` aberta no Excel.

## Configuração passo a passo

1. Abra o Profit Pro e aguarde a conexão com a corretora.
2. Abra **Ferramentas → Grade de Cotações** (o nome pode variar conforme a versão).
3. Adicione WIN vigente, WDO vigente, IBOV, PETR4 e VALE3.
4. Confirme no Profit o código completo dos contratos vigentes de WIN e WDO.
5. Na Grade, use a opção de **Exportação em tempo real**.
6. Selecione **Microsoft Excel** e **RTD**. Não selecione LibreOffice.
7. Para cada campo, copie a fórmula que o próprio Profit gerar. As fórmulas podem variar por versão, corretora, ativo e campo.
8. Abra `profit_market_data.xlsx`, aba `MARKET_DATA`, e cole as fórmulas RTD nas células da linha correspondente. Preserve a coluna `ticker` como alias estável (`WIN` ou `WDO`) e registre o contrato real em `CONFIG`.
9. Salve a pasta de trabalho sem alterar o nome ou caminho. Não é necessário VBA.
10. Mantenha Profit, Excel e o serviço Python abertos simultaneamente.

## Verificação

1. Observe se os valores mudam na aba `MARKET_DATA` durante o pregão.
2. Confira se `horário recebido` acompanha as atualizações.
3. Abra o módulo **Monitor Global** e clique em **Verificar integração Profit**.
4. O diagnóstico deve mostrar Profit, Excel e arquivo como detectados.

## Diagnóstico de erros

- `#N/A`, `#VALOR!` ou `#VALUE!`: recrie a fórmula pelo Profit e confirme o ticker/bolsa.
- Valor parado: confirme a conexão do Profit, a sessão de mercado e o cálculo automático do Excel.
- Excel fechado: abra a pasta no Excel desktop; a leitura direta do arquivo salvo não captura RTD ao vivo.
- Arquivo não localizado: configure `PROFIT_RTD_WORKBOOK` com o caminho absoluto.
- Conector COM ausente: execute `python -m pip install -r requirements.txt`.

## Iniciar o sistema

```powershell
python -m pip install -r requirements.txt
python -m uvicorn web_app:app --host 127.0.0.1 --port 8000
```

A API local permanece vinculada a `127.0.0.1`. O módulo é informativo, não controla o Profit e não envia ordens.
