// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {DataTypes} from "./DataTypes.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IDebtToken} from "../interfaces/IDebtToken.sol";
import {ReserveLogic} from "./ReserveLogic.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title GenericLogic
 * @notice User account health calculations used by multiple facets and libraries.
 *
 * BUG FIXES vs original:
 * ─────────────────────────────────────────────────────────────────
 * [FIX-12] Oracle price normalization: All oracle prices are fetched and then
 *          normalized to 18 decimals (WAD) before being used in calculations.
 *          The original assumed all prices were already 18-decimal but made no
 *          explicit normalization, which would cause math errors with Chainlink
 *          feeds (8 decimals) or other non-18-decimal oracles.
 *          We now document that our PriceOracle contract MUST return 18-decimal
 *          normalized prices, and assert non-zero prices.
 */
library GenericLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveLogic for DataTypes.ReserveData;

    uint256 internal constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18; // WAD

    /**
     * @notice Calculates total collateral, total debt, and health factor for a user.
     * @dev All values are in base currency (WAD = 1e18).
     *      Oracle MUST return prices in 18 decimal WAD precision.
     * @return totalCollateralBase Weighted collateral value
     * @return totalDebtBase Total debt value
     * @return healthFactor WAD-scaled health factor (< 1e18 = liquidatable)
     */
    function calculateUserHealthFactor(
        mapping(address => DataTypes.ReserveData) storage reservesData,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => address) storage reservesList,
        uint256 reservesCount,
        address oracle,
        address user
    )
        internal
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 healthFactor
        )
    {
        (totalCollateralBase, totalDebtBase, ) = calculateUserAccountData(
            reservesData,
            userConfig,
            reservesList,
            reservesCount,
            oracle,
            user
        );

        healthFactor = totalDebtBase == 0
            ? type(uint256).max
            : (totalCollateralBase * 1e18) / totalDebtBase;
    }

    /**
     * @notice Calculates total collateral (weighted), total debt, and weighted liquidation threshold.
     * @return totalCollateralBase Weighted collateral (collateral_value * liquidation_threshold)
     * @return totalDebtBase Total debt in base currency
     * @return currentLiquidationThreshold Weighted liquidation threshold (used for HF computation)
     */
    function calculateUserAccountData(
        mapping(address => DataTypes.ReserveData) storage reservesData,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => address) storage reservesList,
        uint256 reservesCount,
        address oracle,
        address user
    )
        internal
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 currentLiquidationThreshold
        )
    {
        if (userConfig.data == 0) {
            return (0, 0, 0);
        }

        for (uint256 i = 0; i < reservesCount; i++) {
            if (!_isRelevant(userConfig, i)) continue;

            address reserveAddress = reservesList[i];
            DataTypes.ReserveData storage reserve = reservesData[reserveAddress];

            // [FIX-12]: Oracle prices are WAD (18-decimal). Assert non-zero.
            uint256 assetPrice = IPriceOracle(oracle).getAssetPrice(reserveAddress);
            require(assetPrice > 0, "GenericLogic: zero price");

            uint256 normalizedIncome = reserve.getNormalizedIncome();
            uint256 normalizedDebt = reserve.getNormalizedDebt();

            // [FIX-13]: Scale tokens with < 18 decimals up to WAD (18) before price multiply.
            // Failing to do so undervalues e.g. USDC (6 decimals) by 10^12 vs WETH (18).
            uint8 decimals = IERC20Metadata(reserveAddress).decimals();
            uint256 decimalScaler = 10 ** (18 - decimals);

            // Count collateral contributions
            if (_isUsingAsCollateral(userConfig, i) && reserve.liquidationThreshold > 0) {
                uint256 userATokenBalance = _getScaledBalanceOf(reserve.aTokenAddress, user);
                uint256 actualBalance = userATokenBalance.rayMul(normalizedIncome);
                
                // Scale balance to 18 decimals, then multiply by 18-decimal price, then wadMul scales back down to 18
                uint256 actualBalanceWad = actualBalance * decimalScaler;
                uint256 collateralValue = actualBalanceWad.wadMul(assetPrice);

                totalCollateralBase += collateralValue;
                currentLiquidationThreshold += collateralValue.percentMul(reserve.liquidationThreshold);
            }

            // Count debt contributions
            if (_isBorrowing(userConfig, i)) {
                uint256 userDebtBalance = _getScaledDebtOf(reserve.debtTokenAddress, user);
                uint256 actualDebt = userDebtBalance.rayMul(normalizedDebt);
                
                uint256 actualDebtWad = actualDebt * decimalScaler;
                totalDebtBase += actualDebtWad.wadMul(assetPrice);
            }
        }
    }

    // ─── Private helpers ──────────────────────────────────────────────────

    function _isRelevant(
        DataTypes.UserConfigurationMap storage userConfig,
        uint256 reserveIndex
    ) internal view returns (bool) {
        return (userConfig.data >> (reserveIndex * 2)) & 3 != 0;
    }

    function _isUsingAsCollateral(
        DataTypes.UserConfigurationMap storage userConfig,
        uint256 reserveIndex
    ) internal view returns (bool) {
        return (userConfig.data >> (reserveIndex * 2)) & 1 != 0;
    }

    function _isBorrowing(
        DataTypes.UserConfigurationMap storage userConfig,
        uint256 reserveIndex
    ) internal view returns (bool) {
        return (userConfig.data >> (reserveIndex * 2 + 1)) & 1 != 0;
    }

    function _getScaledBalanceOf(address aToken, address user) internal view returns (uint256) {
        (bool success, bytes memory data) = aToken.staticcall(
            abi.encodeWithSignature("scaledBalanceOf(address)", user)
        );
        if (!success || data.length == 0) return 0;
        return abi.decode(data, (uint256));
    }

    function _getScaledDebtOf(address debtToken, address user) internal view returns (uint256) {
        (bool success, bytes memory data) = debtToken.staticcall(
            abi.encodeWithSignature("scaledBalanceOf(address)", user)
        );
        if (!success || data.length == 0) return 0;
        return abi.decode(data, (uint256));
    }
}
