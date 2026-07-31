// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {WadRayMath} from "../../contracts/libraries/WadRayMath.sol";
import {PercentageMath} from "../../contracts/libraries/PercentageMath.sol";

/**
 * @title LendingPoolMathTest
 * @notice Unit tests for the math operations used by LendingPoolFacet.
 *
 * Full Diamond integration tests live in test/integration/FullLifecycle.test.ts.
 * These Foundry tests cover the pure math that underpins deposit/withdraw accounting.
 */
contract LendingPoolMathTest is Test {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;

    // ─── aToken scaled balance math ──────────────────────────────────────────

    /**
     * @notice scaledBalance = nominalAmount.rayDiv(liquidityIndex)
     *         currentBalance = scaledBalance.rayMul(liquidityIndex)
     * The round-trip must recover the original amount within ±1 wei.
     */
    function test_ScaledBalance_Roundtrip() public pure {
        uint256 depositAmount  = 1000e18;
        uint256 liquidityIndex = 1.05e27; // 5% accrued interest

        uint256 scaled  = depositAmount.rayDiv(liquidityIndex);
        uint256 current = scaled.rayMul(liquidityIndex);

        assertApproxEqAbs(current, depositAmount, 1);
    }

    /**
     * @notice When the liquidity index grows, the nominal balance grows proportionally.
     */
    function test_InterestAccrual_BalanceGrows() public pure {
        uint256 depositAmount   = 1000e18;
        uint256 indexAtDeposit  = 1e27;      // index = 1.0 RAY at deposit time
        uint256 indexAtWithdraw = 1.1e27;    // 10% interest accrued

        uint256 scaled          = depositAmount.rayDiv(indexAtDeposit);
        uint256 balanceAtWithdraw = scaled.rayMul(indexAtWithdraw);

        // Should be ~1100 (10% more than deposit)
        assertApproxEqAbs(balanceAtWithdraw, 1100e18, 1);
    }

    /**
     * @notice Withdraw of max(uint256) is equivalent to withdrawing full balance.
     */
    function test_MaxWithdraw_EqualsFullBalance() public pure {
        uint256 userBalance = 500e18;
        uint256 amount      = type(uint256).max;

        uint256 toWithdraw = (amount == type(uint256).max) ? userBalance : amount;
        assertEq(toWithdraw, userBalance);
    }

    // ─── Interest rate update math ────────────────────────────────────────────

    /**
     * @notice Reserve factor reduces the depositor rate.
     * depositRate = borrowRate * utilization * (1 - reserveFactor)
     */
    function test_ReserveFactor_ReducesDepositRate() public pure {
        uint256 borrowRateRay   = 5e25;   // 5% in ray
        uint256 utilization     = 8e17;   // 80% in wad
        uint256 reserveFactor   = 1000;   // 10% in bps

        uint256 grossDepositRate  = borrowRateRay.rayMul(utilization);
        uint256 netToDepositors   = grossDepositRate.percentMul(10000 - reserveFactor);

        assertLt(netToDepositors, grossDepositRate);
        assertApproxEqAbs(netToDepositors, (grossDepositRate * 9000) / 10000, 1e10);
    }

    /**
     * @notice At 0% utilization: no borrows → no deposit interest.
     */
    function test_ZeroUtilization_ZeroDepositRate() public pure {
        uint256 borrowRate  = 5e25;
        uint256 utilization = 0;

        uint256 depositRate = borrowRate.rayMul(utilization);
        assertEq(depositRate, 0);
    }

    // ─── LTV / health factor math ─────────────────────────────────────────────

    /**
     * @notice Health factor = collateral * threshold / debt
     * If HF < 1e18 the position is liquidatable.
     */
    function test_HealthFactor_AboveOne_Safe() public pure {
        uint256 collateralValue = 2000e18; // $2000 collateral
        uint256 threshold       = 8000;    // 80% liquidation threshold
        uint256 debtValue       = 1000e18; // $1000 debt

        // liquidationScore = 2000 * 0.80 = 1600
        uint256 liquidationScore = collateralValue.percentMul(threshold);
        // HF = 1600 / 1000 = 1.6 WAD
        uint256 hf = liquidationScore.wadDiv(debtValue);

        assertGt(hf, WAD); // HF > 1 → safe
        assertApproxEqAbs(hf, 16e17, 1e12); // ≈ 1.6
    }

    function test_HealthFactor_BelowOne_Liquidatable() public pure {
        uint256 collateralValue = 1000e18;
        uint256 threshold       = 8000;
        uint256 debtValue       = 1500e18; // Debt > collateral threshold

        uint256 liquidationScore = collateralValue.percentMul(threshold);
        uint256 hf               = liquidationScore.wadDiv(debtValue);

        assertLt(hf, WAD); // HF < 1 → liquidatable
    }
}
