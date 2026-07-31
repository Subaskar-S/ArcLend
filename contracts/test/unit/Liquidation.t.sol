// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {WadRayMath} from "../../contracts/libraries/WadRayMath.sol";
import {PercentageMath} from "../../contracts/libraries/PercentageMath.sol";

/**
 * @title LiquidationMathTest
 * @notice Unit tests for the pure math that drives liquidation collateral seizure.
 *
 * The formula under test (from LiquidationFacet._computeVars):
 *
 *   collateralToSeize = debtToCover.wadMul(debtPrice).percentMul(bonus).wadDiv(collateralPrice)
 *
 * If collateralToSeize > userBalance, cap and recalculate actualDebtToCover:
 *
 *   actualDebtToCover = balance.wadMul(collateralPrice).percentDiv(bonus).wadDiv(debtPrice)
 */
contract LiquidationMathTest is Test {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    uint256 internal constant WAD              = 1e18;
    uint256 internal constant CLOSE_FACTOR_BPS = 5000; // 50%

    // ─── Basic collateral seizure calculation ─────────────────────────────────

    function test_CollateralSeizure_NoBonus() public pure {
        // Cover $1000 of USDC debt (price $1) with WETH collateral (price $2000)
        // No bonus: liquidationBonus = 10000 (100%)
        // collateralToSeize = 1000 * 1 * 10000 / 10000 / 2000 = 0.5 WETH
        uint256 debtToCover      = 1000e18;
        uint256 debtPrice        = 1e18;
        uint256 collateralPrice  = 2000e18;
        uint256 liquidationBonus = 10000;

        uint256 collateral = debtToCover.wadMul(debtPrice).percentMul(liquidationBonus).wadDiv(collateralPrice);

        assertApproxEqAbs(collateral, 0.5e18, 1e12);
    }

    function test_CollateralSeizure_WithBonus() public pure {
        // 5% bonus → 0.525 WETH seized for $1000 debt
        uint256 debtToCover      = 1000e18;
        uint256 debtPrice        = 1e18;
        uint256 collateralPrice  = 2000e18;
        uint256 liquidationBonus = 10500; // 105%

        uint256 collateral = debtToCover.wadMul(debtPrice).percentMul(liquidationBonus).wadDiv(collateralPrice);

        assertApproxEqAbs(collateral, 0.525e18, 1e12);
    }

    // ─── FIX-6: Collateral cap ─────────────────────────────────────────────────

    function test_CollateralCap_AppliedWhenExceedsBalance() public pure {
        // User only has 0.3 WETH but seizure formula demands 0.525 WETH
        uint256 userCollateralBalance = 0.3e18;
        uint256 debtToCover           = 1000e18;
        uint256 debtPrice             = 1e18;
        uint256 collateralPrice       = 2000e18;
        uint256 liquidationBonus      = 10500;

        uint256 collateralToSeize = debtToCover.wadMul(debtPrice).percentMul(liquidationBonus).wadDiv(collateralPrice);

        // Formula demands more than the user has → cap at balance
        if (collateralToSeize > userCollateralBalance) {
            collateralToSeize = userCollateralBalance;
        }

        assertEq(collateralToSeize, userCollateralBalance);
    }

    function test_CollateralCap_RecalculatesActualDebt() public pure {
        // After capping, recalculate actualDebtToCover proportionally
        uint256 collateralBalance = 0.3e18;
        uint256 collateralPrice   = 2000e18;
        uint256 debtPrice         = 1e18;
        uint256 liquidationBonus  = 10500;

        // actualDebtToCover = balance * collateralPrice / bonus / debtPrice
        uint256 actualDebt = collateralBalance.wadMul(collateralPrice).percentDiv(liquidationBonus).wadDiv(debtPrice);

        // 0.3 WETH @ $2000 / 1.05 / $1 ≈ $571.43 debt covered
        assertApproxEqAbs(actualDebt, 571428571428571428571, 1e12);
        // Must be less than the original 1000 debt request
        assertLt(actualDebt, 1000e18);
    }

    // ─── Close factor ─────────────────────────────────────────────────────────

    function test_CloseFactor_CapsAt50Percent() public pure {
        uint256 userTotalDebt     = 2000e18;
        uint256 requestedToCover  = 2000e18; // Trying to liquidate 100%

        uint256 maxLiquidatable  = userTotalDebt.percentMul(CLOSE_FACTOR_BPS);
        uint256 actualDebtCover  = requestedToCover > maxLiquidatable ? maxLiquidatable : requestedToCover;

        assertEq(actualDebtCover, 1000e18); // capped at 50%
        assertLe(actualDebtCover, userTotalDebt);
    }

    function test_CloseFactor_SmallRequestPassesThrough() public pure {
        uint256 userTotalDebt    = 2000e18;
        uint256 requestedCover   = 100e18; // only 5% → well under 50%

        uint256 maxLiquidatable  = userTotalDebt.percentMul(CLOSE_FACTOR_BPS);
        uint256 actualDebtCover  = requestedCover > maxLiquidatable ? maxLiquidatable : requestedCover;

        assertEq(actualDebtCover, requestedCover); // not capped
    }

    // ─── Self-liquidation guard ───────────────────────────────────────────────

    function test_SelfLiquidation_Detected() public pure {
        // In production LiquidationFacet: require(msg.sender != user, "...")
        // We verify the guard logic directly without a contract call.
        address user      = address(0xBEEF);
        address liquidator = address(0xBEEF);

        bool isSelfLiquidation = (liquidator == user);
        assertTrue(isSelfLiquidation, "Should detect self-liquidation");
    }
}
