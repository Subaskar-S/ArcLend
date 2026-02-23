// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {
    DefaultInterestRateStrategy
} from "../../src/interest/DefaultInterestRateStrategy.sol";
import {ILendingPool} from "../../src/interfaces/ILendingPool.sol";

contract InterestRateTest is Test {
    DefaultInterestRateStrategy public strategy;
    address public mockPool = address(0x1111);

    uint256 constant RAY = 1e27;

    function setUp() public {
        strategy = new DefaultInterestRateStrategy(
            mockPool,
            45 * (RAY / 100), // optimalUtilization = 45%
            0, // baseVariableBorrowRate = 0%
            4 * (RAY / 100), // variableRateSlope1 = 4%
            75 * (RAY / 100) // variableRateSlope2 = 75%
        );
    }

    function test_CalculateInterestRates_LowUtilization() public view {
        uint256 reserveFactor = 1000; // 10%
        uint256 availableLiquidity = 800e18;
        uint256 totalVariableDebt = 200e18;
        // Utilization = 200 / 1000 = 20% < 45% (optimal)

        (uint256 liquidityRate, uint256 variableBorrowRate) = strategy
            .calculateInterestRates(
                address(0),
                availableLiquidity,
                totalVariableDebt,
                reserveFactor
            );

        // Expected variable rate: base (0) + 20/45 * 4%
        uint256 expectedVariableRate = (20 * 4 * RAY) / (45 * 100);
        assertApproxEqAbs(variableBorrowRate, expectedVariableRate, 1e12);

        // Expected liquidity rate: variableRate * util (0.2) * (1 - reserveFactor(0.1))
        uint256 expectedLiquidityRate = (expectedVariableRate * 20 * 90) /
            10000;
        assertApproxEqAbs(liquidityRate, expectedLiquidityRate, 1e12);
    }

    function test_CalculateInterestRates_HighUtilization() public view {
        uint256 reserveFactor = 1000; // 10%
        uint256 availableLiquidity = 200e18;
        uint256 totalVariableDebt = 800e18;
        // Utilization = 800 / 1000 = 80% > 45% (optimal)

        (uint256 liquidityRate, uint256 variableBorrowRate) = strategy
            .calculateInterestRates(
                address(0),
                availableLiquidity,
                totalVariableDebt,
                reserveFactor
            );

        // Expected variable rate: base (0) + slope1 (4%) + (80-45)/(100-45) * slope2 (75%)
        uint256 expectedVariableRate = (4 * RAY) /
            100 +
            (35 * 75 * RAY) /
            (55 * 100);
        assertApproxEqAbs(variableBorrowRate, expectedVariableRate, 1e12);
    }
}
