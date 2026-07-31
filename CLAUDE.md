# ArcLend Development Guide

## General Instructions

You are a TypeScript and Solidity engineer working on ArcLend — a production-grade DeFi lending protocol inspired by Aave v2/v3, built with an EIP-2535 Diamond proxy, a NestJS indexing backend, a blockchain indexer, and an automated liquidation bot.

---

## MANDATORY RULES — NEVER VIOLATE THESE

1. **Project-grounded analysis only**
   Always read and analyze the actual files in the current project before proposing any change.
   Do NOT guess, do NOT rely on training data, do NOT assume "it probably looks like this".
   If the needed function, class, interface, or pattern is not present in the codebase, ask the user for the file before proceeding.

2. **Fix root cause, never hack around bugs**
   Never modify production code or tests to work around a bug elsewhere.
   If a test fails because of a bug in production code, fix the bug — do not add guards, special cases, or workarounds in the test.
   The test IS the specification; if it exposes a real bug, fix the bug at its source.

3. **Minimal change philosophy**
   Solve the requested issue with the smallest possible number of added or changed lines.
   - Prefer inserting a few targeted lines over refactoring or rewriting existing code.
   - Do NOT refactor, rename, or restructure unless the user explicitly asks.
   - Do NOT make architectural changes without explicit user approval.

4. **Strict adherence to coding standards**
   Follow the coding standards defined in this document at all times:
   - Solidity: NatSpec on all public/external functions, explicit visibility, explicit error messages.
   - TypeScript: strict mode, no `any`, consistent async/await, no unhandled promises.
   - Naming, file layout, import order, and formatting rules defined below must be followed.

5. **When in doubt**
   If something is missing or unclear, ask the user for clarification before writing any code.

---

## Response Format When Given a Task

- First, briefly list which files you examined.
- Then, describe the minimal change you propose (exact lines to add/modify, file names).
- Only after the user approves, output the actual code.

You are not allowed to rewrite large sections, introduce new classes, change architecture, or perform any refactoring unless explicitly requested.
Your default mode is **"tiny, surgical insertion into existing code"**.

---

## Important Guidelines

- Do not commit changes without explicit user permission.
- When reporting a bug, start by writing a test that reproduces it.
- Never commit code you don't understand.
- Never assume or speculate about something unclear.
- Always run tests before committing.
- Always run the linter and formatter before committing.
- Always run the build before committing.
- Operate interactively with the user on a step-by-step basis.

---

## Service Commands

### Smart Contracts (`contracts/`)

```bash
# Install all deps from repo root
pnpm install

# Compile
pnpm --filter @arclend/contracts compile

# Run Hardhat unit + integration tests
pnpm --filter @arclend/contracts test

# Run specific test file
pnpm --filter @arclend/contracts exec hardhat test test/unit/LendingPool.test.ts

# Deploy to local Hardhat node
pnpm --filter @arclend/contracts deploy:localhost

# Start local Hardhat node (run in separate terminal)
pnpm --filter @arclend/contracts exec hardhat node
```

### Backend (`backend/`)

```bash
# Development (watch mode — run manually in terminal)
pnpm --filter aave-lending-backend start:dev

# Production build
pnpm --filter aave-lending-backend build

# Tests
pnpm --filter aave-lending-backend test
pnpm --filter aave-lending-backend test:e2e
```

### Indexer (`indexer/`)

```bash
# Start (run manually in terminal)
pnpm --filter aave-lending-indexer start

# Typecheck
pnpm --filter aave-lending-indexer typecheck
```

### Liquidation Bot (`liquidation-bot/`)

```bash
# Start (run manually in terminal)
pnpm --filter aave-lending-liquidator start

# Typecheck
pnpm --filter aave-lending-liquidator typecheck
```

### Infrastructure (Docker)

```bash
# Start PostgreSQL + Redis
docker-compose up -d

# Stop
docker-compose down

# View logs
docker-compose logs -f
```

---

