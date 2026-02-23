// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {LiquidationLogic} from "../../src/libraries/LiquidationLogic.sol";

// Fuzzing the calculateAvailableCollateralToLiquidate pure function
contract LiquidationFuzzTest is Test {
    function testFuzz_CalculateAvailableCollateralToLiquidate(
        uint256 collateralPrice,
        uint256 debtPrice,
        uint256 debtToCover,
        uint256 userCollateralBalance,
        uint256 liquidationBonus
    ) public {
        // Assume reasonable ranges to prevent meaningless overflows
        vm.assume(collateralPrice > 0 && collateralPrice < 1e36);
        vm.assume(debtPrice > 0 && debtPrice < 1e36);
        vm.assume(debtToCover > 0 && debtToCover < 1e36);
        vm.assume(userCollateralBalance > 0 && userCollateralBalance < 1e36);
        // Bonus usually between 100% and 200%
        vm.assume(liquidationBonus >= 10000 && liquidationBonus <= 20000);

        (uint256 collateralAmount, uint256 amountToLiquidate) = LiquidationLogic
            .calculateAvailableCollateralToLiquidate(
                collateralPrice,
                debtPrice,
                debtToCover,
                userCollateralBalance,
                liquidationBonus,
                18,
                18
            );

        assertTrue(collateralAmount <= userCollateralBalance);
        assertTrue(amountToLiquidate <= debtToCover);
    }
}
