// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title PercentageMath
 * @notice Basis-point (1e4 = 100%) math for protocol configuration values.
 * @dev Used for: LTV, liquidation threshold, liquidation bonus, reserve factor.
 *      100% = 10_000 basis points.
 *      All operations use explicit rounding direction.
 */
library PercentageMath {
    /// @dev 100% in basis points
    uint256 internal constant PERCENTAGE_FACTOR = 1e4;

    /// @dev Half of 100% for rounding
    uint256 internal constant HALF_PERCENTAGE_FACTOR = 0.5e4;

    /**
     * @notice Applies a percentage to a value, rounding half down.
     * @param value The base value
     * @param percentage The percentage in basis points (e.g., 8000 = 80%)
     * @return result = (value * percentage + HALF_PERCENTAGE_FACTOR) / PERCENTAGE_FACTOR
     */
    function percentMul(
        uint256 value,
        uint256 percentage
    ) internal pure returns (uint256) {
        if (value == 0 || percentage == 0) return 0;

        require(
            value <= (type(uint256).max - HALF_PERCENTAGE_FACTOR) / percentage,
            "PMATH: PERCENT_MUL_OVERFLOW"
        );

        return
            (value * percentage + HALF_PERCENTAGE_FACTOR) / PERCENTAGE_FACTOR;
    }

    /**
     * @notice Divides a value by a percentage, rounding half down.
     * @param value The numerator value
     * @param percentage The percentage in basis points
     * @return result = (value * PERCENTAGE_FACTOR + percentage / 2) / percentage
     */
    function percentDiv(
        uint256 value,
        uint256 percentage
    ) internal pure returns (uint256) {
        require(percentage != 0, "PMATH: PERCENT_DIV_BY_ZERO");
        if (value == 0) return 0;

        require(
            value <= (type(uint256).max - percentage / 2) / PERCENTAGE_FACTOR,
            "PMATH: PERCENT_DIV_OVERFLOW"
        );

        return (value * PERCENTAGE_FACTOR + percentage / 2) / percentage;
    }

    /**
     * @notice Applies a percentage to a value, rounding up.
     * @dev Used when the protocol should not lose precision (e.g., debt calculations).
     */
    function percentMulUp(
        uint256 value,
        uint256 percentage
    ) internal pure returns (uint256) {
        if (value == 0 || percentage == 0) return 0;

        require(
            value <= (type(uint256).max - PERCENTAGE_FACTOR + 1) / percentage,
            "PMATH: PERCENT_MUL_UP_OVERFLOW"
        );

        return (value * percentage + PERCENTAGE_FACTOR - 1) / PERCENTAGE_FACTOR;
    }
}
