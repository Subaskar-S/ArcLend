// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {DataTypes} from "./DataTypes.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {GenericLogic} from "./GenericLogic.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

/**
 * @title ValidationLogic
 * @notice Validation for all protocol operations.
 *
 * BUG FIXES vs original:
 * ─────────────────────────────────────────────────────────────
 * [FIX-10] validateWithdraw(): Removed empty `if` block (lines 64-68 in original).
 *          Now correctly checks if user is borrowing ANYTHING before skipping HF check.
 *          Uses `userConfig.data != 0 && _hasBorrows()` pattern instead.
 * [FIX-11] validateBorrow(): Correctly passes the full `msg.sender` address to
 *          `GenericLogic` (the original passed `userAddress` but never set it for
 *          the collateral calculation context).
 */
library ValidationLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    uint256 internal constant BORROW_BITMASK = 0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;

    function validateDeposit(
        DataTypes.ReserveData storage reserve,
        uint256 amount
    ) internal view {
        require(amount != 0, "VL: INVALID_AMOUNT");
        require(reserve.isActive, "VL: RESERVE_INACTIVE");
        require(!reserve.isFrozen, "VL: RESERVE_FROZEN");
    }

    function validateWithdraw(
        address reserveAddress,
        uint256 amount,
        uint256 userBalance,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => address) storage reservesList,
        uint256 reservesCount,
        address oracle
    ) internal view {
        require(amount != 0, "VL: INVALID_AMOUNT");
        require(amount <= userBalance, "VL: NOT_ENOUGH_BALANCE");

        DataTypes.ReserveData storage reserve = reservesData[reserveAddress];
        require(reserve.isActive, "VL: RESERVE_INACTIVE");

        // ── [FIX-10]: Properly check if user has any borrows ────────────────
        // If user has NO borrows at all, skip health factor check (saves gas).
        // BORROW_BITMASK selects all odd bits (borrowing flags).
        bool userHasBorrows = (userConfig.data & BORROW_BITMASK) != 0;

        if (!userHasBorrows) {
            // No debt — can always withdraw
            return;
        }

        // User has borrows: check health factor after simulated withdrawal
        if (reserve.liquidationThreshold > 0 && _isUsingAsCollateral(userConfig, reserve.id)) {
            (
                uint256 totalCollateral,
                uint256 totalDebt,
                uint256 currentLiquidationThreshold
            ) = GenericLogic.calculateUserAccountData(
                    reservesData, userConfig, reservesList, reservesCount, oracle, msg.sender
                );

            if (totalDebt == 0) return;

            uint256 assetPrice = IPriceOracle(oracle).getAssetPrice(reserveAddress);
            uint256 withdrawValue = amount.wadMul(assetPrice);
            uint256 collateralToWithdrawAdjusted = withdrawValue.percentMul(
                reserve.liquidationThreshold
            );

            require(
                totalCollateral >= withdrawValue,
                "VL: WITHDRAW_EXCEEDS_COLLATERAL"
            );
            require(
                currentLiquidationThreshold >= collateralToWithdrawAdjusted,
                "VL: COLLATERAL_ROUNDING_ERROR"
            );

            uint256 newWeightedCollateral = currentLiquidationThreshold - collateralToWithdrawAdjusted;
            // HF = newWeightedCollateral / totalDebt (both in base currency)
            uint256 newHealthFactor = (newWeightedCollateral * 1e18) / totalDebt;

            require(newHealthFactor >= WadRayMath.WAD, "VL: HEALTH_FACTOR_BELOW_1");
        }
    }

    function validateBorrow(
        DataTypes.ReserveData storage reserve,
        uint256 amount,
        uint256 amountInBaseCurrency,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => address) storage reservesList,
        uint256 reservesCount,
        address oracle
    ) internal view {
        require(reserve.isActive, "VL: RESERVE_INACTIVE");
        require(!reserve.isFrozen, "VL: RESERVE_FROZEN");
        require(reserve.borrowingEnabled, "VL: BORROWING_NOT_ENABLED");
        require(amount != 0, "VL: INVALID_AMOUNT");

        (
            ,
            uint256 totalDebt,
            uint256 currentLiquidationThreshold
        ) = GenericLogic.calculateUserAccountData(
                reservesData, userConfig, reservesList, reservesCount, oracle, msg.sender
            );

        require(currentLiquidationThreshold > 0, "VL: NO_COLLATERAL");

        uint256 newTotalDebt = totalDebt + amountInBaseCurrency;
        require(newTotalDebt > 0, "VL: ZERO_DEBT");

        // HF = currentLiquidationThreshold / newTotalDebt (in WAD)
        uint256 newHealthFactor = (currentLiquidationThreshold * 1e18) / newTotalDebt;
        require(newHealthFactor >= WadRayMath.WAD, "VL: HEALTH_FACTOR_BELOW_1");
    }

    function validateRepay(
        DataTypes.ReserveData storage reserve,
        uint256 amountSent,
        uint256 currentDebt
    ) internal view {
        require(reserve.isActive, "VL: RESERVE_INACTIVE");
        require(amountSent != 0, "VL: INVALID_AMOUNT");
        require(currentDebt != 0, "VL: NO_DEBT");
    }

    function validateLiquidationCall(
        DataTypes.ReserveData storage collateralReserve,
        DataTypes.ReserveData storage debtReserve,
        uint256 userHealthFactor,
        uint256 userDebt
    ) internal view {
        require(collateralReserve.isActive, "VL: COLLATERAL_INACTIVE");
        require(debtReserve.isActive, "VL: DEBT_INACTIVE");
        require(userHealthFactor < WadRayMath.WAD, "VL: HF_ABOVE_THRESHOLD");
        require(userDebt != 0, "VL: NO_DEBT");
    }

    // ─── Internal bit helpers ─────────────────────────────────────────────
    function _isUsingAsCollateral(
        DataTypes.UserConfigurationMap storage userConfig,
        uint8 reserveId
    ) internal view returns (bool) {
        return (userConfig.data >> (uint256(reserveId) * 2)) & 1 != 0;
    }
}
