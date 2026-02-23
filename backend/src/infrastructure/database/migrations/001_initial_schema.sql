-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
--                        CORE TABLES
-- ============================================================

-- Users: Wallet addresses and metadata
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    address VARCHAR(42) NOT NULL UNIQUE, -- Normalized lowercase
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_active TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Markets: Reserve configuration
CREATE TABLE markets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_address VARCHAR(42) NOT NULL UNIQUE,
    symbol VARCHAR(10) NOT NULL,
    decimals INTEGER NOT NULL,
    ltv NUMERIC(5,0) NOT NULL, -- Basis points
    liquidation_threshold NUMERIC(5,0) NOT NULL, -- Basis points
    liquidation_bonus NUMERIC(5,0) NOT NULL, -- Basis points
    reserve_factor NUMERIC(5,0) NOT NULL, -- Basis points
    is_active BOOLEAN DEFAULT TRUE,
    is_frozen BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- User Positions: Current aggregated state per user+market
-- Optimized for reading health factor without summing logs
CREATE TABLE user_positions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id),
    market_id UUID NOT NULL REFERENCES markets(id),
    
    -- Scaled balances (ray precision) match smart contract state
    scaled_atoken_balance NUMERIC(78,0) DEFAULT 0,
    scaled_debt_balance NUMERIC(78,0) DEFAULT 0,
    
    -- Cached health metrics (updated by indexer)
    health_factor NUMERIC(78,0), -- Wad
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(user_id, market_id)
);

-- Index for liquidation scanner
CREATE INDEX idx_user_positions_health ON user_positions(health_factor) WHERE health_factor < 1000000000000000000; -- < 1.0 wad

-- ============================================================
--                        HISTORY TABLES
-- ============================================================

CREATE TABLE deposits (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    user_id UUID NOT NULL REFERENCES users(id),
    market_id UUID NOT NULL REFERENCES markets(id),
    amount NUMERIC(78,0) NOT NULL, -- Underlying amount
    on_behalf_of UUID REFERENCES users(id),
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(tx_hash, log_index)
);

CREATE TABLE borrows (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    user_id UUID NOT NULL REFERENCES users(id),
    market_id UUID NOT NULL REFERENCES markets(id),
    amount NUMERIC(78,0) NOT NULL,
    borrow_rate NUMERIC(78,0) NOT NULL, -- Ray
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(tx_hash, log_index)
);

CREATE TABLE liquidations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    
    collateral_market_id UUID NOT NULL REFERENCES markets(id),
    debt_market_id UUID NOT NULL REFERENCES markets(id),
    liquidated_user_id UUID NOT NULL REFERENCES users(id),
    liquidator_address VARCHAR(42) NOT NULL, -- External liquidator
    
    debt_to_cover NUMERIC(78,0) NOT NULL,
    collateral_seized NUMERIC(78,0) NOT NULL,
    
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(tx_hash, log_index)
);

-- ============================================================
--                        DATA FEEDS
-- ============================================================

CREATE TABLE prices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    market_id UUID NOT NULL REFERENCES markets(id),
    price NUMERIC(78,0) NOT NULL, -- Wad (base currency)
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_prices_market_time ON prices(market_id, timestamp DESC);

-- ============================================================
--                        INDEXER STATE
-- ============================================================

CREATE TABLE block_sync_state (
    chain_id INTEGER PRIMARY KEY,
    last_processed_block INTEGER NOT NULL,
    last_processed_hash VARCHAR(66) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE raw_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chain_id INTEGER NOT NULL,
    block_number INTEGER NOT NULL,
    block_hash VARCHAR(66) NOT NULL,
    parent_hash VARCHAR(66) NOT NULL,
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    event_name VARCHAR(100) NOT NULL,
    data JSONB NOT NULL,
    processed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(tx_hash, log_index)
);

CREATE INDEX idx_raw_events_block ON raw_events(block_number);
