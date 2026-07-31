# ArcLend — Development Guide

## Project Layout

```
ArcLend/
├── contracts/                  # Solidity smart contracts (Hardhat + EIP-2535 Diamond)
│   ├── contracts/
│   │   ├── Diamond.sol         # Proxy entry point
│   │   ├── DiamondInit.sol     # One-time initializer
│   │   ├── AppStorage.sol      # Shared state struct
│   │   ├── facets/             # Protocol logic (deposit, borrow, liquidate, config)
│   │   ├── libraries/          # Math + logic libraries (WadRayMath, ReserveLogic, ...)
│   │   ├── tokenization/       # AToken, DebtToken
│   │   ├── oracle/             # PriceOracle
│   │   ├── interest/           # DefaultInterestRateStrategy
│   │   └── interfaces/         # IAToken, IDebtToken, IPriceOracle, IInterestRateStrategy
│   ├── deploy/
│   │   └── 00_deploy_all.ts    # Full deployment script
│   └── test/
│       ├── unit/               # Per-facet Hardhat tests (.test.ts) + Foundry (.t.sol)
│       ├── integration/        # Full lifecycle tests
│       ├── fuzz/               # Foundry fuzz tests (WIP)
│       └── invariant/          # Foundry invariant tests (WIP)
│
├── backend/                    # NestJS REST API (PostgreSQL + Redis)
│   └── src/
│       ├── main.ts             # Entry point
│       ├── app.module.ts       # Root module
│       ├── modules/            # Feature modules (markets, users, deposits, ...)
│       ├── infrastructure/     # Database, Redis, Queue setup
│       └── shared/             # Guards, filters, interceptors
│
├── indexer/                    # Standalone blockchain event indexer (Node.js)
│   └── src/
│       ├── main.ts             # Entry point
│       ├── sync/               # BlockWatcher, ReorgDetector
│       └── processors/         # EventProcessor, per-event handlers
│
├── liquidation-bot/            # Automated liquidation bot (Node.js)
│   └── src/
│       ├── main.ts             # Entry point + main loop
│       ├── scanner/            # HealthScanner (reads DB)
│       └── executor/           # LiquidationExecutor (calls contract)
│
├── docker-compose.yml          # PostgreSQL 15 + Redis 7
├── .env.example                # Environment variable template
├── ARCHITECTURE.md             # System design overview
├── CLAUDE.md                   # AI agent rules and coding standards
└── QUICK_START.md              # Get running in 10 minutes
```

---

## Service Architecture

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
                  │                     │
              REST reads           scans HF < 1e18
                                   executes liquidation
                          │
                        Redis
                   (cache + locks)
```

---

## Coding Standards

See **CLAUDE.md** for the full ruleset. This section summarizes per-layer conventions.

### Smart Contracts

**File naming**: `PascalCase.sol` for contracts, `PascalCase.sol` for libraries.

**Imports order** (one blank line between groups):
1. OpenZeppelin
2. Local libraries
3. Local interfaces
4. Local contracts

**Function order inside a contract**:
1. Events
2. Errors / constants
3. External functions
4. Public functions
5. Internal functions
6. Private functions

**Every external/public function must**:
- Call `LibAccessControl.requireNotPaused()` first (user-facing actions)
- Call `reserve.updateState(asset)` before reading any index
- Follow Checks → Effects → Interactions (CEI)
- Have a NatSpec `@notice`

**Fixed-point math**:
- Wad (1e18): token balances, health factor, prices
- Ray (1e27): liquidity index, borrow index, interest rates
- Basis points (1e4): LTV, liquidation threshold, bonus, reserve factor

```solidity
// Always comment units
uint256 normalizedIncome = reserve.getNormalizedIncome(); // ray
uint256 userBalance = scaledBalance.rayMul(normalizedIncome); // wad
```

---

### NestJS Backend

**Module structure** — every feature module must have:
```
modules/<feature>/
├── <feature>.module.ts       # Wires providers + exports
├── <feature>.controller.ts   # HTTP layer only
├── <feature>.service.ts      # Business logic
├── dto/
│   └── create-<feature>.dto.ts
└── entities/
    └── <feature>.entity.ts
```

**Controller rules**:
- Never put business logic in a controller
- Always use typed DTOs for request bodies
- Always return typed response objects

**Service rules**:
- Never return TypeORM entity objects directly to controllers — map to plain objects
- Throw NestJS HTTP exceptions (`NotFoundException`, `BadRequestException`)
- Never swallow errors silently

**DTO rules**:
- Use `class-validator` decorators on every field
- Use `@IsEthereumAddress()` for wallet addresses
- Use `@IsNumberString()` for on-chain amounts (bigint strings)

```typescript
export class CreateDepositDto {
    @IsEthereumAddress()
    userAddress: string;

    @IsUUID()
    marketId: string;

