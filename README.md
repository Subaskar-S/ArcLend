# ArcLend — DeFi Lending Protocol

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.21-blue.svg)](https://soliditylang.org/)
[![NestJS](https://img.shields.io/badge/NestJS-10.0-E0234E.svg)](https://nestjs.com/)
[![Node](https://img.shields.io/badge/Node.js-18+-green.svg)](https://nodejs.org/)
[![pnpm](https://img.shields.io/badge/pnpm-11.x-orange.svg)](https://pnpm.io/)

An Aave v2/v3-inspired decentralized lending protocol built with an EIP-2535 Diamond proxy, an event-driven blockchain indexer, a NestJS REST API, and a distributed liquidation bot.

---

## Architecture

```
User Wallet ──[EVM txs]──▶ Diamond Proxy (contracts/)
                                 │ emits events
                                 ▼
                         Indexer (indexer/)
                                 │ writes
                                 ▼
                           PostgreSQL DB
                          ▲            ▲
                          │            │
              NestJS API          Liquidation Bot
              (backend/)          (liquidation-bot/)
                                        │
                                   Redis (locks + cache)
```

| Service | Stack | Purpose |
|---------|-------|---------|
| `contracts/` | Solidity 0.8.21, Hardhat, EIP-2535 Diamond | On-chain protocol logic |
| `backend/` | NestJS 10, TypeORM, PostgreSQL, Redis | REST API read layer |
| `indexer/` | Node.js, ethers v6, pg | Blockchain → DB event pipeline |
| `liquidation-bot/` | Node.js, ethers v6, ioredis | Auto-liquidation bot |

---

## Key Features

- **EIP-2535 Diamond** — upgradeable multi-facet proxy; all state in a single `AppStorage` struct
- **Dual-slope interest rate model** — kinked utilization curve with wad/ray fixed-point math
- **Reorg-safe indexer** — detects chain reorganizations, rolls back derived tables, re-indexes
- **Distributed liquidation bot** — Redis `SET NX PX` locks prevent concurrent liquidation races
- **Clean architecture backend** — controllers, services, DTOs, entities strictly separated
- **pnpm workspace** — single install for all 4 packages from the repo root

---

## Repository Structure

```
ArcLend/
├── contracts/                  # Solidity smart contracts
│   ├── contracts/
│   │   ├── Diamond.sol         # Proxy entry point
│   │   ├── AppStorage.sol      # Shared state struct
│   │   ├── facets/             # LendingPool, Borrow, Liquidation, Config, View
│   │   ├── libraries/          # WadRayMath, ReserveLogic, GenericLogic, ...
│   │   ├── tokenization/       # AToken, DebtToken
│   │   ├── oracle/             # PriceOracle
│   │   └── interest/           # DefaultInterestRateStrategy
│   ├── deploy/                 # Hardhat deployment scripts
│   └── test/                   # Unit, integration, fuzz, invariant tests
│
├── backend/                    # NestJS REST API
│   └── src/
│       ├── modules/            # markets, users, deposits, borrows, liquidations, prices, health
│       └── infrastructure/     # database, redis, queue
│
├── indexer/                    # Blockchain event indexer
│   └── src/
│       ├── sync/               # BlockWatcher (block polling + reorg detection)
│       └── processors/         # EventProcessor + per-event handlers
│
├── liquidation-bot/            # Liquidation bot
│   └── src/
│       ├── scanner/            # HealthScanner (queries user_positions)
│       └── executor/           # LiquidationExecutor (calls contract)
│
├── docker-compose.yml          # PostgreSQL 15 + Redis 7
├── pnpm-workspace.yaml         # pnpm monorepo config
├── .env.example                # Environment variable template
├── CLAUDE.md                   # Coding standards and AI agent rules
├── QUICK_START.md              # Get running in 10 minutes
├── ARCHITECTURE.md             # System design deep dive
└── docs/
    ├── DEVELOPMENT.md          # Module-by-module dev guide
    ├── CONTRACTS.md            # Smart contract internals
    ├── INDEXER.md              # Indexer implementation guide
    └── DATABASE.md             # Schema reference and query patterns
```

---

## Quick Start

### Prerequisites

- Node.js 18+
- Docker & Docker Compose
- pnpm 11+ (`npm install -g pnpm`)

### 1. Install all dependencies

```bash
git clone https://github.com/Subaskar-S/ArcLend.git
cd ArcLend
pnpm install
```

### 2. Configure environment

```bash
cp .env.example .env
```

### 3. Start infrastructure

```bash
docker-compose up -d
psql -h localhost -U postgres -d aave_lending \
  -f backend/src/infrastructure/database/migrations/001_initial_schema.sql
psql -h localhost -U postgres -d aave_lending \
  -f backend/src/infrastructure/database/migrations/002_add_repayments_withdrawals.sql
```

### 4. Deploy contracts (local)

```bash
# Terminal 1 — local Hardhat node
pnpm --filter @arclend/contracts exec hardhat node

# Terminal 2 — deploy
pnpm --filter @arclend/contracts deploy:localhost
```

### 5. Start services

```bash
# Terminal 3 — API
pnpm --filter aave-lending-backend start:dev

# Terminal 4 — Indexer
pnpm --filter aave-lending-indexer start

# Terminal 5 — Liquidation Bot
pnpm --filter aave-lending-liquidator start
```

See **[QUICK_START.md](./QUICK_START.md)** for the full walkthrough including common errors.

---

## Testing

```bash
# Smart contract tests (Hardhat)
pnpm --filter @arclend/contracts test

# Backend unit tests
pnpm --filter aave-lending-backend test

# All packages
pnpm test:all

# Typecheck indexer and bot
pnpm --filter aave-lending-indexer typecheck
pnpm --filter aave-lending-liquidator typecheck
```

---

## Branch Strategy

| Branch | Purpose |
|--------|---------|
| `main` | Stable, release-ready code |
| `develop` | Integration branch — all features merge here first |
| `feature/<name>` | One branch per feature/module |
| `fix/<name>` | Bug fixes |

All work happens on feature branches → PR to `develop` → reviewed → merged → eventually promoted to `main`.

---

## Project Status

| Component | Status | Notes |
|-----------|--------|-------|
| Smart Contracts | ✅ Complete | All facets, libraries, tokenization, oracle |
| DB Schema | ✅ Complete | Migrations 001 + 002 |
| Backend CRUD | ✅ Complete | All 6 modules working |
| Indexer pipeline | ✅ Complete | Full event processing, reorg-safe |
| Health Factor API | 🔧 Stub | Returns hardcoded 1.5 WAD — needs real BigInt computation |
| Liquidation Bot execution | 🔧 Stub | Scanner works; executor.liquidate() not yet wired |
| user_positions HF updater | 🔧 Missing | Indexer writes balances but doesn't recompute health factor |
| Redis caching | 🔧 Partial | Infrastructure ready; not applied to hot paths yet |
| RateLimitGuard | 🔧 Partial | Implemented but not registered globally |
| BullMQ worker | 🔧 Missing | Queue declared; no consumer implemented |
| Foundry fuzz/invariant tests | 🔧 Stub | Skeletons exist, not implemented |
| Chainlink oracle | ⏳ Planned | Current oracle is admin-set; Chainlink for mainnet |

---

## Documentation

| Doc | Description |
|-----|-------------|
| [QUICK_START.md](./QUICK_START.md) | Get running locally in 10 minutes |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | System design, data flow, math overview |
| [CLAUDE.md](./CLAUDE.md) | Coding standards, mandatory rules, AI agent guide |
| [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md) | Module-by-module development guide |
| [docs/CONTRACTS.md](./docs/CONTRACTS.md) | Smart contract internals and upgrade guide |
| [docs/INDEXER.md](./docs/INDEXER.md) | Indexer implementation guide |
| [docs/DATABASE.md](./docs/DATABASE.md) | Schema reference and query patterns |

---

## License

MIT
