-- Migration 002: Add repayments and withdrawals history tables
-- These tables track the Repay and Withdraw events emitted by the protocol.
-- Run after 001_initial_schema.sql.

CREATE TABLE repayments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    user_id UUID NOT NULL REFERENCES users(id),
    market_id UUID NOT NULL REFERENCES markets(id),
    repayer_id UUID REFERENCES users(id),        -- null if repayer == user
    amount NUMERIC(78,0) NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(tx_hash, log_index)
);

CREATE INDEX idx_repayments_user ON repayments(user_id);
CREATE INDEX idx_repayments_market ON repayments(market_id);

CREATE TABLE withdrawals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    user_id UUID NOT NULL REFERENCES users(id),
    market_id UUID NOT NULL REFERENCES markets(id),
    to_address VARCHAR(42) NOT NULL,              -- recipient of the underlying asset
    amount NUMERIC(78,0) NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(tx_hash, log_index)
);

CREATE INDEX idx_withdrawals_user ON withdrawals(user_id);
CREATE INDEX idx_withdrawals_market ON withdrawals(market_id);
