-- Fundação aditiva do módulo Controle Bancário e Cartões.
-- Valores monetários são persistidos em centavos inteiros.
CREATE TABLE IF NOT EXISTS bank_accounts (
    id BIGSERIAL PRIMARY KEY, owner_key TEXT NOT NULL,
    bank_name TEXT NOT NULL, description TEXT NOT NULL,
    account_type TEXT NOT NULL, holder TEXT NOT NULL,
    agency TEXT NOT NULL DEFAULT '', account_last_digits TEXT NOT NULL DEFAULT '',
    opening_balance_cents BIGINT NOT NULL DEFAULT 0, opening_date DATE NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE, notes TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS bank_cards (
    id BIGSERIAL PRIMARY KEY, owner_key TEXT NOT NULL,
    issuer TEXT NOT NULL, card_name TEXT NOT NULL, brand TEXT NOT NULL,
    last_four TEXT NOT NULL, holder TEXT NOT NULL,
    credit_limit_cents BIGINT NOT NULL DEFAULT 0,
    closing_day INTEGER NOT NULL, due_day INTEGER NOT NULL,
    payment_account_id BIGINT REFERENCES bank_accounts(id) ON DELETE SET NULL,
    visual_label TEXT NOT NULL DEFAULT '', active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS bank_categories (
    id BIGSERIAL PRIMARY KEY, owner_key TEXT NOT NULL,
    category_type TEXT NOT NULL CHECK (category_type IN ('INCOME', 'EXPENSE')),
    name TEXT NOT NULL,
    parent_id BIGINT REFERENCES bank_categories(id) ON DELETE SET NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(owner_key, category_type, name)
);

CREATE TABLE IF NOT EXISTS bank_transactions (
    id BIGSERIAL PRIMARY KEY, owner_key TEXT NOT NULL,
    transaction_date DATE NOT NULL,
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('INCOME', 'EXPENSE', 'TRANSFER')),
    description TEXT NOT NULL, counterparty TEXT NOT NULL DEFAULT '',
    category_id BIGINT REFERENCES bank_categories(id) ON DELETE SET NULL,
    amount_cents BIGINT NOT NULL CHECK (amount_cents > 0),
    payment_method TEXT NOT NULL DEFAULT '',
    account_id BIGINT REFERENCES bank_accounts(id) ON DELETE SET NULL,
    destination_account_id BIGINT REFERENCES bank_accounts(id) ON DELETE SET NULL,
    card_id BIGINT REFERENCES bank_cards(id) ON DELETE SET NULL,
    reference_month TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_bank_tx_owner_date
ON bank_transactions(owner_key, transaction_date, id);
CREATE INDEX IF NOT EXISTS idx_bank_tx_owner_month
ON bank_transactions(owner_key, reference_month, transaction_type);
