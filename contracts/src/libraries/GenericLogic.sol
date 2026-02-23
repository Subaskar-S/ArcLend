// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {DataTypes} from "./DataTypes.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {ReserveLogic} from "./ReserveLogic.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IAToken} from "../interfaces/IAToken.sol";
import {IDebtToken} from "../interfaces/IDebtToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title GenericLogic
 * @notice Calculation utilities for user account health.
 * @dev All values computed in the base currency (e.g., ETH or USD).
 *      Health Factor formula:
 *
 *        HF = (Σ collateral_i × price_i × liquidationThreshold_i) / (Σ debt_j × price_j)
 *
 *      HF >= 1 WAD  → healthy
 *      HF <  1 WAD  → liquidatable
 *
 *      All intermediate values use wad (1e18) precision.
 */
library GenericLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveLogic for DataTypes.ReserveData;

    struct CalculateUserAccountDataVars {
        uint256 totalCollateralInBaseCurrency;
        uint256 totalDebtInBaseCurrency;
        uint256 avgLiquidationThreshold;
        uint256 currentReserveAddress;
        uint256 healthFactor;
        uint256 assetPrice;
        uint256 userBalanceInBaseCurrency;
        uint256 userDebtInBaseCurrency;
        uint256 liquidationThresholdWeightedSum;
    }

    /**
     * @notice Calculates the account data for a user across all reserves.
     * @dev Iterates through all active reserves, computing collateral and debt values.
     *      Uses the user configuration bitmap to skip inactive reserves (gas optimization).
     *
     * @param reservesData Mapping of reserve address → reserve data
     * @param userConfig The user's configuration bitmap
     * @param reservesList Mapping of reserve ID → reserve address
     * @param reservesCount Number of active reserves
     * @param oracle The price oracle address
     * @return totalCollateralInBaseCurrency Total collateral value in base currency (wad)
     * @return totalDebtInBaseCurrency Total debt value in base currency (wad)
     * @return healthFactor The user's health factor (wad). type(uint256).max if no debt.
     */
    function calculateUserAccountData(
        mapping(address => DataTypes.ReserveData) storage reservesData,
        DataTypes.UserConfigurationMap memory userConfig,
        mapping(uint256 => address) storage reservesList,
        uint256 reservesCount,
        address oracle
    )
        internal
        view
        returns (
            uint256 totalCollateralInBaseCurrency,
            uint256 totalDebtInBaseCurrency,
            uint256 healthFactor
        )
    {
        if (userConfig.data == 0) {
            return (0, 0, type(uint256).max);
        }

        uint256 liquidationThresholdWeightedSum;

        for (uint256 i = 0; i < reservesCount; ) {
            // Check if user has any position in this reserve (2 bits per reserve)
            if (!_isUsingReserve(userConfig, i)) {
                unchecked {
                    ++i;
                }
                continue;
            }

            address currentReserveAddress = reservesList[i];
            DataTypes.ReserveData storage currentReserve = reservesData[
                currentReserveAddress
            ];

            uint256 assetPrice = IPriceOracle(oracle).getAssetPrice(
                currentReserveAddress
            );
            require(assetPrice > 0, "GL: ZERO_PRICE");

            // Check if user is depositing (collateral)
            if (_isUsingAsCollateral(userConfig, i)) {
                uint256 userBalance = IAToken(currentReserve.aTokenAddress)
                    .scaledBalanceOf(msg.sender);
                if (userBalance > 0) {
                    // currentBalance = scaledBalance × normalizedIncome
                    uint256 currentBalance = userBalance.rayMul(
                        currentReserve.getNormalizedIncome()
                    );
                    uint256 balanceInBaseCurrency = currentBalance.wadMul(
                        assetPrice
                    );

                    totalCollateralInBaseCurrency += balanceInBaseCurrency;
                    liquidationThresholdWeightedSum +=
                        balanceInBaseCurrency *
                        currentReserve.liquidationThreshold;
                }
            }

            // Check if user is borrowing
            if (_isBorrowing(userConfig, i)) {
                uint256 userDebt = IDebtToken(currentReserve.debtTokenAddress)
                    .scaledBalanceOf(msg.sender);
                if (userDebt > 0) {
                    // currentDebt = scaledBalance × normalizedDebt
                    uint256 currentDebt = userDebt.rayMul(
                        currentReserve.getNormalizedDebt()
                    );
                    uint256 debtInBaseCurrency = currentDebt.wadMul(assetPrice);

                    totalDebtInBaseCurrency += debtInBaseCurrency;
                }
            }

            unchecked {
                ++i;
            }
        }

        // Calculate health factor
        if (totalDebtInBaseCurrency == 0) {
            healthFactor = type(uint256).max;
        } else {
            // avgLiquidationThreshold = ΣweightedThreshold / totalCollateral
            // HF = (totalCollateral × avgLiquidationThreshold) / totalDebtInBaseCurrency
            // Simplified: HF = liquidationThresholdWeightedSum / (totalDebt × PERCENTAGE_FACTOR)
            //
            // We avoid division-then-multiplication to preserve precision:
            // HF = liquidationThresholdWeightedSum / (totalDebtInBaseCurrency × PERCENTAGE_FACTOR)
            // But we need the result in wad (1e18), while thresholds are in basis points (1e4).
            //
            // HF_wad = (liquidationThresholdWeightedSum × 1e18) / (totalDebtInBaseCurrency × 1e4)
            // Which simplifies to:
            // HF_wad = (liquidationThresholdWeightedSum × 1e14) / totalDebtInBaseCurrency

            healthFactor =
                (liquidationThresholdWeightedSum * 1e14) /
                totalDebtInBaseCurrency;
        }
    }

    /**
     * @notice Calculates the health factor for a specific user address.
     * @dev Used by liquidation and validation logic where msg.sender != the user being checked.
     */
    function calculateUserHealthFactor(
        mapping(address => DataTypes.ReserveData) storage reservesData,
        DataTypes.UserConfigurationMap memory userConfig,
        mapping(uint256 => address) storage reservesList,
        uint256 reservesCount,
        address oracle,
        address user
    )
        internal
        view
        returns (
            uint256 totalCollateralInBaseCurrency,
            uint256 totalDebtInBaseCurrency,
            uint256 healthFactor
        )
    {
        if (userConfig.data == 0) {
            return (0, 0, type(uint256).max);
        }

        uint256 liquidationThresholdWeightedSum;

        for (uint256 i = 0; i < reservesCount; ) {
            if (!_isUsingReserve(userConfig, i)) {
                unchecked {
                    ++i;
                }
                continue;
            }

            address currentReserveAddress = reservesList[i];
            DataTypes.ReserveData storage currentReserve = reservesData[
                currentReserveAddress
            ];

            uint256 assetPrice = IPriceOracle(oracle).getAssetPrice(
                currentReserveAddress
            );
            require(assetPrice > 0, "GL: ZERO_PRICE");

            if (_isUsingAsCollateral(userConfig, i)) {
                uint256 userBalance = IAToken(currentReserve.aTokenAddress)
                    .scaledBalanceOf(user);
                if (userBalance > 0) {
                    uint256 currentBalance = userBalance.rayMul(
                        currentReserve.getNormalizedIncome()
                    );
                    uint256 balanceInBaseCurrency = currentBalance.wadMul(
                        assetPrice
                    );

                    totalCollateralInBaseCurrency += balanceInBaseCurrency;
                    liquidationThresholdWeightedSum +=
                        balanceInBaseCurrency *
                        currentReserve.liquidationThreshold;
                }
            }

            if (_isBorrowing(userConfig, i)) {
                uint256 userDebt = IDebtToken(currentReserve.debtTokenAddress)
                    .scaledBalanceOf(user);
                if (userDebt > 0) {
                    uint256 currentDebt = userDebt.rayMul(
                        currentReserve.getNormalizedDebt()
                    );
                    uint256 debtInBaseCurrency = currentDebt.wadMul(assetPrice);

                    totalDebtInBaseCurrency += debtInBaseCurrency;
                }
            }

            unchecked {
                ++i;
            }
        }

        if (totalDebtInBaseCurrency == 0) {
            healthFactor = type(uint256).max;
        } else {
            healthFactor =
                (liquidationThresholdWeightedSum * 1e14) /
                totalDebtInBaseCurrency;
        }
    }

    // ============================================================
    //               USER CONFIGURATION BITMAP HELPERS
    // ============================================================

    /// @dev Bit 2*reserveIndex = using as collateral, Bit 2*reserveIndex+1 = borrowing
    function _isUsingReserve(
        DataTypes.UserConfigurationMap memory self,
        uint256 reserveIndex
    ) internal pure returns (bool) {
        uint256 mask = 3 << (reserveIndex * 2);
        return (self.data & mask) != 0;
    }

    function _isUsingAsCollateral(
        DataTypes.UserConfigurationMap memory self,
        uint256 reserveIndex
    ) internal pure returns (bool) {
        return (self.data & (1 << (reserveIndex * 2))) != 0;
    }

    function _isBorrowing(
        DataTypes.UserConfigurationMap memory self,
        uint256 reserveIndex
    ) internal pure returns (bool) {
        return (self.data & (1 << (reserveIndex * 2 + 1))) != 0;
    }
}