## Solidity Code Style

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Contracts/Libraries | PascalCase | `LendingPoolFacet`, `ReserveLogic` |
| Interfaces | `I` prefix + PascalCase | `IAToken`, `IPriceOracle` |
| Functions | camelCase | `deposit()`, `liquidationCall()` |
| Events | PascalCase | `Deposit`, `LiquidationCall` |
| State variables | camelCase | `liquidityIndex`, `priceOracle` |
| Constants | SCREAMING_SNAKE_CASE | `LIQUIDATION_CLOSE_FACTOR_PERCENT` |
| Errors | PascalCase with context | `"LiquidationFacet: no debt"` |
| Struct fields | camelCase | `healthFactor`, `userDebt` |
| Mapping keys | descriptive | `s.reserves[asset]`, `s.usersConfig[user]` |

### Formatting Rules

- **Pragma**: Always `pragma solidity 0.8.21;` (exact version, no `^`)
- **SPDX**: Every file starts with `// SPDX-License-Identifier: MIT`
- **Imports**: OpenZeppelin first, then local libraries, then interfaces
- **Visibility**: Always explicit — `external`, `public`, `internal`, `private`
- **NatSpec**: Every `external`/`public` function gets `@notice` and `@param`/`@return`
- **Events**: Emit events AFTER all state changes, never before
- **Checks-Effects-Interactions**: Always in this order

```solidity
// Good — CEI pattern
function deposit(address asset, uint256 amount) external {
    // CHECKS
    ValidationLogic.validateDeposit(reserve, amount);
    
    // EFFECTS
    reserve.updateInterestRates(asset, amount, 0);
    IAToken(reserve.aTokenAddress).mint(onBehalfOf, amount, reserve.liquidityIndex);
    
    // INTERACTIONS
    IERC20(asset).safeTransferFrom(msg.sender, reserve.aTokenAddress, amount);
    
    emit Deposit(asset, msg.sender, onBehalfOf, amount);
}
```

### Fixed-Point Math Rules

- Use `WadRayMath` for all 1e18 (wad) and 1e27 (ray) arithmetic — never raw `*` or `/`
- Use `PercentageMath` for basis-point (1e4) calculations
- Comment units clearly: `// liquidityIndex is ray (1e27)`
- Never mix wad and ray without explicit conversion

```solidity
// Good
uint256 balance = scaledBalance.rayMul(reserve.liquidityIndex); // result in wad

// Bad — silent precision loss
uint256 balance = scaledBalance * reserve.liquidityIndex / 1e27;
```

### Diamond Pattern Rules

- All state lives in `AppStorage` — never declare state variables in facet contracts
- Access storage exclusively via `LibAppStorage.appStorage()`
- Call `reserve.updateState(asset)` before reading any index from any reserve
- Call `LibAccessControl.requireNotPaused()` as the first line of every user-facing function
- Never call `delegatecall` from within a facet

---

## TypeScript Code Style

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Classes | PascalCase | `HealthScanner`, `BlockWatcher` |
| Interfaces/Types | PascalCase | `UserPosition`, `ReserveData` |
| Functions/Methods | camelCase | `scanUnhealthyPositions()`, `processLog()` |
| Variables | camelCase | `unhealthyUsers`, `lastBlock` |
| Constants | SCREAMING_SNAKE_CASE | `SCAN_INTERVAL_MS`, `LOCK_TTL_MS` |
| NestJS modules | PascalCase + suffix | `DepositsModule`, `MarketsService` |
| DTOs | PascalCase + `Dto` | `CreateDepositDto`, `CreateBorrowDto` |
| Entities | PascalCase + `Entity` | `DepositEntity`, `MarketEntity` |
| Files | kebab-case | `health-scanner.ts`, `borrow.entity.ts` |
| Directories | kebab-case | `liquidation-bot/`, `borrows/` |

### Formatting Rules

- **Indent**: 4 spaces
- **Quotes**: single quotes for strings
- **Semicolons**: always
- **Trailing commas**: always in multi-line objects/arrays
- **Line length**: 120 characters max
- **No `any`**: always type explicitly; use `unknown` when truly unknown
- **No unhandled promises**: always `await` or `.catch()`
- **No floating promises in constructors**: use factory methods or `onModuleInit`

