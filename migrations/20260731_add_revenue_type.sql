-- Compatível com PostgreSQL. Registros antigos permanecem NULL de propósito.
ALTER TABLE monthly_budget_items
    ADD COLUMN IF NOT EXISTS tipo_receita TEXT;

ALTER TABLE monthly_budget_items
    ADD COLUMN IF NOT EXISTS tipo_receita_outros VARCHAR(80);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'monthly_budget_items_tipo_receita_check'
    ) THEN
        ALTER TABLE monthly_budget_items
            ADD CONSTRAINT monthly_budget_items_tipo_receita_check
            CHECK (
                tipo_receita IS NULL
                OR tipo_receita IN ('ALUGUEL', 'DAY_TRADE', 'OUTROS')
            );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'monthly_budget_items_tipo_receita_outros_check'
    ) THEN
        ALTER TABLE monthly_budget_items
            ADD CONSTRAINT monthly_budget_items_tipo_receita_outros_check
            CHECK (
                (tipo_receita = 'OUTROS' AND NULLIF(BTRIM(tipo_receita_outros), '') IS NOT NULL)
                OR (tipo_receita IS DISTINCT FROM 'OUTROS' AND tipo_receita_outros IS NULL)
            ) NOT VALID;
    END IF;
END $$;
