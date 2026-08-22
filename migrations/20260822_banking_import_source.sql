ALTER TABLE bank_transactions
    ADD COLUMN IF NOT EXISTS source_type TEXT NOT NULL DEFAULT 'manual';

ALTER TABLE bank_transactions
    ADD COLUMN IF NOT EXISTS external_id TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_bank_tx_import_identity
    ON bank_transactions(owner_key, account_id, external_id)
    WHERE external_id <> '';
