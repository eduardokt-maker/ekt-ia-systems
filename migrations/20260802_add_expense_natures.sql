BEGIN;

CREATE TABLE IF NOT EXISTS expense_natures (
    id BIGSERIAL PRIMARY KEY,
    owner_key TEXT NOT NULL,
    name VARCHAR(80) NOT NULL,
    normalized_name VARCHAR(80) NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (owner_key, normalized_name)
);

ALTER TABLE monthly_budget_items
    ADD COLUMN IF NOT EXISTS expense_nature_id BIGINT;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'monthly_budget_items_expense_nature_fk'
    ) THEN
        ALTER TABLE monthly_budget_items
            ADD CONSTRAINT monthly_budget_items_expense_nature_fk
            FOREIGN KEY (expense_nature_id) REFERENCES expense_natures(id)
            ON DELETE RESTRICT NOT VALID;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_monthly_budget_expense_nature
    ON monthly_budget_items (owner_key, expense_nature_id);

COMMIT;

-- Reversão manual segura, somente após confirmar que nenhum vínculo deve ser preservado:
-- DROP INDEX IF EXISTS idx_monthly_budget_expense_nature;
-- ALTER TABLE monthly_budget_items DROP COLUMN IF EXISTS expense_nature_id;
-- DROP TABLE IF EXISTS expense_natures;
