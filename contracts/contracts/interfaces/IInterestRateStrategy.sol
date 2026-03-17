// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IInterestRateStrategy {
    /**
     * @notice Calculates borrow and liquidity rates.
     * @param totalLiquidity Total liquidity (available + borrowed) in the pool.
     * @param totalVariableDebt Total outstanding variable debt.
     * @param reserveFactor Protocol fee as basis points.
     * @return liquidityRate The supply APY (ray, 1e27).
     * @return variableBorrowRate The borrow APY (ray, 1e27).
     */
    function calculateInterestRates(
        uint256 totalLiquidity,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) external view returns (uint256 liquidityRate, uint256 variableBorrowRate);
}
