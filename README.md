# 🌊 Aave-Inspired DeFi Lending Protocol

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.21-blue.svg)](https://soliditylang.org/)
[![NestJS](https://img.shields.io/badge/NestJS-10.0-E0234E.svg)](https://nestjs.com/)
[![Foundry](https://img.shields.io/badge/Foundry-Toolchain-orange.svg)](https://getfoundry.sh/)

A production-grade, audit-ready decentralized lending system inspired by Aave v2/v3. This project includes UUPS upgradeable smart contracts, an event-driven blockchain indexer, a NestJS backend with Redis caching, and a distributed fault-tolerant liquidation bot.

---

## 🏗️ Architecture Overview

The system consists of six tightly integrated components:

1. **Smart Contracts**: UUPS upgradeable Solidity contracts with fixed-point `wad`/`ray` math for precise interest accrual.
2. **PostgreSQL Database**: Normalized schema with efficient indexing for rapid querying.
3. **Blockchain Indexer**: Event-driven, reorg-safe, idempotent processor that synchronizes on-chain state to the database.
4. **NestJS Backend**: Clean-architecture REST API with Redis caching and BullMQ background jobs.
5. **Liquidation Bot**: Distributed, fault-tolerant service scanning user health factors and executing liquidations.
6. **Redis Infrastructure**: Handles API rate limiting, caching, and distributed locks for the bot infrastructure.

---

## ✨ Key Features

- **Robust Smart Contracts**: Features dual-slope interest rate models, reentrancy guards, and access control.
- **Wad & Ray Mathematics**: Industry-standard precision for compound interest and financial calculations to prevent precision loss.
- **Reorg-Safe Indexing**: The custom indexer handles blockchain reorganizations seamlessly with rollback mechanisms.
- **Enterprise Backend**: Built with NestJS, utilizing Redis token bucket rate-limiting and global exception filters.
- **High-Performance Liquidation**: Automated, profit-estimating bot with distributed Redis locking to prevent concurrent executions.
- **Comprehensive Testing**: Covered by Foundry unit, fuzz, and invariant tests, along with Jest-based backend testing.

---

## 📂 Repository Structure

```text
aave-lending/
├── contracts/           # Foundry-based smart contracts (Core, Libraries, Oracle, Tokenization)
├── backend/             # NestJS API backend (PostgreSQL + TypeORM)
├── indexer/             # Blockchain event listener and processor
├── liquidation-bot/     # Automated health factor scanner and executor
├── docker-compose.yml   # Local infrastructure (Postgres, Redis)
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites

- [Node.js](https://nodejs.org/) (v18+ recommended)
- [Docker](https://www.docker.com/) & Docker Compose
- [Foundry](https://getfoundry.sh/) (for on-chain compilation and testing)

### Installation

1. **Clone the repository:**

   ```bash
   git clone <repository_url>
   cd aave-lending
   ```

2. **Start Infrastructure (PostgreSQL & Redis):**

   ```bash
   docker-compose up -d
   ```

3. **Install Backend Dependencies & Run:**

   ```bash
   cd backend
   npm install
   cp .env.example .env # Configure your DB/Redis credentials
   npm run start:dev
   ```

4. **Compile Smart Contracts:**
   ```bash
   cd ../contracts
   forge build
   ```

---

## 🧪 Testing

### Smart Contracts

The contracts are heavily tested using the Foundry framework. This includes unit tests, fuzz testing, and invariant tests to ensure protocol solvency.

```bash
cd contracts
forge test -vvv
```

### Backend

The backend utilizes Jest for unit and end-to-end testing, fully typed and configured.

```bash
cd backend
npm run test
```

---

## 🛡️ Security

This system implements multiple security layers:

- **Smart Contracts**: Full coverage with zero-floating-point math. `nonReentrant` modifiers on all pool interactions. Strict Access Control roles via UUPS.
- **Database**: TypeORM parameterized queries to prevent SQL injection. Strict DB-level constraints (e.g., balances >= 0).
- **Network Layer**: Redis-backed distributed rate limiters to prevent DDoS and API abuse. Distributed bot locks prevent gas wars and duplicate executions.

---

## 📄 License

This project is licensed under the MIT License.
