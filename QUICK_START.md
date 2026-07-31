# ArcLend — Quick Start Guide

Get the full stack running locally in under 10 minutes.

---

## Prerequisites

- Node.js 18+
- Docker & Docker Compose
- Git

---

## 1. Clone & Install

```bash
git clone <repo-url> ArcLend
cd ArcLend
```

Install dependencies for each service:

```bash
# From repo root — installs all 4 packages at once
pnpm install
```

---

## 2. Configure Environment

```bash
cp .env.example .env
```

The defaults in `.env.example` work for local development with no changes needed.
For a real deployment, update:
- `PRIVATE_KEY` — use a real funded wallet (never the Hardhat default key)
- `RPC_URL` — your node or Infura/Alchemy endpoint
- `LENDING_POOL_ADDRESS` — deployed Diamond contract address
- `DB_PASSWORD` — a strong password

---

## 3. Start Infrastructure

```bash
docker-compose up -d
```

This starts:
- **PostgreSQL** on port `5432`
- **Redis** on port `6379`

Run the initial schema migration:

```bash
psql -h localhost -U postgres -d aave_lending -f backend/src/infrastructure/database/migrations/001_initial_schema.sql
```

---

## 4. Deploy Smart Contracts

Start a local Hardhat node (in a separate terminal):

```bash
cd contracts
npx hardhat node
```

In another terminal, deploy:

```bash
cd contracts
npx hardhat run deploy/00_deploy_all.ts --network localhost
```

Copy the printed `Diamond address` into your `.env` as `LENDING_POOL_ADDRESS`.

---

## 5. Start Each Service

Open a terminal for each service:

**Backend API** (port 3000):
```bash
cd backend
npm run start:dev
```

**Blockchain Indexer**:
```bash
cd indexer
npx ts-node src/main.ts
```

**Liquidation Bot**:
```bash
cd liquidation-bot
npx ts-node src/main.ts
```

---

## 6. Verify Everything Works

```bash
# Backend health check
curl http://localhost:3000/api/v1/health

# List markets (empty at first)
curl http://localhost:3000/api/v1/markets
```

---

## Code Style Quick Reference

### Solidity

```solidity
// Always explicit pragma
pragma solidity 0.8.21;

// NatSpec on every external function
/// @notice Deposit underlying asset and receive aTokens
/// @param asset The ERC20 asset address
/// @param amount Amount to deposit
function deposit(address asset, uint256 amount) external {
    LibAccessControl.requireNotPaused();     // pause check first
    AppStorage storage s = LibAppStorage.appStorage(); // Diamond storage
    s.reserves[asset].updateState(asset);   // accrue interest first
    // ...
}
```

### TypeScript (NestJS)

```typescript
// Services: business logic only, no HTTP
@Injectable()
export class DepositsService {
    constructor(
        @InjectRepository(DepositEntity)
        private readonly repo: Repository<DepositEntity>,
    ) {}

    async findAllByUserId(userId: string): Promise<DepositEntity[]> {
        return this.repo.find({ where: { userId } });
    }
}
```

### TypeScript (Indexer / Bot)

```typescript
// Always parameterized SQL
const result = await client.query(
    'INSERT INTO deposits (tx_hash, log_index, amount) VALUES ($1, $2, $3)',
    [txHash, logIndex, amount],
);

// Always wrap multi-step writes in a transaction
await client.query('BEGIN');
try {
    // ... writes
    await client.query('COMMIT');
} catch (e) {
    await client.query('ROLLBACK');
    throw e;
}
```

---

## Run Tests

```bash
# Smart contract tests (Hardhat)
pnpm --filter @arclend/contracts test

# Backend unit tests
pnpm --filter aave-lending-backend test

# All packages
pnpm test:all
```

---

## Common Issues

| Problem | Fix |
|---------|-----|
| `ECONNREFUSED 5432` | Run `docker-compose up -d` first |
| `ECONNREFUSED 6379` | Redis not running — check Docker |
| `relation "users" does not exist` | Run the SQL migration file |
| `nonce too low` on bot | Restart Hardhat node and redeploy |
| `invalid address` on deposit | Ensure `LENDING_POOL_ADDRESS` is set in `.env` |

---

## Complete Documentation

- **CLAUDE.md** — Mandatory rules, coding standards, AI agent guide
- **ARCHITECTURE.md** — Full system design, data flow, math overview
- **docs/DEVELOPMENT.md** — Module-by-module development guide
- **docs/CONTRACTS.md** — Smart contract internals and upgrade guide
- **docs/INDEXER.md** — Indexer implementation guide (what to build next)
- **docs/DATABASE.md** — Schema reference and query patterns
