# Mercado Ibovespa

App em Python/Flet para listar os ativos do Ibovespa, uma selecao de empresas de inteligencia artificial dos EUA, S&P 500, E-mini S&P 500, EWZ, Nikkei 225 e SSE Composite, acompanhando suas cotacoes online.

O projeto usa:

- Python
- Flet para interface mobile/desktop
- brapi e Yahoo Finance para buscar cotacoes online do mercado financeiro brasileiro

## Como rodar no computador

Instale as dependencias:

```powershell
python -m pip install -r requirements.txt
```

Execute o app:

```powershell
flet run main.py
```

Se o comando `flet` nao for reconhecido, use o caminho completo do executavel instalado no Windows:

```powershell
C:\Users\eduar\AppData\Local\Python\pythoncore-3.14-64\Scripts\flet.exe run main.py
```

## Publicar na web com atualizacao automatica

O projeto esta preparado para funcionar como site dinamico Flet no Render.

Arquivos de deploy:

- `web_app.py`: exporta o app ASGI.
- `render.yaml`: configura o servico web.
- `.python-version`: fixa Python 3.12.

Fluxo recomendado:

1. Crie um repositorio no GitHub e envie estes arquivos.
2. No Render, escolha `New > Blueprint`.
3. Conecte o repositorio GitHub.
4. O Render detectara `render.yaml` e criara o servico `ekt-ia-systems`.
5. Compartilhe a URL `https://ekt-ia-systems.onrender.com` gerada pelo Render.

O deploy automatico fica ativo. A cada `git push` para a branch conectada, o Render recompila e publica a nova versao no mesmo link.

## Como usar

Ao abrir, o app carrega automaticamente duas listas:

- Ativos do Ibovespa.
- Ativos de inteligencia artificial do mercado americano.
- S&P 500, E-mini S&P 500 futures, EWZ, Nikkei 225 e SSE Composite da Bolsa de Xangai.
- Principais ativos globais ligados a terras raras, com empresas dos EUA, Australia e Canada.

Cada lista mostra logo da empresa, preco, variacao e horario da cotacao.

A coluna `Busca` permite consultar um ticker manualmente. Exemplos:

- `PETR4`, `VALE3` ou outro ativo da B3.
- `NVDA`, `MSFT` ou outro ticker americano.
- `IBOV`, `USD/BRL`, `SPX`, `EWZ`, `ES`, `NIKKEI` ou `SSE`.

Ao localizar o ativo, o app abre uma tela de detalhe com grafico diario de linha dos ultimos 6 meses, medias moveis de 9 e 20 periodos e uma leitura textual da tendencia atual.

O botao `JEX` abre uma tela institucional separada para a empresa privada neerlandesa JEX Nederland B.V. A tela apresenta dados cadastrais, linha do tempo publica consolidada e links para verificacao nas fontes. Como a empresa nao possui ticker publico, ela nao aparece como cotacao de bolsa.

Na tela institucional, o botao `JEX ANALITICS` abre uma analise baseada em informacoes publicas: pressao de caixa, leitura fundamentalista, perspectiva de IPO e sentimento qualitativo. Como nao ha demonstracoes financeiras completas abertas nem prospecto publico, a tela separa fatos, inferencias e informacoes indisponiveis.

No card de fluxo de caixa, o botao `Ver fotografia financeira` abre uma visualizacao em pizza com comparacao percentual de magnitudes publicas selecionadas. A visualizacao inclui um aviso metodologico: os indicadores comparados nao representam uma composicao contabil do caixa.

A coluna do Ibovespa usa o scanner do TradingView para buscar as cotacoes dos ativos da B3. Na modalidade gratuita, dados da B3 podem ter atraso de 15 minutos; cotacoes realmente em tempo real dependem de assinatura/feed autorizado.

No lado direito, o painel `Indicadores` mostra a cotacao do Ibovespa e do dolar americano em reais (`USD/BRL`). A cotacao gratuita do IBOV pode ter atraso de ate 15 minutos.

O sistema roda em atualizacao automatica: indices a cada 5 segundos e demais listas/indicadores a cada 60 segundos, buscando o dado mais recente disponibilizado pelas fontes.

Na terceira coluna, clique em `SSE Composite` para abrir uma tela com grafico de candlesticks de 5 minutos e medias moveis de 9 e 20 periodos.

## Meu orcamento

Na tela de controle de investimentos, o botao `Meu orcamento` abre um modulo simples para acompanhar receitas e despesas mensais.

Regra de negocio:

- Cada lancamento pertence a um mes de referencia no formato `AAAA-MM`.
- O lancamento pode ser `Receita` ou `Despesa`.
- Todo lancamento tem descricao, valor, vencimento/data e status.
- Despesas pagas tambem podem registrar a data do pagamento no formato brasileiro `dd/mm/aaaa`.
- Em receitas, o status indica `Recebido` ou `Nao recebido`.
- Em despesas, o status indica `Pago` ou `Falta pagar`.
- Lancamentos cadastrados podem ser editados, salvos novamente ou cancelados antes da alteracao.
- A tela totaliza receitas, despesas, saldo previsto e despesas ainda em aberto.
- Os dados ficam salvos no banco da aplicacao, na tabela `monthly_budget_items`.

## Cotações online

O app tenta buscar dados primeiro na API da brapi:

```text
https://brapi.dev/api/quote
```

Sem token, a brapi libera um conjunto limitado de ativos de teste e pode recusar consultas com muitos tickers ou indices. Quando isso acontece, o app tenta buscar os mesmos tickers pelo endpoint de grafico do Yahoo Finance.

Para usar a brapi com mais estabilidade, crie uma chave e defina a variavel de ambiente `BRAPI_TOKEN`.

No PowerShell:

```powershell
$env:BRAPI_TOKEN="sua-chave-aqui"
flet run main.py
```

Dados gratuitos podem ter atraso, conforme a fonte/plano de dados.

Ao iniciar, o app tenta consultar a composicao atual do Ibovespa pelo site/API publica da B3. Se a consulta nao responder, usa uma lista local de reserva.

## Testar no celular

Instale o app Flet no Android e rode:

```powershell
flet run --android main.py
```

O terminal exibira um QR Code para abrir o app no celular conectado a mesma rede Wi-Fi.

## Gerar app Android

O Flet permite gerar APK no Windows, Linux ou macOS. Instale o Flet e rode:

```powershell
flet build apk
```

Na primeira execucao, o Flet pode baixar Java JDK 17 e Android SDK automaticamente se eles nao estiverem instalados.

## Observacao

Este app faz um controle simples de rentabilidade. Ele nao substitui relatorios oficiais da corretora nem apuracao fiscal.
