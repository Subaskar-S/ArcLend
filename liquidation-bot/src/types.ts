/**
 * Shared types for the liquidation bot.
 */

/** Row returned by HealthScanner.scanUnhealthyPositions() */
export interface UnhealthyUser {
    userId: string;
    userAddress: string;
    healthFactor: string;   // NUMERIC(78,0) as string — WAD (1e18)
}

/** Best debt/collateral pair to liquidate for a given user */
export interface LiquidationPair {
    userAddress: string;
    debtAsset: string;          // ERC20 contract address
    collateralAsset: string;    // ERC20 contract address
    /** 50% of total debt (close factor), as a NUMERIC string */
    debtToCover: string;
}

/** Per-market position row used internally for pair selection */
export interface PositionMarket {
    marketId: string;
    assetAddress: string;
    decimals: number;
    liquidationBonus: number;   // basis points, e.g. 10500 = 105%
    scaledATokenBalance: bigint;
    scaledDebtBalance: bigint;
    latestPrice: bigint;        // WAD (1e18)
}
