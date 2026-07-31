-- Novos lançamentos continuam exigindo competência na API.
-- A leitura precisa tolerar registros legados sem competência.
ALTER TABLE monthly_budget_items
    ALTER COLUMN reference_month DROP NOT NULL;
