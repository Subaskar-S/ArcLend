# ArcLend — Smart Contracts Guide

## Overview

ArcLend's smart contracts implement an Aave v2/v3-inspired lending protocol using the **EIP-2535 Diamond multi-facet proxy pattern**. This allows the protocol to be upgraded without redeploying the main contract or losing state.

All protocol state is stored in a single `AppStorage` struct accessed via a deterministic keccak256 storage slot. Facets contain only logic — never state variables.

---

## Contract Map

```
Diamond.sol                     ← Proxy entry point (all user calls go here)
DiamondInit.sol                 ← One-time initializer (roles, oracle)
AppStorage.sol                  ← Shared state struct + storage slot accessor

facets/
├── DiamondCutFacet.sol         ← Add/replace/remove facets
├── DiamondLoupeFacet.sol       ← Introspect facets and selectors
├── OwnershipFacet.sol          ← Owner management
├── ConfiguratorFacet.sol       ← Reserve init, risk params, pause/unpause
├── LendingPoolFacet.sol        ← deposit(), withdraw()
├── BorrowFacet.sol             ← borrow(), repay()
├── LiquidationFacet.sol        ← liquidationCall()
└── ViewFacet.sol               ← Read-only getters (healthFactor, reserveData, ...)

libraries/
├── WadRayMath.sol              ← 1e18 (wad) and 1e27 (ray) fixed-point math
├── PercentageMath.sol          ← Basis-point (1e4) math
├── DataTypes.sol               ← Shared structs (ReserveData, UserConfigurationMap)
├── ReserveLogic.sol            ← Interest accrual (updateState, updateInterestRates)
├── GenericLogic.sol            ← Health factor computation
├── ValidationLogic.sol         ← Pre-action validation
├── LibAccessControl.sol        ← Role management, pause guard
└── LibDiamond.sol              ← EIP-2535 core (diamond storage, cut logic)

tokenization/
├── AToken.sol                  ← Scaled-balance interest-bearing ERC20
└── DebtToken.sol               ← Non-transferable scaled debt ERC20

interest/
└── DefaultInterestRateStrategy.sol  ← Dual-slope kinked interest rate model

oracle/
└── PriceOracle.sol             ← Admin-set prices (WAD, 18 decimals)

interfaces/
├── IAToken.sol
├── IDebtToken.sol
├── IPriceOracle.sol
└── IInterestRateStrategy.sol
```

---

## Core Concepts

### Diamond Storage

All protocol state lives in `AppStorage`. Never declare storage variables in facets.

```solidity
// AppStorage.sol
struct AppStorage {
    mapping(address => DataTypes.ReserveData) reserves;
    mapping(address => DataTypes.UserConfigurationMap) usersConfig;
    address[] reservesList;
    uint256 reservesCount;
    address priceOracle;
    // roles, pause state, etc.
}

library LibAppStorage {
    bytes32 constant STORAGE_SLOT = keccak256("arclend.app.storage");

    function appStorage() internal pure returns (AppStorage storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly { s.slot := slot }
    }
}
```

### ReserveData

Each asset (USDC, WETH, etc.) has a `ReserveData` struct:

```
liquidityIndex          — ray (1e27) — grows as deposit interest accrues
variableBorrowIndex     — ray (1e27) — grows as borrow interest accrues
currentLiquidityRate    — ray (1e27) — current APY for depositors
currentVariableBorrowRate — ray (1e27) — current APR for borrowers
lastUpdateTimestamp     — uint40     — last time updateState() was called
aTokenAddress           — address    — the aToken contract for this reserve
debtTokenAddress        — address    — the DebtToken contract for this reserve
interestRateStrategyAddress — address
ltv                     — uint16     — basis points (e.g. 7500 = 75%)
liquidationThreshold    — uint16     — basis points (e.g. 8000 = 80%)
liquidationBonus        — uint16     — basis points (e.g. 10500 = 105%, a 5% bonus)
reserveFactor           — uint16     — basis points
isActive / isFrozen     — bool
id                      — uint8      — index in reservesList
```

### Scaled Balances

AToken and DebtToken store **scaled balances**, not nominal balances. This is how interest accrues without any per-user transaction.

```
scaledBalance = nominalAmount / currentIndex   (at deposit time)
currentBalance = scaledBalance * currentIndex  (at any later time)
```

Because `currentIndex` increases over time (as interest accrues), `currentBalance` grows automatically without touching the user's storage slot.

---

## Interest Rate Model

`DefaultInterestRateStrategy` implements a dual-slope (kinked) model:

```
Utilization = totalBorrows / totalLiquidity

If utilization <= optimalUtilization:
    borrowRate = baseVariableBorrowRate + (utilization / optimalUtilization) * variableRateSlope1

If utilization > optimalUtilization:
    excess = utilization - optimalUtilization
    normalizedExcess = excess / (1 - optimalUtilization)
    borrowRate = baseVariableBorrowRate + variableRateSlope1 + normalizedExcess * variableRateSlope2

depositRate = borrowRate * utilization * (1 - reserveFactor)
```

All rates are in **ray** (1e27) per second. The frontend displays them as APY after compounding.

---

## Health Factor

