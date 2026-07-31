-- A competência já existe em reference_month e é armazenada como DATE no
-- primeiro dia do mês. Esta migration adiciona somente os índices necessários
-- às consultas independentes por competência, vencimento e pagamento.

CREATE INDEX IF NOT EXISTS idx_monthly_budget_owner_month
    ON monthly_budget_items (owner_key, reference_month);

CREATE INDEX IF NOT EXISTS idx_monthly_budget_owner_due_date
    ON monthly_budget_items (owner_key, due_date);

CREATE INDEX IF NOT EXISTS idx_monthly_budget_owner_payment_date
    ON monthly_budget_items (owner_key, payment_date)
    WHERE payment_date IS NOT NULL;
