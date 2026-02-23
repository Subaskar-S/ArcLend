// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title DataTypes
 * @notice Protocol-wide data structures.
 * @dev Separated from implementation to prevent tight coupling and allow
 *      shared usage across libraries without circular imports.
 */
library DataTypes {
    /**
     * @notice Per-reserve configuration and state.
     * @dev Packed to minimize storage slots. All rate/index fields are in ray (1e27).
     *
     * Storage layout (critical for UUPS — never reorder):
     *   Slot 0: liquidityIndex (256 bits)
     *   Slot 1: variableBorrowIndex (256 bits)
     *   Slot 2: currentLiquidityRate (256 bits)
     *   Slot 3: currentVariableBorrowRate (256 bits)
     *   Slot 4: lastUpdateTimestamp (40 bits) + config packed
     *   ...
     */
    struct ReserveData {
        // ---- Cumulative indexes (ray) ---- //
        /// @dev Cumulative liquidity index. Starts at 1 RAY.
        /// Represents the interest accumulated by depositors since reserve creation.
        uint128 liquidityIndex;
        /// @dev Cumulative variable borrow index. Starts at 1 RAY.
        /// Represents the interest accumulated by borrowers since reserve creation.
        uint128 variableBorrowIndex;
        // ---- Current rates (ray) ---- //
        /// @dev Current annualized supply rate (what depositors earn)
        uint128 currentLiquidityRate;
        /// @dev Current annualized variable borrow rate
        uint128 currentVariableBorrowRate;
        // ---- Timestamp ---- //
        /// @dev Timestamp of the last state update
        uint40 lastUpdateTimestamp;
        // ---- Reserve ID ---- //
        /// @dev Sequential ID for iterating over all reserves
        uint16 id;
        // ---- Token addresses ---- //
        /// @dev Address of the interest-bearing aToken
        address aTokenAddress;
        /// @dev Address of the debt token
        address debtTokenAddress;
        /// @dev Address of the interest rate strategy contract
        address interestRateStrategyAddress;
        // ---- Configuration (basis points, 1e4 = 100%) ---- //
        /// @dev Loan-to-Value ratio (max borrow power as % of collateral)
        uint16 ltv;
        /// @dev Liquidation threshold (collateral value threshold for liquidation)
        uint16 liquidationThreshold;
        /// @dev Liquidation bonus (extra collateral % liquidator receives)
        uint16 liquidationBonus;
        /// @dev Reserve factor (% of interest that goes to protocol treasury)
        uint16 reserveFactor;
        // ---- Flags ---- //
        /// @dev Whether the reserve is active for operations
        bool isActive;
        /// @dev Whether the reserve is frozen (no new deposits/borrows, only repay/withdraw)
        bool isFrozen;
        /// @dev Whether borrowing is enabled
        bool borrowingEnabled;
    }

    /**
     * @notice Per-user configuration bitmap.
     * @dev Compact representation: each reserve uses 2 bits.
     *      Bit 2*i: user is depositing in reserve i
     *      Bit 2*i+1: user is borrowing from reserve i
     *      Supports up to 128 reserves (256 bits / 2 bits per reserve).
     */
    struct UserConfigurationMap {
        uint256 data;
    }

    /**
     * @notice Parameters for executeDeposit
     */
    struct ExecuteDepositParams {
        address asset;
        uint256 amount;
        address onBehalfOf;
    }

    /**
     * @notice Parameters for executeWithdraw
     */
    struct ExecuteWithdrawParams {
        address asset;
        uint256 amount;
        address to;
        uint256 reservesCount;
        address oracle;
    }

    /**
     * @notice Parameters for executeBorrow
     */
    struct ExecuteBorrowParams {
        address asset;
        uint256 amount;
        address onBehalfOf;
        uint256 reservesCount;
        address oracle;
    }

    /**
     * @notice Parameters for executeRepay
     */
    struct ExecuteRepayParams {
        address asset;
        uint256 amount;
        address onBehalfOf;
    }

    /**
     * @notice Parameters for executeLiquidationCall
     */
    struct ExecuteLiquidationCallParams {
        address collateralAsset;
        address debtAsset;
        address user;
        uint256 debtToCover;
        uint256 reservesCount;
        address oracle;
    }
}
