# Carteira de investimentos

Esta carteira usa `/api/portfolio-v2` no mesmo domínio do site. A sessão do aplicativo é validada no backend existente (`/api/auth/me`); a identidade não é aceita do corpo da requisição. Cada usuário possui sua própria carteira e o perfil de consulta não pode gravar.

Os dados ficam na tabela D1 `investment_portfolios`, em documento versionado. Um compare-and-swap por revisão evita sobrescritas concorrentes. Cadastro com aporte inicial é gravado em uma única operação. As tabelas antigas de investimentos, Day Trade, orçamento e origens de pagamento não são alteradas ou importadas.

## Uso

- Renda fixa vem preenchida com Tesouro Prefixado 2029, vencimento 01/01/2029, pelo C6 Bank. Os campos são livres. A taxa anual é cadastral; não há projeção automática de juros nem de impostos.
- Renda variável oferece tickers clicáveis, com destaque inicial a ITSA4, e aceita cadastro manual de outros papéis.
- Aportes/compras registram valor, quantidade/preço quando aplicável, data e custos. Retiradas registram resgates/vendas efetivos. Não há envio de ordens nem integração bancária.
- Atualização de posição informa o saldo bruto do extrato para renda fixa ou o preço unitário para renda variável. É um evento de avaliação, não um aporte.
- Dividendos, JCP e juros recebidos fora da posição são rendimentos; para reinvesti-los registre também um aporte.
- A posição em uma data considera eventos até aquele dia, em ordem cronológica. Eventos no mesmo dia mantêm a ordem de inclusão. Lançamentos posteriores continuam sendo validados ao excluir um registro antigo.
- Resultado absoluto = posição + retiradas líquidas + rendimentos líquidos − aportes e custos. Não é uma taxa anualizada nem uma apuração tributária.
- O preço da última compra/venda é a referência até uma nova cotação informada. A origem e a data aparecem no cartão. Não há cotação em tempo real.

## Fontes cadastrais

- [Itaúsa: composição acionária, ITSA3 e ITSA4](https://ri.itausa.com.br/governanca-corporativa/composicao-acionaria/)
- [C6 Bank: Tesouro Direto](https://www.c6bank.com.br/tesouro-direto/)
- [Tesouro Nacional: relatório com vencimento do Prefixado 2029](https://cdn.tesouro.gov.br/sistemas-internos/apex/producao/sistemas/thot/arquivos/publicacoes/48789_1598601/Balan%C3%A7o%20TD%20-%20Arte%20correta%20-%20Anual%20Dezembro2023.pdf)
- [B3: tickers negociados](https://www.b3.com.br/pt_br/noticias/datawise-8AE490C99FB04F9C019FB319DE9F63AD.htm)

## Verificação

`node --test hosting/portfolio.test.mjs` valida persistência SQLite, isolamento, permissões, concorrência, cronologia, saldo e quantidades. `flutter test --no-pub test/investment_portfolio_model_test.dart test/investments_screen_test.dart` valida cálculos e formulário em tela móvel, inclusive preservação de entradas quando a gravação falha.
