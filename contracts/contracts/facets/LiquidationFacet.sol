// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {AppStorage, LibAppStorage} from "../AppStorage.sol";
import {LibAccessControl} from "../libraries/LibAccessControl.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {ReserveLogic} from "../libraries/ReserveLogic.sol";
import {GenericLogic} from "../libraries/GenericLogic.sol";
import {IAToken} from "../interfaces/IAToken.sol";
import {IDebtToken} from "../interfaces/IDebtToken.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {PercentageMath} from "../libraries/PercentageMath.sol";

/**
 * @title LiquidationFacet
 * @notice Handles liquidation of undercollateralized positions.
 *
 * BUG FIXES applied vs original LiquidationLogic.sol:
 * ─────────────────────────────────────────────────────
 * [FIX-5] Calls updateState() on BOTH reserves BEFORE reading indexes.
 *         Original code burned debt using a potentially stale borrow index.
 * [FIX-6] Caps collateral seizure at the user's actual balance, then recomputes
 *         actualDebtToCover proportionally.
 * @dev  Refactored into sub-functions to stay within the EVM 16-stack-slot limit.
 */
contract LiquidationFacet {
    using ReserveLogic for DataTypes.ReserveData;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    uint256 internal constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000; // 50%

    event LiquidationCall(
        address indexed collateralAsset,
        address indexed debtAsset,
        address indexed user,
        uint256 debtToCover,
        uint256 liquidatedCollateralAmount,
        address liquidator
    );

    struct LiquidationVars {
        uint256 healthFactor;
        uint256 userDebt;
        uint256 maxLiquidatableDebt;
        uint256 actualDebtToCover;
        uint256 debtPrice;
        uint256 collateralPrice;
        uint256 collateralToSeize;
        uint256 userCollateralBalance;
    }

    /**
     * @notice Liquidate an undercollateralized borrower position.
     */
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover
    ) external {
        LibAccessControl.requireNotPaused();
        require(msg.sender != user, "LiquidationFacet: cannot self-liquidate");

        AppStorage storage s = LibAppStorage.appStorage();

        // ── [FIX-5]: Update state on BOTH reserves before reading any index ──
        s.reserves[collateralAsset].updateState(collateralAsset);
        s.reserves[debtAsset].updateState(debtAsset);

        LiquidationVars memory vars = _computeVars(
            s, collateralAsset, debtAsset, user, debtToCover
        );

        _executeLiquidation(s, collateralAsset, debtAsset, user, vars);

        emit LiquidationCall(
            collateralAsset,
            debtAsset,
            user,
            vars.actualDebtToCover,
            vars.collateralToSeize,
            msg.sender
        );
    }

    function _computeVars(
        AppStorage storage s,
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover
    ) private view returns (LiquidationVars memory vars) {
        // 1. Health factor check
        (, , vars.healthFactor) = GenericLogic.calculateUserHealthFactor(
            s.reserves,
            s.usersConfig[user],
            s.reservesList,
            s.reservesCount,
            s.priceOracle,
            user
        );
        require(vars.healthFactor < WadRayMath.WAD, "LiquidationFacet: HF above threshold");

        // 2. Compute max liquidatable debt (close factor = 50%)
        vars.userDebt = IDebtToken(s.reserves[debtAsset].debtTokenAddress)
            .scaledBalanceOf(user)
            .rayMul(s.reserves[debtAsset].getNormalizedDebt());
        require(vars.userDebt > 0, "LiquidationFacet: no debt");

        vars.maxLiquidatableDebt = vars.userDebt.percentMul(LIQUIDATION_CLOSE_FACTOR_PERCENT);
        vars.actualDebtToCover = debtToCover > vars.maxLiquidatableDebt
            ? vars.maxLiquidatableDebt
            : debtToCover;

        // 3. Compute collateral to seize (with bonus)
        vars.debtPrice = IPriceOracle(s.priceOracle).getAssetPrice(debtAsset);
        vars.collateralPrice = IPriceOracle(s.priceOracle).getAssetPrice(collateralAsset);
        require(vars.debtPrice > 0 && vars.collateralPrice > 0, "LiquidationFacet: invalid price");

        vars.collateralToSeize = vars.actualDebtToCover
            .wadMul(vars.debtPrice)
            .percentMul(uint256(s.reserves[collateralAsset].liquidationBonus))
            .wadDiv(vars.collateralPrice);

        // 4. [FIX-6]: Cap at user's actual collateral balance
        vars.userCollateralBalance = IAToken(s.reserves[collateralAsset].aTokenAddress)
            .scaledBalanceOf(user)
            .rayMul(s.reserves[collateralAsset].getNormalizedIncome());

        if (vars.collateralToSeize > vars.userCollateralBalance) {
            vars.collateralToSeize = vars.userCollateralBalance;
            vars.actualDebtToCover = vars.collateralToSeize
                .wadMul(vars.collateralPrice)
                .percentDiv(uint256(s.reserves[collateralAsset].liquidationBonus))
                .wadDiv(vars.debtPrice);
        }
    }

    function _executeLiquidation(
        AppStorage storage s,
        address collateralAsset,
        address debtAsset,
        address user,
        LiquidationVars memory vars
    ) private {
        // Burn debt tokens (liquidator covers the debt)
        IDebtToken(s.reserves[debtAsset].debtTokenAddress).burn(
            user,
            vars.actualDebtToCover,
            s.reserves[debtAsset].variableBorrowIndex
        );

        // Burn collateral aTokens — send underlying to liquidator
        IAToken(s.reserves[collateralAsset].aTokenAddress).burn(
            user,
            msg.sender,
            vars.collateralToSeize,
            s.reserves[collateralAsset].liquidityIndex
        );

        // Update interest rates for both reserves
        s.reserves[debtAsset].updateInterestRates(debtAsset, vars.actualDebtToCover, 0);
        s.reserves[collateralAsset].updateInterestRates(collateralAsset, 0, vars.collateralToSeize);
    }
}
