# ArcLend — Blockchain Indexer Guide

## Purpose

The indexer is the **nervous system** of ArcLend. It watches the blockchain for events emitted by the Diamond contract and writes a mirror of the protocol's state into PostgreSQL. The NestJS backend and liquidation bot both read from this database — they have no direct RPC access to the blockchain.

Without a functioning indexer, `user_positions` is never populated, health factors are never computed, and the liquidation bot can never find anyone to liquidate.

---

## Current State (What Exists vs What's Missing)

| Component | Status | Notes |
|-----------|--------|-------|
| `BlockWatcher` — sync cursor management | ✅ Done | Tracks `block_sync_state` correctly |
| `BlockWatcher` — reorg detection | ✅ Done | Detects reorg by comparing `parentHash` |
| `BlockWatcher` — reorg rollback | ⚠️ Partial | Rolls back 1 block; `last_processed_hash` set to `'UNKNOWN'` — broken |
| `BlockWatcher` — log fetching | ❌ Missing | `getLogs()` call is commented out |
| `EventProcessor` — raw_events insert | ✅ Done | Idempotent insert with `ON CONFLICT DO NOTHING` |
| `EventProcessor` — event routing | ❌ Missing | `routeEvent()` switch cases all commented out |
| `handleDeposit()` | ❌ Missing | Not implemented |
| `handleBorrow()` | ❌ Missing | Not implemented |
| `handleRepay()` | ❌ Missing | Not implemented |
| `handleWithdraw()` | ❌ Missing | Not implemented |
| `handleLiquidation()` | ❌ Missing | Not implemented |
| `user_positions` updater | ❌ Missing | Never written to by indexer |
| `ReorgDetector` class | ⚠️ Written but unused | Duplicates inline logic in BlockWatcher |

---

## Data Flow (Target State)

```
1. BlockWatcher.processBlocks()
       │
       ├─ getLastProcessedBlock()        ← reads block_sync_state
       ├─ provider.getBlockNumber()      ← current chain head
       │
       └─ for each new block:
              │
              ├─ detectReorg(block)      ← compares parentHash
              │     └─ handleReorg()     ← rollback derived tables
              │
              ├─ provider.getLogs({      ← MISSING: needs implementation
              │       address: DIAMOND,
              │       fromBlock: n,
              │       toBlock: n
              │   })
              │
              ├─ EventProcessor.processLog(log, client)
              │       ├─ Insert raw_events (idempotent)
              │       └─ routeEvent(parsedLog, client)
              │               ├─ handleDeposit()     ← MISSING
              │               ├─ handleBorrow()      ← MISSING
              │               ├─ handleRepay()       ← MISSING
              │               ├─ handleWithdraw()    ← MISSING
              │               └─ handleLiquidation() ← MISSING
              │
              └─ UPDATE block_sync_state (last block + hash)
```

---

## Implementing the Missing Pieces

### Step 1 — Load the Contract ABI

Create `src/abis/Diamond.json` by copying the ABI from the Hardhat compilation output:

```bash
cp contracts/artifacts/contracts/Diamond.sol/Diamond.json indexer/src/abis/Diamond.json
```

Or more precisely, build a combined ABI from all facets (since Diamond is a proxy):

```typescript
// src/config.ts
import { ethers } from 'ethers';

// Build combined interface from all facet ABIs
export const DIAMOND_INTERFACE = new ethers.Interface([
    // LendingPoolFacet events
    'event Deposit(address indexed reserve, address user, address indexed onBehalfOf, uint256 amount)',
    'event Withdraw(address indexed reserve, address indexed user, address indexed to, uint256 amount)',
    // BorrowFacet events
    'event Borrow(address indexed reserve, address user, address indexed onBehalfOf, uint256 amount, uint256 borrowRate)',
    'event Repay(address indexed reserve, address indexed user, address indexed repayer, uint256 amount)',
    // LiquidationFacet events
    'event LiquidationCall(address indexed collateralAsset, address indexed debtAsset, address indexed user, uint256 debtToCover, uint256 liquidatedCollateralAmount, address liquidator)',
]);

export const DIAMOND_ADDRESS = process.env.LENDING_POOL_ADDRESS!;
```

