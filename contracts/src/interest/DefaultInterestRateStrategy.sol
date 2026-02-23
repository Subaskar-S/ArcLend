// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IInterestRateStrategy} from "../interfaces/IInterestRateStrategy.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {PercentageMath} from "../libraries/PercentageMath.sol";

/**
 * @title DefaultInterestRateStrategy
 * @notice Standard dual-slope interest rate model.
 * @dev All rates and math in ray (1e27).
 */
contract DefaultInterestRateStrategy is IInterestRateStrategy {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    uint256 public immutable OPTIMAL_UTILIZATION_RATE;
    uint256 public immutable BASE_VARIABLE_BORROW_RATE;
    uint256 public immutable VARIABLE_RATE_SLOPE1;
    uint256 public immutable VARIABLE_RATE_SLOPE2;

    constructor(
        uint256 optimalUtilizationRate,
        uint256 baseVariableBorrowRate,
        uint256 variableRateSlope1,
        uint256 variableRateSlope2
    ) {
        OPTIMAL_UTILIZATION_RATE = optimalUtilizationRate;
        BASE_VARIABLE_BORROW_RATE = baseVariableBorrowRate;
        VARIABLE_RATE_SLOPE1 = variableRateSlope1;
        VARIABLE_RATE_SLOPE2 = variableRateSlope2;
    }

    /**
     * @inheritdoc IInterestRateStrategy
     */
    function calculateInterestRates(
        uint256 totalDeposits,
        uint256 totalBorrows,
        uint256 reserveFactor
    )
        external
        view
        override
        returns (uint256 liquidityRate, uint256 variableBorrowRate)
    {
        uint256 availableLiquidity = totalDeposits > totalBorrows
            ? totalDeposits - totalBorrows
            : 0;
        // Total liquidity = available + borrows. If deposits < borrows (shouldn't happen), assume util 100%
        uint256 totalLiquidity = availableLiquidity + totalBorrows;

        uint256 utilizationRate = (totalLiquidity == 0)
            ? 0
            : totalBorrows.rayDiv(totalLiquidity.wadToRay());
        // wait, totalBorrows is wad (underlying amount), totalLiquidity is wad.
        // rayDiv expects rays. So upgrade both?
        // totalBorrows.wadToRay().rayDiv(totalLiquidity.wadToRay()) -> cancels out.
        // But precision: wad/wad = wad. We want ray.
        // so (totalBorrows * RAY) / totalLiquidity.
        // WadRayMath.wadToRay(totalBorrows).rayDiv(WadRayMath.wadToRay(totalLiquidity))
        // This is effectively (totalBorrows * 1e27) / totalLiquidity.

        // Variable Rate logic
        if (utilizationRate <= OPTIMAL_UTILIZATION_RATE) {
            variableBorrowRate =
                BASE_VARIABLE_BORROW_RATE +
                (
                    utilizationRate.rayDiv(OPTIMAL_UTILIZATION_RATE).rayMul(
                        VARIABLE_RATE_SLOPE1
                    )
                );
        } else {
            uint256 excessUtilization = utilizationRate -
                OPTIMAL_UTILIZATION_RATE;
            uint256 maxExcessUtilization = WadRayMath.RAY -
                OPTIMAL_UTILIZATION_RATE;

            variableBorrowRate =
                BASE_VARIABLE_BORROW_RATE +
                VARIABLE_RATE_SLOPE1 +
                (
                    excessUtilization.rayDiv(maxExcessUtilization).rayMul(
                        VARIABLE_RATE_SLOPE2
                    )
                );
        }

        // Liquidity Rate = VariableBorrowRate * Utilization * (1 - ReserveFactor)
        // ReserveFactor is in basis points (1e4).

        uint256 yieldFromVariable = variableBorrowRate.rayMul(utilizationRate);

        liquidityRate = yieldFromVariable.percentMul(
            PercentageMath.PERCENTAGE_FACTOR - reserveFactor
        );
    }
}
