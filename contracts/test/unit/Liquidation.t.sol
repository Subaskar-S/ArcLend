// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {LiquidationLogic} from "../../src/libraries/LiquidationLogic.sol";
import {PercentageMath} from "../../src/libraries/PercentageMath.sol";

// Note: To truly unit test LiquidationLogic in a standalone way requires setting up an environment
// or an adapter since LiquidationLogic executes against `mapping(address => ReserveData)`.
// We will test the pure math component of it.

contract LiquidationLogicTest is Test {
    using PercentageMath for uint256;

    uint256 constant WAD = 1e18;

    function test_CalculateAvailableCollateralToLiquidate_NoBonus()
        public
        pure
    {
        uint256 collateralPrice = 2000e18; // 2000 USD
        uint256 debtPrice = 1e18; // 1 USD
        uint256 debtToCover = 1000e18; // 1000 USD to cover
        uint256 liquidationBonus = 10000; // 100% (No bonus)
        uint256 collateralDecimals = 18;
        uint256 debtDecimals = 18;

        (uint256 collateralAmount, uint256 amountToLiquidate) = LiquidationLogic
            .calculateAvailableCollateralToLiquidate(
                collateralPrice,
                debtPrice,
                debtToCover,
                10000e18, // User has 10000 collateral
                liquidationBonus,
                collateralDecimals,
                debtDecimals
            );

        // Expected collateral needed: 1000 * 1 / 2000 = 0.5 collateral
        assertEq(collateralAmount, 0.5e18);
        assertEq(amountToLiquidate, debtToCover);
    }

    function test_CalculateAvailableCollateralToLiquidate_WithBonus()
        public
        pure
    {
        uint256 collateralPrice = 2000e18; // 2000 USD
        uint256 debtPrice = 1e18; // 1 USD
        uint256 debtToCover = 1000e18; // 1000 USD to cover
        uint256 liquidationBonus = 10500; // 105% (5% bonus)
        uint256 collateralDecimals = 18;
        uint256 debtDecimals = 18;

        (uint256 collateralAmount, uint256 amountToLiquidate) = LiquidationLogic
            .calculateAvailableCollateralToLiquidate(
                collateralPrice,
                debtPrice,
                debtToCover,
                10000e18, // User has plenty
                liquidationBonus,
                collateralDecimals,
                debtDecimals
            );

        // Expected collateral needed: (1000 * 1 / 2000) * 1.05 = 0.525 collateral
        assertEq(collateralAmount, 0.525e18);
        assertEq(amountToLiquidate, debtToCover);
    }
}
