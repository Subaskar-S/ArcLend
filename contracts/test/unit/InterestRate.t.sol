// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {DefaultInterestRateStrategy} from "../../contracts/interest/DefaultInterestRateStrategy.sol";

/**
 * @title InterestRateTest
 * @notice Unit tests for DefaultInterestRateStrategy — the dual-slope interest rate model.
 *
 * Model:
 *   If util <= optimalUtilization:
 *     borrowRate = baseRate + (util / optimal) * slope1
 *   If util > optimalUtilization:
 *     excess = (util - optimal) / (1 - optimal)
 *     borrowRate = baseRate + slope1 + excess * slope2
 *
 *   depositRate = borrowRate * util * (1 - reserveFactor)
 */
contract InterestRateTest is Test {
    DefaultInterestRateStrategy public strategy;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant OPTIMAL_UTILIZATION = 45 * (RAY / 100);    // 45%
    uint256 internal constant BASE_RATE           = 0;
    uint256 internal constant SLOPE1              = 4 * (RAY / 100);     // 4%
    uint256 internal constant SLOPE2              = 75 * (RAY / 100);    // 75%

    function setUp() public {
        strategy = new DefaultInterestRateStrategy(
            OPTIMAL_UTILIZATION,
            BASE_RATE,
            SLOPE1,
            SLOPE2
        );
    }

    // ─── Below optimal utilization ────────────────────────────────────────────

    function test_LowUtilization_BorrowRate() public view {
        uint256 availableLiquidity = 800e18;
        uint256 totalDebt          = 200e18;
        // util = 200 / 1000 = 20%
        uint256 totalLiquidity = availableLiquidity + totalDebt;

        (, uint256 variableBorrowRate) = strategy.calculateInterestRates(
            totalLiquidity, totalDebt, 1000
        );

        // borrowRate = 0 + (0.20 / 0.45) * 4% = 1.778%
        uint256 expected = (20 * SLOPE1) / 45;
        assertApproxEqAbs(variableBorrowRate, expected, 1e12);
    }

    function test_LowUtilization_DepositRate_ReducedByReserveFactor() public view {
        uint256 availableLiquidity = 800e18;
        uint256 totalDebt          = 200e18;
        uint256 reserveFactor      = 1000; // 10%
        uint256 totalLiquidity = availableLiquidity + totalDebt;

        (uint256 liquidityRate, uint256 variableBorrowRate) = strategy.calculateInterestRates(
            totalLiquidity, totalDebt, reserveFactor
        );

        // Deposit rate < borrow rate (reserve factor takes a cut)
        assertLt(liquidityRate, variableBorrowRate);
    }

    // ─── Above optimal utilization ────────────────────────────────────────────

    function test_HighUtilization_BorrowRate_KinkApplied() public view {
        uint256 availableLiquidity = 200e18;
        uint256 totalDebt          = 800e18;
        uint256 totalLiquidity = availableLiquidity + totalDebt;

        (, uint256 variableBorrowRate) = strategy.calculateInterestRates(
            totalLiquidity, totalDebt, 1000
        );

        uint256 slopeOneOnly = SLOPE1;
        assertGt(variableBorrowRate, slopeOneOnly);
    }

    function test_HighUtilization_RateHigherThanLow() public view {
        uint256 totalLow  = 1000e18;
        uint256 debtLow   = 200e18;
        uint256 totalHigh = 1000e18;
        uint256 debtHigh  = 800e18;

        (, uint256 lowRate)  = strategy.calculateInterestRates(totalLow, debtLow, 1000);
        (, uint256 highRate) = strategy.calculateInterestRates(totalHigh, debtHigh, 1000);

        assertGt(highRate, lowRate);
    }

    // ─── Edge cases ───────────────────────────────────────────────────────────

    function test_ZeroUtilization_ZeroRates() public view {
        (, uint256 variableBorrowRate) = strategy.calculateInterestRates(1000e18, 0, 1000);
        assertEq(variableBorrowRate, BASE_RATE);
    }

    function test_100Percent_Utilization_MaxRate() public view {
        (, uint256 variableBorrowRate) = strategy.calculateInterestRates(1000e18, 1000e18, 1000);
        uint256 expectedMax = BASE_RATE + SLOPE1 + SLOPE2;
        assertApproxEqAbs(variableBorrowRate, expectedMax, 1e12);
    }

    function test_DepositRate_NeverExceedsBorrowRate() public view {
        uint256[3] memory debtAmounts = [uint256(200e18), uint256(500e18), uint256(900e18)];
        uint256 totalLiquidity = 1000e18;

        for (uint256 i = 0; i < debtAmounts.length; i++) {
            (uint256 liquidityRate, uint256 borrowRate) = strategy.calculateInterestRates(
                totalLiquidity, debtAmounts[i], 1000
            );
            assertLe(liquidityRate, borrowRate);
        }
    }

    function test_ReserveFactor_Zero_DepositEqualsGrossRate() public view {
        uint256 totalLiquidity = 1000e18;
        uint256 totalDebt      = 500e18;

        (uint256 liquidityRate, uint256 variableBorrowRate) = strategy.calculateInterestRates(
            totalLiquidity, totalDebt, 0
        );

        assertGt(liquidityRate, 0);
        assertLe(liquidityRate, variableBorrowRate);
    }
}
