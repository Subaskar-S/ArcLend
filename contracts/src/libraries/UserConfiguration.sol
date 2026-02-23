// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {DataTypes} from "./DataTypes.sol";

/**
 * @title UserConfiguration
 * @notice Library for manipulating user configuration bitmaps.
 * @dev Optimized for gas.
 */
library UserConfiguration {
    function setUsingAsCollateral(
        DataTypes.UserConfigurationMap storage self,
        uint256 reserveIndex,
        bool usingAsCollateral
    ) internal {
        require(reserveIndex < 128, "UC: INDEX_OVERFLOW");
        uint256 bit = 1 << (reserveIndex * 2);
        if (usingAsCollateral) {
            self.data |= bit;
        } else {
            self.data &= ~bit;
        }
    }

    function setBorrowing(
        DataTypes.UserConfigurationMap storage self,
        uint256 reserveIndex,
        bool borrowing
    ) internal {
        require(reserveIndex < 128, "UC: INDEX_OVERFLOW");
        uint256 bit = 1 << (reserveIndex * 2 + 1);
        if (borrowing) {
            self.data |= bit;
        } else {
            self.data &= ~bit;
        }
    }

    function isUsingAsCollateral(
        DataTypes.UserConfigurationMap memory self,
        uint256 reserveIndex
    ) internal pure returns (bool) {
        require(reserveIndex < 128, "UC: INDEX_OVERFLOW");
        return (self.data & (1 << (reserveIndex * 2))) != 0;
    }

    function isBorrowing(
        DataTypes.UserConfigurationMap memory self,
        uint256 reserveIndex
    ) internal pure returns (bool) {
        require(reserveIndex < 128, "UC: INDEX_OVERFLOW");
        return (self.data & (1 << (reserveIndex * 2 + 1))) != 0;
    }

    function isEmpty(
        DataTypes.UserConfigurationMap memory self
    ) internal pure returns (bool) {
        return self.data == 0;
    }
}
