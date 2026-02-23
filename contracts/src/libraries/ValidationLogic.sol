// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {DataTypes} from "./DataTypes.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {GenericLogic} from "./GenericLogic.sol";
import {IAToken} from "../interfaces/IAToken.sol";
import {IDebtToken} from "../interfaces/IDebtToken.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

/**
 * @title ValidationLogic
 * @notice Validation logic for all LendingPool operations.
 * @dev Reverts with standard error codes if validation fails.
 */
library ValidationLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using GenericLogic for DataTypes.UserConfigurationMap;

    /**
     * @notice Validates a deposit execution.
     * @param reserve The reserve state
     * @param amount The amount to deposit
     */
    function validateDeposit(
        DataTypes.ReserveData storage reserve,
        uint256 amount
    ) internal view {
        require(amount != 0, "VL: INVALID_AMOUNT");
        require(reserve.isActive, "VL: RESERVE_INACTIVE");
        require(!reserve.isFrozen, "VL: RESERVE_FROZEN");
    }

    /**
     * @notice Validates a withdraw execution.
     * @param reserve The reserve address and data
     * @param amount The amount to withdraw
     * @param userBalance The user's current aToken balance
     * @param reservesData Storage mapping of all reserves
     * @param userConfig The user's configuration
     * @param reservesList List of all reserves
     * @param reservesCount Count of reserves
     * @param oracle The price oracle
     */
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
        require(amount <= userBalance, "VL: NOT_ENOUGH_AVAILABLE_USER_BALANCE");

        DataTypes.ReserveData storage reserve = reservesData[reserveAddress];
        require(reserve.isActive, "VL: RESERVE_INACTIVE");

        // optimized: if user is not borrowing, no need to check health factor
        if (userConfig.data == 0 || !userConfig._isBorrowing(reserve.id)) {
            // Wait, logic check: need to check if they are borrowing ANY asset.
            // Actually, simply checking if they have ANY debt is better.
            // But GenericLogic has check logic.
        }

        // If the user uses this reserve as collateral and has debt, we must check if
        // withdrawing 'amount' leaves them with HF >= 1.
        if (
            reserve.liquidationThreshold > 0 &&
            userConfig._isUsingAsCollateral(reserve.id)
        ) {
            // We simulate the withdrawal by subtracting the collateral from the calculation
            // This requires a specialized check or re-using GenericLogic with a simulation.

            // For rigorous validation, we need to basically calculate HF *after* the withdrawal.
            (
                uint256 totalCollateral,
                uint256 totalDebt,
                uint256 currentLiquidationThreshold
            ) = GenericLogic.calculateUserAccountData(
                    reservesData,
                    userConfig,
                    reservesList,
                    reservesCount,
                    oracle
                );

            if (totalDebt == 0) return;

            uint256 assetPrice = IPriceOracle(oracle).getAssetPrice(
                reserveAddress
            );
            uint256 withdrawValue = amount.wadMul(assetPrice);
            uint256 collateralToWithdrawAdjusted = withdrawValue.percentMul(
                reserve.liquidationThreshold
            );

            require(
                totalCollateral >= withdrawValue,
                "VL: WITHDRAW_EXCEEDS_COLLATERAL" // Should be caught by balance check, but safety net
            );

            // New HF check
            // HF = (Collateral - WithdrawValue) * (NewWeightedThreshold) / Debt
            // Simplified: (TotalWeightedCollateral - withdrawValue * threshold) / Debt

            require(
                currentLiquidationThreshold >= collateralToWithdrawAdjusted,
                "VL: COLLATERAL_INVALID" // Should not happen if math is right
            );

            uint256 newLiquidationThresholdTotal = currentLiquidationThreshold -
                collateralToWithdrawAdjusted;

            uint256 newHealthFactor = (newLiquidationThresholdTotal * 1e14) /
                totalDebt;

            require(
                newHealthFactor >= WadRayMath.WAD,
                "VL: HEALTH_FACTOR_BELOW_1"
            );
        }
    }

    /**
     * @notice Validates a borrow execution.
     */
    function validateBorrow(
        address reserveAddress,
        DataTypes.ReserveData storage reserve,
        address userAddress,
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
                reservesData,
                userConfig,
                reservesList,
                reservesCount,
                oracle
            );

        require(currentLiquidationThreshold > 0, "VL: COLLATERAL_BALANCE_IS_0");

        // HF after borrow must be >= 1
        // New HF = TotalWeightedCollateral / (ExistingDebt + NewDebt)

        uint256 newTotalDebt = totalDebt + amountInBaseCurrency;
        uint256 newHealthFactor = (currentLiquidationThreshold * 1e14) /
            newTotalDebt;

        require(newHealthFactor >= WadRayMath.WAD, "VL: HEALTH_FACTOR_BELOW_1");
    }

    /**
     * @notice Validates a repay execution.
     */
    function validateRepay(
        DataTypes.ReserveData storage reserve,
        uint256 amountSent,
        DataTypes.UserConfigurationMap storage userConfig,
        address user,
        uint256 currentDebt
    ) internal view {
        require(reserve.isActive, "VL: RESERVE_INACTIVE");
        require(amountSent != 0, "VL: INVALID_AMOUNT");
        require(currentDebt != 0, "VL: NO_DEBT_OF_SELECTED_TYPE");

        // We don't strictly check if amountSent <= currentDebt because we typically allow
        // repaying max(-1) to clean up dust. Logic usually handles excess refund.
    }

    /**
     * @notice Validates a liquidation execution.
     */
    function validateLiquidationCall(
        DataTypes.UserConfigurationMap storage userConfig,
        DataTypes.ReserveData storage collateralReserve,
        DataTypes.ReserveData storage debtReserve,
        uint256 userHealthFactor,
        uint256 userDebt
    ) internal view {
        require(collateralReserve.isActive, "VL: COLLATERAL_INACTIVE");
        require(debtReserve.isActive, "VL: DEBT_INACTIVE");

        require(userHealthFactor < WadRayMath.WAD, "VL: HEALTH_FACTOR_ABOVE_1");
        require(userDebt != 0, "VL: USER_DOES_NOT_HAVE_DEBT");
    }
}