    @IsNumberString()
    amount: string; // stored as NUMERIC(78,0) — keep as string
}
```

---

### Indexer

**Key responsibilities**:
1. Maintain `block_sync_state` cursor
2. Fetch logs filtered to the Diamond contract address
3. Parse each log using the contract ABI
4. Route parsed events to the correct handler
5. Upsert `raw_events` with idempotency
6. Update `deposits`, `borrows`, `liquidations`, `user_positions`
7. Detect and handle chain reorgs

**Idempotency rule**: Every insert uses `ON CONFLICT (tx_hash, log_index) DO NOTHING`.

**Transaction rule**: Every block's writes happen inside a single `BEGIN/COMMIT` transaction.

**Reorg handling**: On a detected reorg, roll back derived tables (deposits, borrows, user_positions) to the last safe block, then re-index forward.

**Chain ID**: Never hardcode chain ID. Read it from the provider at startup:
```typescript
const network = await this.provider.getNetwork();
const chainId = Number(network.chainId);
```

---

### Liquidation Bot

**Main loop**:
1. `HealthScanner.scanUnhealthyPositions()` — query `user_positions` where `health_factor < 1e18`
2. For each unhealthy user: acquire Redis distributed lock (`SET NX PX`)
3. Select best debt/collateral pair (highest debt value first)
4. Pre-approve the lending pool to spend the debt token
5. Call `LiquidationExecutor.liquidate()`
6. Release lock on success or timeout

**Lock key format**: `liquidation-lock:<chainId>:<userAddress>`

**Lock TTL**: 30 seconds maximum — enough to broadcast + confirm a tx

---

## Adding a New Feature Module (Backend)

1. Generate with NestJS CLI (or create manually):
   ```bash
   cd backend
   npx nest generate module modules/repayments
   npx nest generate controller modules/repayments
   npx nest generate service modules/repayments
   ```

2. Create entity in `modules/repayments/entities/repayment.entity.ts`

3. Create DTO in `modules/repayments/dto/create-repayment.dto.ts`

4. Register entity in `AppModule` TypeORM config or add to `entities` glob

5. Register the new module in `app.module.ts` imports

6. Write a unit test in `modules/repayments/repayments.service.spec.ts`

---

## Adding a New Facet (Contracts)

1. Create `contracts/contracts/facets/MyFacet.sol`
   - Import `AppStorage` and `LibAppStorage`
   - Import `LibAccessControl`
   - All user-facing functions call `requireNotPaused()` first
   - No state variables — use `AppStorage`

2. Add any new fields to `AppStorage.sol` (append only, never reorder)

3. Add the facet to `deploy/00_deploy_all.ts`:
   ```typescript
   const myFacet = await deployFacet('MyFacet');
   cuts.push(facetCut(myFacet, FacetCutAction.Add, getSelectors(myFacet)));
   ```

4. Write unit tests in `test/unit/MyFacet.test.ts`

---

## Error Handling Patterns

### Solidity

```solidity
// Specific, namespaced error messages
require(amount > 0, "LendingPoolFacet: amount must be > 0");
require(reserve.isActive, "LendingPoolFacet: reserve not active");
require(healthFactor >= WAD, "LendingPoolFacet: health factor below threshold");
```

### TypeScript (NestJS)

```typescript
// Typed exceptions with context
throw new NotFoundException(`Market with asset ${assetAddress} not found`);
throw new BadRequestException(`Amount must be a positive integer string`);
```

### TypeScript (Indexer / Bot)

```typescript
// Log then rethrow — never swallow
try {
    await this.processBlock(block);
} catch (error) {
    console.error(`Failed to process block ${block.number}:`, error);
    throw error; // let the outer loop decide recovery strategy
}
```

---

## Testing Patterns

### Smart Contracts (Hardhat/Chai)

```typescript
describe('LendingPoolFacet', () => {
    let diamond: Contract;
    let usdc: ERC20Mock;
    let depositor: SignerWithAddress;

    beforeEach(async () => {
        ({ diamond, usdc, depositor } = await loadFixture(deployFixture));
    });

    it('mints aTokens on deposit', async () => {
        await usdc.connect(depositor).approve(diamond.address, AMOUNT);
        await diamond.connect(depositor).deposit(usdc.address, AMOUNT, depositor.address);

        const aToken = IAToken__factory.connect(await diamond.getReserveAToken(usdc.address), depositor);
        expect(await aToken.balanceOf(depositor.address)).to.equal(AMOUNT);
    });
});
```

### NestJS (Jest)

```typescript
describe('DepositsService', () => {
    let service: DepositsService;
    let repo: jest.Mocked<Repository<DepositEntity>>;

    beforeEach(async () => {
        const module = await Test.createTestingModule({
            providers: [
                DepositsService,
                { provide: getRepositoryToken(DepositEntity), useValue: mockRepository() },
            ],
        }).compile();

        service = module.get(DepositsService);
        repo = module.get(getRepositoryToken(DepositEntity));
    });

    it('findAllByUserId returns deposits for a user', async () => {
        repo.find.mockResolvedValue([mockDeposit]);
        const result = await service.findAllByUserId('user-uuid');
        expect(result).toHaveLength(1);
    });
});
```

---

## Code Review Checklist

**Smart Contracts**
- [ ] No state variables declared in facet contracts
- [ ] `requireNotPaused()` called first in all user-facing functions
- [ ] `updateState(asset)` called before reading any index
- [ ] CEI pattern followed
- [ ] NatSpec present on all external/public functions
- [ ] Fixed-point math uses WadRayMath / PercentageMath — no raw arithmetic
- [ ] Events emitted after all state changes

**Backend**
- [ ] No business logic in controllers
- [ ] All DTOs validated with `class-validator`
- [ ] No `any` types
- [ ] All promises awaited or handled
- [ ] NestJS HTTP exceptions used (not raw `Error`)
- [ ] New module registered in `app.module.ts`

**Indexer / Bot**
- [ ] All SQL queries parameterized
- [ ] Multi-step writes in explicit transactions
- [ ] `ON CONFLICT DO NOTHING` on all idempotent inserts
- [ ] Chain ID read from provider, not hardcoded
- [ ] Errors logged before rethrowing

**General**
- [ ] No commented-out code
- [ ] No `console.log` left in production paths (use proper logger)
- [ ] No `.env` values committed — only `.env.example`
- [ ] Tests added or updated
- [ ] PR under 300 lines changed
