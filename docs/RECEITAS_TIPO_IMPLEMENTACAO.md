# Tipo de Receita — implementação completa

Data: 31/07/2026

## Arquitetura identificada

O frontend oficial é Flutter e consome a API ASGI em `web_app.py`. A API
normaliza e valida o payload e delega a persistência a `main.py`. Receitas e
despesas compartilham a tabela `monthly_budget_items`, tanto no PostgreSQL de
produção quanto no SQLite de testes/desenvolvimento. Listagem mensal, BI anual
e totalizadores leem essa mesma tabela.

## Banco e migration

Foram adicionadas as colunas:

- `tipo_receita`: valor padronizado `ALUGUEL`, `DAY_TRADE` ou `OUTROS`;
- `tipo_receita_outros`: texto livre limitado a 80 caracteres.

A migration PostgreSQL está em
`migrations/20260731_add_revenue_type.sql`. A inicialização idempotente também
migra PostgreSQL e SQLite automaticamente.

As colunas são anuláveis para preservar registros anteriores. Nenhuma receita
antiga foi classificada automaticamente como `OUTROS`; ela aparece como “Não
informado” até ser editada.

## Frontend

- Dropdown obrigatório no cadastro e na edição de receitas.
- Opções fixas: Aluguel, Day Trade e Outros.
- Campo “Especifique o tipo de receita” exibido apenas para Outros.
- Limite de 80 caracteres e remoção de espaços nas extremidades.
- A especificação é limpa ao trocar para Aluguel, Day Trade ou Despesa.
- Categoria exibida em cada cartão da listagem.
- Filtro independente: Todos, Aluguel, Day Trade e Outros.
- O filtro Outros usa a categoria principal e não a descrição livre.
- Componentes nativos Flutter preservam mouse, teclado, setas, Enter e foco
  visível; o formulário e os filtros mantêm o layout responsivo existente.

## Backend e validações

O backend é a fonte final de validação e rejeita:

- receita sem categoria: “Selecione o tipo de receita.”;
- Outros sem especificação: “Especifique o tipo de receita.”;
- categoria fora da lista: “Tipo de receita inválido.”;
- especificação com mais de 80 caracteres.

Para Aluguel e Day Trade, `tipo_receita_outros` é sempre gravado como nulo,
mesmo que um cliente tente enviá-lo. Para despesas, os dois campos são nulos.

## Relatórios e cálculos

Os payloads mensal e anual agora incluem os dois campos. Totais, saldos,
recebimentos parciais, Caixa e métricas continuam usando os mesmos campos de
valor e status; portanto, a categorização não altera cálculos financeiros.

## Evidências

- 34 testes backend e regras financeiras aprovados.
- 34 testes Flutter aprovados.
- Análise estática Flutter sem problemas.
- Build web de produção concluído.
- Casos cobertos: Aluguel, Day Trade, Outros, especificação aparada,
  categoria ausente/inválida, Outros vazio, persistência SQLite, troca de
  Outros para categoria fixa, leitura mensal/anual e receita legada.

## Compatibilidade

Os contratos existentes foram estendidos, sem remoção de campos. Funções de
persistência aceitam categorias anuláveis para que registros e chamadas
legadas continuem legíveis. Novos cadastros e edições feitos pela API exigem a
categoria, conforme a nova regra de negócio. As suítes anteriores de orçamento,
Caixa, day trade, fluxo de capital e sessão permaneceram aprovadas.
