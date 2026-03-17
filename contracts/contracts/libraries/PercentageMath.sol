// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title PercentageMath
 * @notice Basis-point (1e4) fixed-point math library.
 * @dev Used for liquidation thresholds, bonuses, and reserve factors.
 *      PERCENTAGE_FACTOR = 10000 = 100%
 *      Example: percentMul(1000e18, 5000) = 500e18 (50%)
 */
library PercentageMath {
    uint256 internal constant PERCENTAGE_FACTOR = 1e4; // 100%
    uint256 internal constant HALF_PERCENTAGE_FACTOR = 0.5e4;

    function percentMul(uint256 value, uint256 percentage) internal pure returns (uint256) {
        if (value == 0 || percentage == 0) return 0;
        require(value <= (type(uint256).max - HALF_PERCENTAGE_FACTOR) / percentage, "PM: MUL_OVERFLOW");
        return (value * percentage + HALF_PERCENTAGE_FACTOR) / PERCENTAGE_FACTOR;
    }

    function percentDiv(uint256 value, uint256 percentage) internal pure returns (uint256) {
        require(percentage != 0, "PM: DIV_BY_ZERO");
        uint256 halfPercentage = percentage / 2;
        require(value <= (type(uint256).max - halfPercentage) / PERCENTAGE_FACTOR, "PM: DIV_OVERFLOW");
        return (value * PERCENTAGE_FACTOR + halfPercentage) / percentage;
    }
}
