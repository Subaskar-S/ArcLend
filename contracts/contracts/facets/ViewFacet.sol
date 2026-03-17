// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {AppStorage, LibAppStorage} from "../AppStorage.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {ReserveLogic} from "../libraries/ReserveLogic.sol";
import {GenericLogic} from "../libraries/GenericLogic.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";

/**
 * @title ViewFacet
 * @notice Read-only getters for reserve and user state.
 * @dev Gas-free view functions for frontends and liquidation bots.
 */
contract ViewFacet {
    using ReserveLogic for DataTypes.ReserveData;
    using WadRayMath for uint256;

    function getReserveData(
        address asset
    ) external view returns (DataTypes.ReserveData memory) {
        return LibAppStorage.appStorage().reserves[asset];
    }

    function getUserConfiguration(
        address user
    ) external view returns (DataTypes.UserConfigurationMap memory) {
        return LibAppStorage.appStorage().usersConfig[user];
    }

    function getReserveNormalizedIncome(
        address asset
    ) external view returns (uint256) {
        return LibAppStorage.appStorage().reserves[asset].getNormalizedIncome();
    }

    function getReserveNormalizedVariableDebt(
        address asset
    ) external view returns (uint256) {
        return LibAppStorage.appStorage().reserves[asset].getNormalizedDebt();
    }

    function getReservesList() external view returns (address[] memory) {
        AppStorage storage s = LibAppStorage.appStorage();
        address[] memory list = new address[](s.reservesCount);
        for (uint256 i = 0; i < s.reservesCount; i++) {
            list[i] = s.reservesList[i];
        }
        return list;
    }

    function getPriceOracle() external view returns (address) {
        return LibAppStorage.appStorage().priceOracle;
    }

    function isPaused() external view returns (bool) {
        return LibAppStorage.appStorage().paused;
    }

    /**
     * @notice Returns full account health data for a user.
     * @param user The address of the user.
     * @return totalCollateralBase Total collateral value in base currency (WAD)
     * @return totalDebtBase Total debt value in base currency (WAD)
     * @return healthFactor E18-scaled health factor. Below 1e18 = liquidatable.
     */
    function getUserAccountData(
        address user
    )
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 healthFactor
        )
    {
        AppStorage storage s = LibAppStorage.appStorage();
        return GenericLogic.calculateUserHealthFactor(
            s.reserves,
            s.usersConfig[user],
            s.reservesList,
            s.reservesCount,
            s.priceOracle,
            user
        );
    }
}
