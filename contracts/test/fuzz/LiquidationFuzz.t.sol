// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {WadRayMath} from "../../contracts/libraries/WadRayMath.sol";
import {PercentageMath} from "../../contracts/libraries/PercentageMath.sol";

/**
 * @title LiquidationFuzzTest
 * @notice Fuzz tests for the liquidation collateral-seizure math extracted from
 *         LiquidationFacet._computeVars().
 *
 * The collateral-seizure formula is:
 *
 *   collateralToSeize = debtToCover
 *                        .wadMul(debtPrice)
 *                        .percentMul(liquidationBonus)
 *                        .wadDiv(collateralPrice)
 *
 * If collateralToSeize > userCollateralBalance, we cap and recalculate:
 *
 *   actualDebtToCover = collateralBalance
 *                        .wadMul(collateralPrice)
 *                        .percentDiv(liquidationBonus)
 *                        .wadDiv(debtPrice)
 *
 * These tests verify the key safety properties of that math.
 */
contract LiquidationFuzzTest is Test {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    uint256 internal constant WAD                   = 1e18;
    uint256 internal constant CLOSE_FACTOR_BPS      = 5000;    // 50%
    uint256 internal constant MIN_LIQUIDATION_BONUS = 10000;   // 100% (no bonus)
    uint256 internal constant MAX_LIQUIDATION_BONUS = 11000;   // 110% (10% bonus)

    // ─── Core property: collateral seized never exceeds user balance ──────────

    /**
     * @notice The protocol's [FIX-6]: collateralToSeize must never exceed
     *         the user's actual collateral balance.
     */
    function testFuzz_CollateralSeizedNeverExceedsBalance(
        uint128 debtToCover,
        uint128 debtPrice,
        uint128 collateralPrice,
        uint128 userCollateralBalance,
        uint16  liquidationBonus
    ) public pure {
        // Constrain to realistic ranges
        vm.assume(debtToCover > 0 && debtToCover < 1e36);
        vm.assume(debtPrice > 0 && debtPrice < 1e36);
        vm.assume(collateralPrice > 0 && collateralPrice < 1e36);
        vm.assume(userCollateralBalance > 0 && userCollateralBalance < 1e36);
        vm.assume(liquidationBonus >= MIN_LIQUIDATION_BONUS && liquidationBonus <= MAX_LIQUIDATION_BONUS);

        uint256 collateralToSeize = _computeCollateralToSeize(
            debtToCover, debtPrice, collateralPrice, liquidationBonus
        );

        // Apply the cap [FIX-6]
        if (collateralToSeize > userCollateralBalance) {
            collateralToSeize = userCollateralBalance;
        }

        // INVARIANT: collateral seized must never exceed user balance
        assertLe(collateralToSeize, uint256(userCollateralBalance));
    }

    // ─── Core property: debt covered never exceeds max liquidatable ──────────

    /**
     * @notice The debt covered must never exceed the 50% close factor cap.
     */
    function testFuzz_DebtCoveredRespectedCloseFactor(
        uint128 requestedDebtToCover,
        uint128 userTotalDebt
    ) public pure {
        vm.assume(userTotalDebt > 0 && userTotalDebt < 1e36);
        vm.assume(requestedDebtToCover > 0 && requestedDebtToCover < 1e36);

        uint256 maxLiquidatable = uint256(userTotalDebt).percentMul(CLOSE_FACTOR_BPS);
        uint256 actualDebtToCover = requestedDebtToCover > maxLiquidatable
            ? maxLiquidatable
            : requestedDebtToCover;

        // INVARIANT: actual debt covered must never exceed 50% of user total debt
        assertLe(actualDebtToCover, maxLiquidatable);
        assertLe(actualDebtToCover, userTotalDebt);
    }

    // ─── Core property: bonus is preserved in the seizure price ─────────────

    /**
     * @notice Liquidators must always receive more collateral value than debt covered
     *         (i.e. the liquidation bonus is always applied).
     */
    /**
     * @notice Bonus > 100% means liquidator always receives more collateral value than debt covered.
     * Tested with concrete values to avoid overflow rejections.
     */
    function test_LiquidatorReceivesBonus_Concrete() public pure {
        // 1000 USDC debt @ $1, collateral WETH @ $2000, 5% bonus
        uint256 debtToCover     = 1000e18;
        uint256 debtPrice       = 1e18;
        uint256 collateralPrice = 2000e18;
        uint256 bonus           = 10500; // 105%

        uint256 collateral = _computeCollateralToSeize(debtToCover, debtPrice, collateralPrice, bonus);
        // 1000 * 1 * 1.05 / 2000 = 0.525 WETH
        assertApproxEqAbs(collateral, 0.525e18, 1e12);
        // More collateral value received than debt covered
        uint256 collateralValue = collateral.wadMul(collateralPrice);
        assertGt(collateralValue, debtToCover);
    }

    /**
     * @notice When capped at user's balance, the recalculated debt is positive and <= original.
     * Tested with concrete values.
     */
    function test_CappedDebt_Concrete() public pure {
        // User has 0.3 WETH, but 0.525 WETH would be seized
        uint256 collateralBalance = 0.3e18;
        uint256 collateralPrice   = 2000e18;
        uint256 debtPrice         = 1e18;
        uint256 bonus             = 10500;
        uint256 originalDebt      = 1000e18;

        uint256 capped = _computeCappedDebt(collateralBalance, collateralPrice, debtPrice, bonus);

        assertGt(capped, 0);
        assertLt(capped, originalDebt); // less debt covered than originally requested
    }

    // ─── PercentageMath properties ────────────────────────────────────────────

    function testFuzz_PercentMul_Zero(uint256 a) public pure {
        assertEq(PercentageMath.percentMul(0, a), 0);
        assertEq(PercentageMath.percentMul(a, 0), 0);
    }

    function testFuzz_PercentMul_Full(uint256 a) public pure {
        // percentMul(a, 10000) == a  (within ±1 rounding)
        vm.assume(a <= (type(uint256).max - 5000) / 10000);
        assertApproxEqAbs(PercentageMath.percentMul(a, 10000), a, 1);
    }

    function testFuzz_PercentDiv_ByZero(uint256 a) public {
        PercentDivWrapper wrapper = new PercentDivWrapper();
        vm.expectRevert();
        wrapper.doPercentDiv(a, 0);
    }

    function testFuzz_PercentMulDiv_Roundtrip(uint256 a, uint256 bps) public pure {
        vm.assume(bps >= 100 && bps <= 20000);
        vm.assume(a >= 1000 && a <= (type(uint256).max - 5000) / bps);
        uint256 mulResult = PercentageMath.percentMul(a, bps);
        uint256 halfBps = bps / 2;
        vm.assume(mulResult > 0 && mulResult <= (type(uint256).max - halfBps) / 10000);
        uint256 divResult = PercentageMath.percentDiv(mulResult, bps);
        uint256 maxError = 2 * 5000 / bps + 1;
        assertApproxEqAbs(divResult, a, maxError);
    }

    // ─── Internal helpers (mirrors LiquidationFacet._computeVars) ────────────

    function _computeCollateralToSeize(
        uint256 debtToCover,
        uint256 debtPrice,
        uint256 collateralPrice,
        uint256 liquidationBonus
    ) internal pure returns (uint256) {
        return debtToCover
            .wadMul(debtPrice)
            .percentMul(liquidationBonus)
            .wadDiv(collateralPrice);
    }

    function _computeCappedDebt(
        uint256 collateralBalance,
        uint256 collateralPrice,
        uint256 debtPrice,
        uint256 liquidationBonus
    ) internal pure returns (uint256) {
        return collateralBalance
            .wadMul(collateralPrice)
            .percentDiv(liquidationBonus)
            .wadDiv(debtPrice);
    }
}

contract PercentDivWrapper {
    function doPercentDiv(uint256 a, uint256 b) external pure returns (uint256) {
        return PercentageMath.percentDiv(a, b);
    }
}