---

### Step 2 — Wire Log Fetching in BlockWatcher

Replace the commented-out `TODO` in `processBlock()`:

```typescript
// src/sync/block-watcher.ts

private async processBlock(block: ethers.Block) {
    const client = await this.db.connect();
    try {
        await client.query('BEGIN');

        // Fetch logs for our Diamond contract only
        const logs = await this.provider.getLogs({
            address: DIAMOND_ADDRESS,
            fromBlock: block.number,
            toBlock: block.number,
        });

        for (const log of logs) {
            await this.eventProcessor.processLog(log, block, client);
        }

        // Advance the sync cursor
        await client.query(
            'UPDATE block_sync_state SET last_processed_block = $1, last_processed_hash = $2 WHERE chain_id = $3',
            [block.number, block.hash, this.chainId],
        );

        await client.query('COMMIT');
    } catch (e) {
        await client.query('ROLLBACK');
        throw e;
    } finally {
        client.release();
    }
}
```

---

### Step 3 — Parse and Route Events in EventProcessor

```typescript
// src/processors/event-processor.ts

async processLog(log: ethers.Log, block: ethers.Block, client: PoolClient) {
    // 1. Insert raw event (idempotent)
    const insertRes = await client.query(
        `INSERT INTO raw_events
         (chain_id, block_number, block_hash, parent_hash, tx_hash, log_index, event_name, data, processed)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false)
         ON CONFLICT (tx_hash, log_index) DO NOTHING
         RETURNING id`,
        [
            this.chainId,
            block.number,
            block.hash,
            block.parentHash,     // ← was 'UNKNOWN' before; block is now passed in
            log.transactionHash,
            log.index,
            'UNKNOWN',            // updated below after parsing
            JSON.stringify(log),
        ],
    );

    if (insertRes.rowCount === 0) return; // already processed

    // 2. Parse the log
    let parsedLog: ethers.LogDescription | null = null;
    try {
        parsedLog = DIAMOND_INTERFACE.parseLog({ topics: [...log.topics], data: log.data });
    } catch {
        // Unknown event signature — skip
        return;
    }

    // 3. Update event name in raw_events
    await client.query(
        'UPDATE raw_events SET event_name = $1 WHERE tx_hash = $2 AND log_index = $3',
        [parsedLog.name, log.transactionHash, log.index],
    );

    // 4. Route to handler
    await this.routeEvent(parsedLog, log, block, client);

    // 5. Mark as processed
    await client.query(
        'UPDATE raw_events SET processed = true WHERE tx_hash = $1 AND log_index = $2',
        [log.transactionHash, log.index],
    );
}

async routeEvent(parsedLog: ethers.LogDescription, log: ethers.Log, block: ethers.Block, client: PoolClient) {
    const timestamp = new Date((await this.provider.getBlock(block.number))!.timestamp * 1000);

    switch (parsedLog.name) {
        case 'Deposit':
            await this.handleDeposit(parsedLog, log, timestamp, client);
            break;
        case 'Withdraw':
            await this.handleWithdraw(parsedLog, log, timestamp, client);
            break;
        case 'Borrow':
            await this.handleBorrow(parsedLog, log, timestamp, client);
            break;
        case 'Repay':
            await this.handleRepay(parsedLog, log, timestamp, client);
            break;
        case 'LiquidationCall':
            await this.handleLiquidation(parsedLog, log, timestamp, client);
            break;
        default:
            console.warn(`Unhandled event: ${parsedLog.name}`);
    }
}
```

---

### Step 4 — Implement Event Handlers

Each handler follows the same pattern:
1. Upsert the `users` row for every address involved
2. Look up the `markets` row by asset address
3. Insert into the history table (`deposits`, `borrows`, etc.)
4. Upsert `user_positions` with updated scaled balances

