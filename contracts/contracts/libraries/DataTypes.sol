// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title DataTypes
 * @notice Core data structures for the ArcLend protocol.
 */
library DataTypes {
    /**
     * @notice Per-asset reserve state.
     * @dev Packed into 5 storage slots for gas efficiency.
     */
    struct ReserveData {
        // ─── Slot 0 ───────────────────────────────────────────────────────
        // Cumulative liquidity index (ray, 1e27), grows as depositors earn interest
        uint128 liquidityIndex;
        // Cumulative variable borrow index (ray, 1e27), grows as borrowers accrue debt
        uint128 variableBorrowIndex;
        // ─── Slot 1 ───────────────────────────────────────────────────────
        // Current annualized liquidity rate paid to depositors (ray)
        uint128 currentLiquidityRate;
        // Current annualized variable borrow rate charged to borrowers (ray)
        uint128 currentVariableBorrowRate;
        // ─── Slot 2 ───────────────────────────────────────────────────────
        // Timestamp of last state update (uint40 fits years past 2100)
        uint40 lastUpdateTimestamp;
        // Bitmask configuration – packed booleans and small values
        uint8 id;          // Reserve list index (max 255 reserves)
        bool isActive;     // Reserve is enabled for interactions
        bool isFrozen;     // No new deposits or borrows (existing positions unaffected)
        bool borrowingEnabled;
        // ─── Slot 3 ───────────────────────────────────────────────────────
        // Addresses of associated contracts
        address aTokenAddress;
        uint16 ltv;                   // Loan-to-value ratio (basis points, e.g. 7500 = 75%)
        uint16 liquidationThreshold;  // Threshold at which positions can be liquidated (basis points)
        // ─── Slot 4 ───────────────────────────────────────────────────────
        address debtTokenAddress;
        uint16 liquidationBonus;     // Bonus for liquidators (basis points, e.g. 10500 = 105%)
        uint16 reserveFactor;        // Protocol fee (basis points, e.g. 1000 = 10%)
        // ─── Slot 5 ───────────────────────────────────────────────────────
        address interestRateStrategyAddress;
    }

    /**
     * @notice User's bitmask configuration across all reserves.
     * @dev Bit layout per reserve (2 bits each):
     *      - bit(2*n)     = 1 → using reserve[n] as collateral
     *      - bit(2*n + 1) = 1 → borrowing from reserve[n]
     */
    struct UserConfigurationMap {
        uint256 data;
    }
}