```
healthFactor = (Σ collateralValue_i * liquidationThreshold_i) / Σ debtValue_i

Where:
  collateralValue_i  = aTokenBalance_i * price_i   (in base currency, WAD)
  liquidationThreshold_i = per-reserve config, in basis points
  debtValue_i  = debtTokenBalance_i * price_i

HF > 1.0  → position is safe
HF < 1.0  → position is undercollateralized and eligible for liquidation
```

Non-18-decimal assets (e.g. USDC with 6 decimals) are normalized to 18 before multiplication:
```solidity
uint256 amountWad = amount * (10 ** (18 - decimals));
uint256 valueInBase = amountWad.wadMul(oraclePrice);
```

---

## Fixed-Point Math Reference

| Type | Scale | Used For |
|------|-------|---------|
| Wad | 1e18 | Token balances, health factor, prices |
| Ray | 1e27 | Liquidity index, borrow index, interest rates |
| Basis points | 1e4 | LTV, liquidation threshold, bonus, reserve factor |

```solidity
// WadRayMath operations
a.wadMul(b)   // (a * b + WAD/2) / WAD  — wad × wad → wad
a.wadDiv(b)   // (a * WAD + b/2) / b    — wad / wad → wad
a.rayMul(b)   // (a * b + RAY/2) / RAY  — ray × ray → ray
a.rayDiv(b)   // (a * RAY + b/2) / b    — ray / ray → ray

// PercentageMath operations
a.percentMul(bps)  // (a * bps + HALF_PERCENT) / PERCENTAGE_FACTOR
a.percentDiv(bps)  // (a * PERCENTAGE_FACTOR + bps/2) / bps
```

---

## Liquidation Flow

```
1. Liquidator calls: liquidationCall(collateralAsset, debtAsset, user, debtToCover)

2. LiquidationFacet:
   a. updateState() on BOTH reserves          ← [FIX-5] must happen before reading indexes
   b. Check health factor < 1.0
   c. Compute max liquidatable debt (50% close factor)
   d. Compute collateral to seize (including liquidation bonus)
   e. Cap collateral at user's actual balance  ← [FIX-6]
   f. Burn debt tokens from user
   g. Transfer collateral aTokens to liquidator
   h. updateInterestRates() on both reserves

3. Liquidator receives: collateralAmount * (1 + liquidationBonus) worth of collateral
   for covering: debtToCover worth of debt
```

**Before calling `liquidationCall()`**, the liquidator must:
1. Approve the Diamond contract to spend `debtToCover` of `debtAsset`
2. Have sufficient `debtAsset` balance

---

## Access Control

Roles are stored in `AppStorage.roles` (mapping of role hash → set of addresses).

| Role | Hash | Purpose |
|------|------|---------|
| `DEFAULT_ADMIN_ROLE` | `0x00` | Can grant/revoke any role |
| `POOL_ADMIN` | `keccak256("POOL_ADMIN")` | Initialize reserves, update params |
| `EMERGENCY_ADMIN` | `keccak256("EMERGENCY_ADMIN")` | Pause/unpause protocol |

All three are granted to the deployer in `DiamondInit.sol`.

```solidity
// Checking roles
LibAccessControl.requireRole(LibAccessControl.POOL_ADMIN_ROLE);

// Checking pause state (fast — just a bool check)
LibAccessControl.requireNotPaused();
```

---

## Upgrade Process (Adding a Facet)

1. Deploy the new facet contract
2. Call `diamondCut()` with `FacetCutAction.Add` and the function selectors
3. The Diamond now delegates those selectors to the new contract

```typescript
// In deploy script or upgrade script
const newFacet = await ethers.deployContract('NewFacet');

await diamond.diamondCut(
    [{
        facetAddress: await newFacet.getAddress(),
        action: FacetCutAction.Add,
        functionSelectors: getSelectors(newFacet),
    }],
    ethers.ZeroAddress, // no init call
    '0x',
);
```

**Rules for upgrades**:
- Never reorder fields in `AppStorage` — only append new fields at the end
- Never remove fields — set them to zero/false if deprecating
- New facets replacing old ones: use `FacetCutAction.Replace` for changed selectors
- Run the full test suite before and after any `diamondCut`

---

## Oracle

`PriceOracle.sol` is an admin-controlled oracle with a 1-hour staleness guard.

- Prices are in **WAD (1e18)**, denominated in a base currency (e.g. USD)
- In production, replace with Chainlink `AggregatorV3Interface` calls
- The oracle address is set in `DiamondInit` and can be updated by `POOL_ADMIN` via `ConfiguratorFacet`

---

## Running Tests

```bash
cd contracts

# Hardhat TypeScript tests (unit + integration)
npx hardhat test

# Specific file
npx hardhat test test/unit/LendingPool.test.ts
npx hardhat test test/integration/FullLifecycle.test.ts

# With gas report
REPORT_GAS=true npx hardhat test

# Foundry fuzz tests (requires forge installed)
forge test --match-path "test/fuzz/**"
forge test --match-path "test/invariant/**"
```

---

## Known Gaps / TODOs

| Item | Location | Priority |
|------|----------|----------|
| Foundry fuzz tests are stubs | `test/fuzz/`, `test/invariant/` | Medium |
| PriceOracle needs Chainlink integration for production | `oracle/PriceOracle.sol` | High (for mainnet) |
| No `repay` or `withdraw` events in integration tests | `test/integration/` | Low |
| No stable borrow rate mode | — | Out of scope for MVP |