```typescript
// src/processors/handlers/deposit.handler.ts

async handleDeposit(
    parsed: ethers.LogDescription,
    log: ethers.Log,
    timestamp: Date,
    client: PoolClient,
) {
    const reserve: string = parsed.args.reserve.toLowerCase();
    const onBehalfOf: string = parsed.args.onBehalfOf.toLowerCase();
    const amount: bigint = parsed.args.amount;

    // Upsert user
    await client.query(
        `INSERT INTO users (address) VALUES ($1)
         ON CONFLICT (address) DO UPDATE SET last_active = NOW()`,
        [onBehalfOf],
    );

    // Resolve IDs
    const userRes = await client.query('SELECT id FROM users WHERE address = $1', [onBehalfOf]);
    const marketRes = await client.query('SELECT id FROM markets WHERE asset_address = $1', [reserve]);

    if (marketRes.rowCount === 0) {
        console.warn(`Unknown market for asset ${reserve} — skipping`);
        return;
    }

    const userId: string = userRes.rows[0].id;
    const marketId: string = marketRes.rows[0].id;

    // Insert deposit history
    await client.query(
        `INSERT INTO deposits (tx_hash, log_index, user_id, market_id, amount, on_behalf_of, timestamp)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (tx_hash, log_index) DO NOTHING`,
        [log.transactionHash, log.index, userId, marketId, amount.toString(), userId, timestamp],
    );

    // Upsert user_positions — increment scaled_atoken_balance
    // Note: we store the raw amount here; a separate job should convert to scaled balance
    // using the reserve's current liquidityIndex from the chain or from ViewFacet
    await client.query(
        `INSERT INTO user_positions (user_id, market_id, scaled_atoken_balance)
         VALUES ($1, $2, $3)
         ON CONFLICT (user_id, market_id)
         DO UPDATE SET
             scaled_atoken_balance = user_positions.scaled_atoken_balance + EXCLUDED.scaled_atoken_balance,
             updated_at = NOW()`,
        [userId, marketId, amount.toString()],
    );
}
```

---

### Step 5 — Fix Reorg Rollback

The current rollback sets `last_processed_hash = 'UNKNOWN'` which breaks future reorg detection.

```typescript
// Correct rollback — fetch the parent block's hash from the provider
private async handleReorg(block: ethers.Block) {
    const rollbackToBlock = block.number - 1;
    const parentBlock = await this.provider.getBlock(rollbackToBlock);

    const client = await this.db.connect();
    try {
        await client.query('BEGIN');

        // Roll back derived tables
        await client.query(
            `DELETE FROM deposits
             WHERE tx_hash IN (
                 SELECT tx_hash FROM raw_events WHERE block_number > $1 AND chain_id = $2
             )`,
            [rollbackToBlock, this.chainId],
        );
        // Same for borrows, liquidations, user_positions...

        // Roll back raw events
        await client.query(
            'DELETE FROM raw_events WHERE block_number > $1 AND chain_id = $2',
            [rollbackToBlock, this.chainId],
        );

        // Reset sync cursor to the last safe block
        await client.query(
            'UPDATE block_sync_state SET last_processed_block = $1, last_processed_hash = $2 WHERE chain_id = $3',
            [rollbackToBlock, parentBlock?.hash ?? ethers.ZeroHash, this.chainId],
        );

        await client.query('COMMIT');
    } catch (e) {
        await client.query('ROLLBACK');
        throw e;
    } finally {
        client.release();
    }
}
```

---

## Environment Variables

```bash
# From .env
RPC_URL=http://localhost:8545         # WebSocket preferred: ws://localhost:8545
LENDING_POOL_ADDRESS=0x...
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=postgrespassword
DB_NAME=aave_lending
CHAIN_ID=31337
START_BLOCK=0                         # Block number to start indexing from
```

---

## Operational Notes

- **Start block**: Set `START_BLOCK` to the block where the Diamond was deployed. The indexer will catch up from there.
- **WebSocket vs HTTP**: For live block subscription, use a WebSocket RPC URL (`ws://` or `wss://`). HTTP polling works for development.
- **Reorg safety depth**: On mainnet, consider only confirming events after 12+ blocks (2 Ethereum epochs). For testnet/local, 1 block is fine.
- **Performance**: For high-throughput chains, batch `getLogs()` calls across multiple blocks rather than one block at a time.
- **Logging**: Replace `console.log/error` with a proper logger (winston is already in `package.json`).
