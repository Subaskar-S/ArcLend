# ArcLend — Database Schema Reference

## Overview

ArcLend uses PostgreSQL as its single source of derived truth. All data originates from on-chain events, processed by the indexer. The schema is designed for:

- **High write throughput** from the indexer (append-only history tables)
- **Fast health factor scans** by the liquidation bot (indexed `user_positions`)
- **Complex analytical queries** by the backend API (normalized + indexed)

---

## Schema Diagram

```
users ──────────────────────────────────────────────────────────┐
  id (uuid)                                                      │
  address (varchar 42, unique)                                   │
                                                                 │
markets ────────────────────────────────────────────────────────┤
  id (uuid)                                                      │
  asset_address (varchar 42, unique)                            │
  symbol, decimals, ltv, liquidation_threshold, ...             │
                                                                 │
user_positions ─── user_id → users.id                          │
                ─── market_id → markets.id                     │
  scaled_atoken_balance (numeric 78,0)                         │
  scaled_debt_balance (numeric 78,0)                           │
  health_factor (numeric 78,0)  ← indexed for HF < 1e18 scans │
                                                                │
deposits ──── user_id → users.id                               │
          ──── market_id → markets.id                          │
  tx_hash, log_index (unique)                                   │
  amount (numeric 78,0)                                        │
  timestamp                                                     │
                                                                │
borrows ────── user_id → users.id                              │
           ──── market_id → markets.id                         │
  tx_hash, log_index (unique)                                   │
  amount, borrow_rate (numeric 78,0)                           │
  timestamp                                                     │
                                                                │
liquidations ─── collateral_market_id → markets.id            │
             ─── debt_market_id → markets.id                   │
             ─── liquidated_user_id → users.id                 │
  liquidator_address (varchar 42)                              │
  debt_to_cover, collateral_seized (numeric 78,0)              │
  timestamp                                                     │
                                                                │
prices ──── market_id → markets.id                             │
  price (numeric 78,0)  ← WAD (1e18)                          │
  timestamp                                                     │
  INDEX (market_id, timestamp DESC)                            │
                                                                │
raw_events ──── chain_id, block_number, tx_hash, log_index     │
  event_name, data (jsonb)                                     │
  processed (bool)                                             │
  UNIQUE (tx_hash, log_index)                                  │
                                                                │
block_sync_state ──── chain_id (pk)                            │
  last_processed_block (int)                                   │
  last_processed_hash (varchar 66)                             │
```

---

## Table Reference

### `users`

Tracks every wallet address that has interacted with the protocol.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID | Primary key |
| `address` | VARCHAR(42) | Lowercase `0x...` address, unique |
| `created_at` | TIMESTAMPTZ | First interaction |
| `last_active` | TIMESTAMPTZ | Updated on each interaction |

**Rules**:
- Always normalize addresses to lowercase before insert/query
- Upsert on conflict: `ON CONFLICT (address) DO UPDATE SET last_active = NOW()`

---

### `markets`

One row per reserve (asset) configured in the protocol.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID | Primary key |
| `asset_address` | VARCHAR(42) | Lowercase contract address, unique |
| `symbol` | VARCHAR(10) | e.g. `USDC`, `WETH` |
| `decimals` | INTEGER | Token decimals (e.g. 6 for USDC, 18 for WETH) |
| `ltv` | NUMERIC(5,0) | Basis points (e.g. 7500 = 75%) |
| `liquidation_threshold` | NUMERIC(5,0) | Basis points |
| `liquidation_bonus` | NUMERIC(5,0) | Basis points (e.g. 10500 = 105%) |
| `reserve_factor` | NUMERIC(5,0) | Basis points |
| `is_active` | BOOLEAN | Whether deposits/borrows are allowed |
| `is_frozen` | BOOLEAN | Whether new deposits/borrows are frozen |

**Rules**:
- Populated by the indexer when it sees `ReserveInitialized` events (or seeded manually in dev)
- Risk params updated by indexer when `ConfiguratorFacet` events fire

---

### `user_positions`

Current aggregated position per user per market. Updated by the indexer after every relevant event.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID | Primary key |
| `user_id` | UUID | FK → users.id |
| `market_id` | UUID | FK → markets.id |
| `scaled_atoken_balance` | NUMERIC(78,0) | Scaled balance (divide by liquidityIndex for nominal) |
| `scaled_debt_balance` | NUMERIC(78,0) | Scaled balance (divide by variableBorrowIndex for nominal) |
| `health_factor` | NUMERIC(78,0) | WAD (1e18); updated by indexer or health updater job |

**Critical index** — used by the liquidation bot scanner:
```sql
CREATE INDEX idx_user_positions_health
ON user_positions(health_factor)
WHERE health_factor < 1000000000000000000; -- < 1.0 WAD
```

