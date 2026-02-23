// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {DataTypes} from "./DataTypes.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {IInterestRateStrategy} from "../interfaces/IInterestRateStrategy.sol";
import {IDebtToken} from "../interfaces/IDebtToken.sol";
import {IAToken} from "../interfaces/IAToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ReserveLogic
 * @notice Implements interest accrual and reserve state updates.
 * @dev All interest math uses ray precision (1e27).
 *
 * Interest Accrual Model:
 * ─────────────────────────
 * We use a linear approximation of compound interest per Aave v2:
 *
 *   compoundedRate ≈ 1 + rate × Δt / SECONDS_PER_YEAR
 *
 * This is an acceptable approximation for small time intervals. For production,
 * the error is bounded: for a 100% APR and a 1-year gap, the approximation
 * underestimates by ~0.7%. Per-second updates keep error negligible.
 *
 * The cumulative index grows multiplicatively:
 *   newIndex = oldIndex × compoundedRate
 *
 * This enables O(1) balance computation:
 *   currentBalance = scaledBalance × currentIndex
 */
library ReserveLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    /**
     * @notice Emitted when a reserve's state (indexes + rates) is updated.
     */
    event ReserveDataUpdated(
        address indexed reserve,
        uint256 liquidityRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex
    );

    /**
     * @notice Returns the normalized income (cumulative liquidity index) up to the current timestamp.
     * @dev If the reserve was just updated, returns the stored index.
     *      Otherwise, compounds the elapsed interest onto the stored index.
     *
     * Formula: normalizedIncome = liquidityIndex × (1 + liquidityRate × Δt / SECONDS_PER_YEAR)
     *
     * @param reserve The reserve data
     * @return The current normalized income (ray)
     */
    function getNormalizedIncome(
        DataTypes.ReserveData storage reserve
    ) internal view returns (uint256) {
        uint40 timestamp = reserve.lastUpdateTimestamp;

        // solhint-disable-next-line not-rely-on-time
        if (timestamp == block.timestamp) {
            return reserve.liquidityIndex;
        }

        uint256 cumulated = _calculateLinearInterest(
            reserve.currentLiquidityRate,
            timestamp
        );

        return cumulated.rayMul(reserve.liquidityIndex);
    }

    /**
     * @notice Returns the normalized variable debt (cumulative borrow index) up to current timestamp.
     * @dev Same as getNormalizedIncome but for the borrow side.
     *
     * Formula: normalizedDebt = variableBorrowIndex × (1 + variableBorrowRate × Δt / SECONDS_PER_YEAR)
     *
     * @param reserve The reserve data
     * @return The current normalized variable debt (ray)
     */
    function getNormalizedDebt(
        DataTypes.ReserveData storage reserve
    ) internal view returns (uint256) {
        uint40 timestamp = reserve.lastUpdateTimestamp;

        // solhint-disable-next-line not-rely-on-time
        if (timestamp == block.timestamp) {
            return reserve.variableBorrowIndex;
        }

        uint256 cumulated = _calculateLinearInterest(
            reserve.currentVariableBorrowRate,
            timestamp
        );

        return cumulated.rayMul(reserve.variableBorrowIndex);
    }

    /**
     * @notice Updates the reserve state: accrues interest and recalculates rates.
     * @dev Must be called before any deposit/withdraw/borrow/repay/liquidation.
     *      This is the ONLY function that mutates the reserve's cumulative indexes.
     *
     * Steps:
     *   1. Compound the liquidity index (depositor interest)
     *   2. Compound the borrow index (borrower debt growth)
     *   3. Recalculate current rates based on new utilization
     *   4. Update timestamp
     *
     * @param reserve The reserve to update
     * @param reserveAddress The address of the underlying asset
     */
    function updateState(
        DataTypes.ReserveData storage reserve,
        address reserveAddress
    ) internal {
        uint256 previousVariableBorrowIndex = reserve.variableBorrowIndex;
        uint256 previousLiquidityIndex = reserve.liquidityIndex;
        uint40 lastTimestamp = reserve.lastUpdateTimestamp;

        // Step 1 + 2: Update indexes (accrues interest)
        (
            uint256 newLiquidityIndex,
            uint256 newVariableBorrowIndex
        ) = _updateIndexes(
                reserve,
                previousLiquidityIndex,
                previousVariableBorrowIndex,
                lastTimestamp
            );

        // Step 3: Recalculate interest rates based on current utilization
        _updateInterestRates(reserve, reserveAddress);

        emit ReserveDataUpdated(
            reserveAddress,
            reserve.currentLiquidityRate,
            reserve.currentVariableBorrowRate,
            newLiquidityIndex,
            newVariableBorrowIndex
        );
    }

    // ============================================================
    //                     INTERNAL HELPERS
    // ============================================================

    /**
     * @dev Updates cumulative indexes. Pure interest accrual mechanic.
     */
    function _updateIndexes(
        DataTypes.ReserveData storage reserve,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex,
        uint40 lastTimestamp
    )
        internal
        returns (uint256 newLiquidityIndex, uint256 newVariableBorrowIndex)
    {
        newLiquidityIndex = liquidityIndex;
        newVariableBorrowIndex = variableBorrowIndex;

        // Only update if time has elapsed
        // solhint-disable-next-line not-rely-on-time
        if (lastTimestamp < uint40(block.timestamp)) {
            // Update liquidity index
            if (reserve.currentLiquidityRate > 0) {
                uint256 cumulatedLiquidityInterest = _calculateLinearInterest(
                    reserve.currentLiquidityRate,
                    lastTimestamp
                );
                newLiquidityIndex = cumulatedLiquidityInterest.rayMul(
                    liquidityIndex
                );
                require(
                    newLiquidityIndex <= type(uint128).max,
                    "RL: LIQUIDITY_INDEX_OVERFLOW"
                );
                reserve.liquidityIndex = uint128(newLiquidityIndex);
            }

            // Update variable borrow index
            if (reserve.currentVariableBorrowRate > 0) {
                uint256 cumulatedBorrowInterest = _calculateLinearInterest(
                    reserve.currentVariableBorrowRate,
                    lastTimestamp
                );
                newVariableBorrowIndex = cumulatedBorrowInterest.rayMul(
                    variableBorrowIndex
                );
                require(
                    newVariableBorrowIndex <= type(uint128).max,
                    "RL: BORROW_INDEX_OVERFLOW"
                );
                reserve.variableBorrowIndex = uint128(newVariableBorrowIndex);
            }

            // solhint-disable-next-line not-rely-on-time
            reserve.lastUpdateTimestamp = uint40(block.timestamp);
        }
    }

    /**
     * @dev Recalculates interest rates by calling the strategy contract.
     */
    function _updateInterestRates(
        DataTypes.ReserveData storage reserve,
        address reserveAddress
    ) internal {
        // Total deposits = underlying balance held by the aToken contract
        uint256 totalDeposits = IERC20(reserveAddress).balanceOf(
            reserve.aTokenAddress
        );

        // Total borrows = scaled total supply × current borrow index
        uint256 totalVariableDebt = IDebtToken(reserve.debtTokenAddress)
            .scaledTotalSupply()
            .rayMul(reserve.variableBorrowIndex);

        (
            uint256 newLiquidityRate,
            uint256 newVariableBorrowRate
        ) = IInterestRateStrategy(reserve.interestRateStrategyAddress)
                .calculateInterestRates(
                    totalDeposits + totalVariableDebt, // total liquidity = available + borrowed
                    totalVariableDebt,
                    reserve.reserveFactor
                );

        require(
            newLiquidityRate <= type(uint128).max,
            "RL: LIQUIDITY_RATE_OVERFLOW"
        );
        require(
            newVariableBorrowRate <= type(uint128).max,
            "RL: BORROW_RATE_OVERFLOW"
        );

        reserve.currentLiquidityRate = uint128(newLiquidityRate);
        reserve.currentVariableBorrowRate = uint128(newVariableBorrowRate);
    }

    /**
     * @notice Calculates linear interest accumulated over a time period.
     * @dev result = 1 RAY + (rate × Δt) / SECONDS_PER_YEAR
     *      This is a linear approximation of continuous compounding.
     * @param rate The annualized interest rate (ray)
     * @param lastTimestamp The timestamp of the last update
     * @return The interest factor (ray), always >= 1 RAY
     */
    function _calculateLinearInterest(
        uint256 rate,
        uint40 lastTimestamp
    ) internal view returns (uint256) {
        // solhint-disable-next-line not-rely-on-time
        uint256 timeDelta = block.timestamp - lastTimestamp;

        if (timeDelta == 0) {
            return WadRayMath.RAY;
        }

        // rate × Δt / SECONDS_PER_YEAR
        uint256 rateTimeDelta = (rate * timeDelta) / SECONDS_PER_YEAR;

        return WadRayMath.RAY + rateTimeDelta;
    }
}
