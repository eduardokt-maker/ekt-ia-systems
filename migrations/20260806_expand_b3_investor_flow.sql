-- Amplia o histórico oficial já existente sem apagar registros.
CREATE TABLE IF NOT EXISTS capital_flow_revisions (
    id BIGSERIAL PRIMARY KEY,
    record_id BIGINT NOT NULL REFERENCES capital_flow_records(id),
    old_inflow NUMERIC(20, 2) NOT NULL,
    old_outflow NUMERIC(20, 2) NOT NULL,
    new_inflow NUMERIC(20, 2) NOT NULL,
    new_outflow NUMERIC(20, 2) NOT NULL,
    revision_reason TEXT NOT NULL,
    detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_capital_flow_records_date_type
    ON capital_flow_records(reference_date, investor_type);

CREATE INDEX IF NOT EXISTS idx_capital_flow_revisions_record
    ON capital_flow_revisions(record_id, detected_at DESC);