**Rules**:
- `UNIQUE(user_id, market_id)` — one row per user per market
- Upsert pattern: `ON CONFLICT (user_id, market_id) DO UPDATE SET ...`
- `scaled_*_balance` tracks the scaled amount (matches the smart contract's storage)
- `health_factor` should be recomputed after every position change using on-chain price data

---

### `deposits`

Append-only ledger of all `Deposit` events.

| Column | Type | Notes |
|--------|------|-------|
| `tx_hash` | VARCHAR(66) | Transaction hash |
| `log_index` | INTEGER | Log index within the transaction |
| `user_id` | UUID | FK → users.id (the depositor's `msg.sender`) |
| `market_id` | UUID | FK → markets.id |
| `amount` | NUMERIC(78,0) | Underlying token amount |
| `on_behalf_of` | UUID | FK → users.id (who received aTokens) |
| `timestamp` | TIMESTAMPTZ | Block timestamp |

**Uniqueness**: `UNIQUE(tx_hash, log_index)` — enables idempotent insert.

---

### `borrows`

Append-only ledger of all `Borrow` events.

| Column | Type | Notes |
|--------|------|-------|
| `tx_hash` | VARCHAR(66) | |
| `log_index` | INTEGER | |
| `user_id` | UUID | The borrower |
| `market_id` | UUID | The borrowed asset |
| `amount` | NUMERIC(78,0) | Borrowed amount |
| `borrow_rate` | NUMERIC(78,0) | Ray (1e27) — variable borrow rate at time of borrow |
| `timestamp` | TIMESTAMPTZ | |

---

### `liquidations`

| Column | Type | Notes |
|--------|------|-------|
| `tx_hash` | VARCHAR(66) | |
| `log_index` | INTEGER | |
| `collateral_market_id` | UUID | The seized collateral asset |
| `debt_market_id` | UUID | The covered debt asset |
| `liquidated_user_id` | UUID | The user who was liquidated |
| `liquidator_address` | VARCHAR(42) | The external liquidator (not stored as FK — external) |
| `debt_to_cover` | NUMERIC(78,0) | Amount of debt covered |
| `collateral_seized` | NUMERIC(78,0) | Amount of collateral transferred to liquidator |
| `timestamp` | TIMESTAMPTZ | |

---

### `prices`

Time-series price feed. One row per asset per update.

| Column | Type | Notes |
|--------|------|-------|
| `market_id` | UUID | FK → markets.id |
| `price` | NUMERIC(78,0) | WAD (1e18), denominated in base currency (USD) |
| `timestamp` | TIMESTAMPTZ | When the price was recorded |

**Query pattern** — latest price for an asset:
```sql
SELECT price FROM prices
WHERE market_id = $1
ORDER BY timestamp DESC
LIMIT 1;
```

**Index**: `CREATE INDEX idx_prices_market_time ON prices(market_id, timestamp DESC);`

**Note**: The `Price` entity in the NestJS backend currently uses `assetAddress` as a composite PK. This needs to be updated to match this FK-based schema.

---

### `raw_events`

Raw blockchain log storage — used for reorg rollback and audit.

| Column | Type | Notes |
|--------|------|-------|
| `chain_id` | INTEGER | |
| `block_number` | INTEGER | |
| `block_hash` | VARCHAR(66) | |
| `parent_hash` | VARCHAR(66) | Used for reorg detection |
| `tx_hash` | VARCHAR(66) | |
| `log_index` | INTEGER | |
| `event_name` | VARCHAR(100) | `Deposit`, `Borrow`, etc. |
| `data` | JSONB | Full raw log object |
| `processed` | BOOLEAN | Whether business logic was applied |

**Uniqueness**: `UNIQUE(tx_hash, log_index)`

---

### `block_sync_state`

One row per chain. The indexer's progress cursor.

| Column | Type | Notes |
|--------|------|-------|
| `chain_id` | INTEGER | Primary key |
| `last_processed_block` | INTEGER | Last fully processed block |
| `last_processed_hash` | VARCHAR(66) | Hash of `last_processed_block` — used for reorg detection |

---

## Missing Tables (To Add)

These history tables are implied by the protocol but not yet in the schema:

```sql
-- Repay history
CREATE TABLE repayments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    user_id UUID NOT NULL REFERENCES users(id),
    market_id UUID NOT NULL REFERENCES markets(id),
    repayer_id UUID REFERENCES users(id),
    amount NUMERIC(78,0) NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(tx_hash, log_index)
);

-- Withdraw history
CREATE TABLE withdrawals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    user_id UUID NOT NULL REFERENCES users(id),
    market_id UUID NOT NULL REFERENCES markets(id),
    to_address VARCHAR(42) NOT NULL,
    amount NUMERIC(78,0) NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(tx_hash, log_index)
);
```

---

## Common Query Patterns

### Get all unhealthy positions (used by liquidation bot)
```sql
SELECT u.address AS user_address, up.health_factor, up.market_id
FROM user_positions up
JOIN users u ON u.id = up.user_id
WHERE up.health_factor < 1000000000000000000  -- < 1.0 WAD
ORDER BY up.health_factor ASC
LIMIT 50;
```

### Get user's total deposits across all markets
```sql
SELECT m.symbol, SUM(d.amount) AS total_deposited
FROM deposits d
JOIN markets m ON m.id = d.market_id
WHERE d.user_id = $1
GROUP BY m.symbol;
```

### Get latest price for each active market
```sql
SELECT DISTINCT ON (p.market_id)
    m.symbol, p.price, p.timestamp
FROM prices p
JOIN markets m ON m.id = p.market_id
WHERE m.is_active = true
ORDER BY p.market_id, p.timestamp DESC;
```

### Get liquidation history for a user
```sql
SELECT
    cm.symbol AS collateral_asset,
    dm.symbol AS debt_asset,
    l.debt_to_cover,
    l.collateral_seized,
    l.liquidator_address,
    l.timestamp
FROM liquidations l
JOIN markets cm ON cm.id = l.collateral_market_id
JOIN markets dm ON dm.id = l.debt_market_id
WHERE l.liquidated_user_id = $1
ORDER BY l.timestamp DESC;
```

---

## Migration Naming Convention

All schema changes go in numbered SQL files:

```
backend/src/infrastructure/database/migrations/
├── 001_initial_schema.sql       ← current baseline
├── 002_add_repayments.sql       ← next migration
├── 003_add_withdrawals.sql
└── 004_fix_prices_entity.sql    ← fix prices table to use market_id FK
```

Never modify a migration file that has already been applied to any environment. Always append a new numbered file.
