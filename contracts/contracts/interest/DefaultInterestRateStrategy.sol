// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IInterestRateStrategy} from "../interfaces/IInterestRateStrategy.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {PercentageMath} from "../libraries/PercentageMath.sol";

/**
 * @title DefaultInterestRateStrategy
 * @notice Dual-slope interest rate model (Aave-style).
 *
 * Borrow rate formula:
 * ─────────────────────
 *   If utilization <= optimalUtilization:
 *     borrowRate = baseVariableBorrowRate + (utilization / optimalU) × slope1
 *   Else:
 *     excessFactor = (utilization - optimalU) / (1 - optimalU)
 *     borrowRate = baseVariableBorrowRate + slope1 + excessFactor × slope2
 *
 * Supply rate formula:
 * ─────────────────────
 *   supplyRate = borrowRate × utilization × (1 - reserveFactor)
 *
 * All rates are in ray (1e27) precision.
 */
contract DefaultInterestRateStrategy is IInterestRateStrategy {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    uint256 public immutable OPTIMAL_UTILIZATION_RATE;
    uint256 public immutable BASE_VARIABLE_BORROW_RATE;
    uint256 public immutable VARIABLE_RATE_SLOPE1;
    uint256 public immutable VARIABLE_RATE_SLOPE2;
    uint256 public immutable EXCESS_UTILIZATION_RATE;

    constructor(
        uint256 optimalUtilizationRate,
        uint256 baseVariableBorrowRate,
        uint256 variableRateSlope1,
        uint256 variableRateSlope2
    ) {
        require(optimalUtilizationRate <= WadRayMath.RAY, "IRS: optimal rate > 100%");
        OPTIMAL_UTILIZATION_RATE = optimalUtilizationRate;
        EXCESS_UTILIZATION_RATE = WadRayMath.RAY - optimalUtilizationRate;
        BASE_VARIABLE_BORROW_RATE = baseVariableBorrowRate;
        VARIABLE_RATE_SLOPE1 = variableRateSlope1;
        VARIABLE_RATE_SLOPE2 = variableRateSlope2;
    }

    /**
     * @inheritdoc IInterestRateStrategy
     */
    function calculateInterestRates(
        uint256 totalLiquidity,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) external view override returns (uint256 liquidityRate, uint256 variableBorrowRate) {
        uint256 utilizationRate = totalLiquidity == 0
            ? 0
            : totalVariableDebt.rayDiv(totalLiquidity);

        if (utilizationRate <= OPTIMAL_UTILIZATION_RATE) {
            uint256 utilizationRateToOptimal = utilizationRate.rayDiv(OPTIMAL_UTILIZATION_RATE);
            variableBorrowRate =
                BASE_VARIABLE_BORROW_RATE +
                VARIABLE_RATE_SLOPE1.rayMul(utilizationRateToOptimal);
        } else {
            uint256 excessUtilizationRateRatio = (utilizationRate - OPTIMAL_UTILIZATION_RATE)
                .rayDiv(EXCESS_UTILIZATION_RATE);

            variableBorrowRate =
                BASE_VARIABLE_BORROW_RATE +
                VARIABLE_RATE_SLOPE1 +
                VARIABLE_RATE_SLOPE2.rayMul(excessUtilizationRateRatio);
        }

        // supplyRate = borrowRate × utilization × (1 - reserveFactor)
        liquidityRate = variableBorrowRate
            .rayMul(utilizationRate)
            .percentMul(PercentageMath.PERCENTAGE_FACTOR - reserveFactor);
    }
}
