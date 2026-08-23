CREATE TABLE IF NOT EXISTS bank_import_batches (
    id BIGSERIAL PRIMARY KEY,
    owner_key TEXT NOT NULL,
    account_id BIGINT NOT NULL REFERENCES bank_accounts(id) ON DELETE CASCADE,
    filename TEXT NOT NULL,
    document_kind TEXT NOT NULL,
    detected_bank TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE bank_transactions
    ADD COLUMN IF NOT EXISTS import_batch_id BIGINT
    REFERENCES bank_import_batches(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_bank_import_owner_created
    ON bank_import_batches(owner_key, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_bank_tx_import_batch
    ON bank_transactions(owner_key, import_batch_id);
