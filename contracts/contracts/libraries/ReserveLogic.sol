// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {DataTypes} from "./DataTypes.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {IInterestRateStrategy} from "../interfaces/IInterestRateStrategy.sol";
import {IDebtToken} from "../interfaces/IDebtToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ReserveLogic
 * @notice Interest accrual and reserve state update library.
 *
 * BUG FIXES vs original:
 * ─────────────────────────
 * [FIX-8] Added updateInterestRates() as a separate public function so facets
 *         can call it after modifying liquidity (deposit/withdraw/borrow/repay).
 *         The original conflated state updates with rate updates in a fragile way.
 * [FIX-9] Import paths corrected to point to contracts/libraries/ not src/libraries/
 */
library ReserveLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    event ReserveDataUpdated(
        address indexed reserve,
        uint256 liquidityRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex
    );

    // ─── View Helpers ─────────────────────────────────────────────────────

    function getNormalizedIncome(
        DataTypes.ReserveData storage reserve
    ) internal view returns (uint256) {
        if (uint40(block.timestamp) == reserve.lastUpdateTimestamp) {
            return reserve.liquidityIndex;
        }
        return _calculateLinearInterest(reserve.currentLiquidityRate, reserve.lastUpdateTimestamp)
            .rayMul(reserve.liquidityIndex);
    }

    function getNormalizedDebt(
        DataTypes.ReserveData storage reserve
    ) internal view returns (uint256) {
        if (uint40(block.timestamp) == reserve.lastUpdateTimestamp) {
            return reserve.variableBorrowIndex;
        }
        return _calculateLinearInterest(reserve.currentVariableBorrowRate, reserve.lastUpdateTimestamp)
            .rayMul(reserve.variableBorrowIndex);
    }

    // ─── State Mutators ───────────────────────────────────────────────────

    /**
     * @notice Accrues interest indexes. Call at the START of every action.
     */
    function updateState(
        DataTypes.ReserveData storage reserve,
        address reserveAddress
    ) internal {
        uint40 lastTimestamp = reserve.lastUpdateTimestamp;
        uint256 previousLiquidityIndex = reserve.liquidityIndex;
        uint256 previousVariableBorrowIndex = reserve.variableBorrowIndex;

        if (lastTimestamp < uint40(block.timestamp)) {
            if (reserve.currentLiquidityRate > 0) {
                uint256 newIndex = _calculateLinearInterest(reserve.currentLiquidityRate, lastTimestamp)
                    .rayMul(previousLiquidityIndex);
                require(newIndex <= type(uint128).max, "RL: LIQ_INDEX_OVERFLOW");
                reserve.liquidityIndex = uint128(newIndex);
            }
            if (reserve.currentVariableBorrowRate > 0) {
                uint256 newIndex = _calculateLinearInterest(reserve.currentVariableBorrowRate, lastTimestamp)
                    .rayMul(previousVariableBorrowIndex);
                require(newIndex <= type(uint128).max, "RL: BORROW_INDEX_OVERFLOW");
                reserve.variableBorrowIndex = uint128(newIndex);
            }
            reserve.lastUpdateTimestamp = uint40(block.timestamp);
        }

        emit ReserveDataUpdated(
            reserveAddress,
            reserve.currentLiquidityRate,
            reserve.currentVariableBorrowRate,
            reserve.liquidityIndex,
            reserve.variableBorrowIndex
        );
    }

    /**
     * @notice Recalculates interest rates based on current liquidity.
     * @param reserve The reserve to update.
     * @param reserveAddress The underlying asset address.
     * @param liquidityAdded Amount added to the pool (deposit/repay).
     * @param liquidityTaken Amount taken from pool (borrow/withdraw).
     */
    function updateInterestRates(
        DataTypes.ReserveData storage reserve,
        address reserveAddress,
        uint256 liquidityAdded,
        uint256 liquidityTaken
    ) internal {
        uint256 availableLiquidity = IERC20(reserveAddress).balanceOf(reserve.aTokenAddress);
        // Apply liquidity changes (before actual transfer in case of reentrancy concerns)
        availableLiquidity = availableLiquidity + liquidityAdded - liquidityTaken;

        uint256 totalVariableDebt = IDebtToken(reserve.debtTokenAddress)
            .scaledTotalSupply()
            .rayMul(reserve.variableBorrowIndex);

        (uint256 newLiquidityRate, uint256 newVariableBorrowRate) =
            IInterestRateStrategy(reserve.interestRateStrategyAddress)
                .calculateInterestRates(
                    availableLiquidity + totalVariableDebt,
                    totalVariableDebt,
                    reserve.reserveFactor
                );

        require(newLiquidityRate <= type(uint128).max, "RL: LIQ_RATE_OVERFLOW");
        require(newVariableBorrowRate <= type(uint128).max, "RL: BORROW_RATE_OVERFLOW");

        reserve.currentLiquidityRate = uint128(newLiquidityRate);
        reserve.currentVariableBorrowRate = uint128(newVariableBorrowRate);
    }

    // ─── Private ──────────────────────────────────────────────────────────

    function _calculateLinearInterest(
        uint256 rate,
        uint40 lastTimestamp
    ) internal view returns (uint256) {
        uint256 timeDelta = block.timestamp - lastTimestamp;
        if (timeDelta == 0) return WadRayMath.RAY;
        return WadRayMath.RAY + (rate * timeDelta) / SECONDS_PER_YEAR;
    }
}