```typescript
// Good
const result = await this.db.query<UserPosition>(
    'SELECT * FROM user_positions WHERE health_factor < $1',
    [WAD],
);

// Bad
this.db.query(...).then(r => doSomething(r)); // unhandled rejection
```

### Async Rules

- All database calls are `async/await`
- Never `await` inside a `forEach` — use `Promise.all()` or `for...of`
- Every `try/catch` in a service must log the error before rethrowing

```typescript
// Good
await Promise.all(users.map(user => this.processUser(user)));

// Bad
users.forEach(async (user) => {
    await this.processUser(user); // errors silently swallowed
});
```

### NestJS Rules

- Controllers handle HTTP only — no business logic
- Services contain business logic — no HTTP concepts
- Entities represent the database schema — no domain logic
- DTOs validate incoming data with `class-validator` decorators
- Every injected dependency must be declared in the module's `providers` and `imports`

---

## Database Rules

- **All queries are parameterized** — never string-interpolate user input into SQL
- **Idempotency via `ON CONFLICT DO NOTHING`** using `(tx_hash, log_index)` as the unique key
- **BigInt precision**: on-chain amounts stored as `NUMERIC(78,0)` — never as `FLOAT` or `INTEGER`
- **Addresses**: stored as lowercase `VARCHAR(42)` — normalize at the entry point
- **Timestamps**: always `TIMESTAMP WITH TIME ZONE` — never `TIMESTAMP` without timezone
- **Migrations**: all schema changes go in numbered migration files (`002_add_repayments.sql`)
- **No ORM magic for indexer/bot** — use raw `pg` pool with explicit transactions
- Always wrap multi-step writes in a `BEGIN / COMMIT / ROLLBACK` transaction

```typescript
// Good — explicit transaction
const client = await this.db.connect();
try {
    await client.query('BEGIN');
    await client.query('INSERT INTO deposits ...', [...]);
    await client.query('UPDATE user_positions ...', [...]);
    await client.query('COMMIT');
} catch (e) {
    await client.query('ROLLBACK');
    throw e;
} finally {
    client.release();
}
```

---

## Error Handling Rules

**Every error condition MUST be handled explicitly.**

- NestJS services: throw `NotFoundException`, `BadRequestException`, etc. — never raw `Error`
- Indexer/bot: log + rethrow — never swallow errors silently
- Solidity: use `require(condition, "Context: specific message")` — never bare `revert()`
- Document expected failure modes in function-level comments

```typescript
// Good
const user = await this.usersService.findOne(userId);
if (!user) {
    throw new NotFoundException(`User ${userId} not found`);
}

// Bad
const user = await this.usersService.findOne(userId);
return user.address; // throws uncaught TypeError if user is null
```

---

## PR Size Limit

- **PRs max 300 lines changed** — small, reviewable submissions only
- **Functions max ~80 lines** — split into helpers if longer
- **No deep nesting** — more than 3 levels: extract a function
- **No magic numbers** — use named constants
- **No stubs in production code** — either implement or remove
- **No commented-out code** in merged PRs — delete it

---

## Security Rules

- **Never log private keys**, wallet addresses from `.env`, or raw secrets
- **Never commit `.env`** — only `.env.example` with placeholder values
- **Input validation on all API endpoints** via `class-validator` DTOs
- **Parameterized SQL always** — no string interpolation
- **On-chain amounts**: validate that amounts > 0 before any contract interaction
- **PRIVATE_KEY in `.env`** is a Hardhat test key — rotate immediately for any non-local deployment

---

## Reasoning Rules

Before answering any prompt, work through it step-by-step:

- **UNDERSTAND:** What is the core question?
- **LOCATE:** Which files in the codebase are relevant?
- **ANALYZE:** What does the existing code actually do?
- **PLAN:** What is the minimal change needed?
- **VERIFY:** Does the change break anything downstream?

Be thorough in search. Read the actual file before making claims about it.

---

**Date**: July 31, 2026
