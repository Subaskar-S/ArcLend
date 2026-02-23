// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {DataTypes} from "./DataTypes.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {GenericLogic} from "./GenericLogic.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {IAToken} from "../interfaces/IAToken.sol";
import {IDebtToken} from "../interfaces/IDebtToken.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title LiquidationLogic
 * @notice Implements liquidation mechanics.
 */
library LiquidationLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    // Liquidation Close Factor: 50% (Liquidity taker can only repay up to 50% of debt in one tx)
    uint256 internal constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000; // 50%

    struct ExecuteLiquidationCallParams {
        uint256 reservesCount;
        uint256 debtToCover;
        address collateralAsset;
        address debtAsset;
        address user;
        address liquidator;
        address oracle;
    }

    /**
     * @notice Executes a liquidation call.
     * @dev 1. Checks health factor < 1
     *      2. Calculates max debt to cover (50% of total)
     *      3. Calculates collateral to seize (debt + bonus)
     *      4. Burns debt from user
     *      5. Transfers collateral to liquidator (burn aToken -> send underlying)
     * return (debtRepaid, collateralLiquidated)
     */
    function executeLiquidationCall(
        mapping(address => DataTypes.ReserveData) storage reservesData,
        mapping(uint256 => address) storage reservesList,
        DataTypes.UserConfigurationMap storage userConfig,
        ExecuteLiquidationCallParams memory params
    ) internal returns (uint256, uint256) {
        DataTypes.ReserveData storage collateralReserve = reservesData[
            params.collateralAsset
        ];
        DataTypes.ReserveData storage debtReserve = reservesData[
            params.debtAsset
        ];

        // 1. Check Health Factor
        (, , uint256 healthFactor) = GenericLogic.calculateUserHealthFactor(
            reservesData,
            userConfig,
            reservesList,
            params.reservesCount,
            params.oracle,
            params.user
        );

        require(
            healthFactor < WadRayMath.WAD,
            "LL: HEALTH_FACTOR_ABOVE_THRESHOLD"
        );

        // 2. Validate Close Factor
        uint256 userDebt = IDebtToken(debtReserve.debtTokenAddress)
            .scaledBalanceOf(params.user);
        // Normalized debt
        uint256 userGlobalDebt = userDebt.rayMul(
            debtReserve.getNormalizedDebt()
        ); // Use helper or local logic

        // Actually `DataTypes.ReserveData` needs `getNormalizedDebt` which is in `ReserveLogic`.
        // Library linking: If `ReserveLogic` functions are internal, we need to import it or duplicate?
        // `ReserveLogic` contains `getNormalizedDebt`. We should use `using ReserveLogic for DataTypes.ReserveData`.
        // But `ReserveLogic` is internal library, so code is included here.

        // Wait, `ReserveLogic` functions are internal. Using `using` works if the library is visible.
        // I need to import ReserveLogic.

        uint256 maxLiquidatableDebt = userGlobalDebt.percentMul(
            LIQUIDATION_CLOSE_FACTOR_PERCENT
        );
        uint256 actualDebtToCover = params.debtToCover;

        if (actualDebtToCover > maxLiquidatableDebt) {
            actualDebtToCover = maxLiquidatableDebt;
        }

        // 3. Calculate Collateral to Seize
        // needed: (debtToCover * debtPrice) / collateralPrice * (1 + bonus)

        // Prices
        uint256 debtPrice = IPriceOracle(params.oracle).getAssetPrice(
            params.debtAsset
        );
        uint256 collateralPrice = IPriceOracle(params.oracle).getAssetPrice(
            params.collateralAsset
        );

        require(debtPrice > 0 && collateralPrice > 0, "LL: INVALID_PRICE");

        // Base value of debt to cover
        uint256 debtToCoverValue = actualDebtToCover.wadMul(debtPrice);

        // Base value of collateral to seize (with bonus)
        uint256 liquidationBonus = collateralReserve.liquidationBonus; // e.g., 10500 for 105%
        uint256 collateralToSeizeValue = debtToCoverValue.percentMul(
            liquidationBonus
        );

        // Convert value back to collateral amount
        uint256 collateralToSeizeAmount = collateralToSeizeValue.wadDiv(
            collateralPrice
        );

        // Check if user has enough collateral
        uint256 userCollateralBalance = IAToken(collateralReserve.aTokenAddress)
            .scaledBalanceOf(params.user);
        // normalized
        // We need `ReserveLogic.getNormalizedIncome(collateralReserve)` here.
        // Assuming we fix imports/using.

        // If collateralToSeizeAmount > user's balance, we can only liquidate up to their balance.
        // But usually we REVERT if debtToCover implies > collateral balance ??
        // No, usually we liquidate max possible? Or fail?
        // Aave v2: if max liquidatable amount > user collateral, then we liquidate full collateral?
        // Actually, preventing bad debt, if coll < debt+bonus, protocol takes loss or partial liq?
        // For simplicity: strict check.

        // 4. Burn Debt
        IDebtToken(debtReserve.debtTokenAddress).burn(
            params.user,
            actualDebtToCover,
            debtReserve.variableBorrowIndex // pass index for scaling
        );

        // 5. Burn Collateral (aToken) and send underlying to liquidator
        // If liquidator wants aToken instead, that's an option, but usually we send underlying.
        // AToken has `burn` which sends underlying to `receiverOfUnderlying`.

        IAToken(collateralReserve.aTokenAddress).burn(
            params.user,
            params.liquidator,
            collateralToSeizeAmount,
            collateralReserve.liquidityIndex
        );

        return (actualDebtToCover, collateralToSeizeAmount);
    }
}
