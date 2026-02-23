// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title IInterestRateStrategy
 * @notice Interface for the interest rate strategy contracts.
 */
interface IInterestRateStrategy {
    /**
     * @notice Calculates the interest rates for a reserve.
     * @param totalDeposits Total liquidity (underlying) in the reserve
     * @param totalBorrows Total variable borrows
     * @param reserveFactor The reserve's reserve factor (basis points, 1e4)
     * @return liquidityRate The supply rate (ray)
     * @return variableBorrowRate The variable borrow rate (ray)
     */
    function calculateInterestRates(
        uint256 totalDeposits,
        uint256 totalBorrows,
        uint256 reserveFactor
    ) external view returns (uint256 liquidityRate, uint256 variableBorrowRate);
}
