// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {DataTypes} from "./DataTypes.sol";
import {UserConfiguration} from "./UserConfiguration.sol";

// Note: I haven't implemented UserConfiguration library yet, I should probably put the bitmap logic there
// or keep it in GenericLogic. For strictness, I'll assume GenericLogic or a dedicated library handles the bitmap bits.
// Actually, `DataTypes.UserConfigurationMap` is a struct. I'll stick to using GenericLogic or a helper file.

/**
 * @title LendingPoolStorage
 * @notice Storage layout for the LendingPool contract.
 * @dev UUPS Upgradeable storage must be append-only.
 *      Reserved storage slots are provided for future upgrades.
 */
contract LendingPoolStorage {
    /**
     * @dev Mapping from asset address to reserve data.
     */
    mapping(address => DataTypes.ReserveData) internal _reserves;

    /**
     * @dev Mapping from user address to configuration (bitmap).
     */
    mapping(address => DataTypes.UserConfigurationMap) internal _usersConfig;

    /**
     * @dev List of reserves.
     */
    mapping(uint256 => address) internal _reservesList;

    /**
     * @dev Count of reserves.
     */
    uint256 internal _reservesCount;

    /**
     * @dev Pause state (from Pausable, but often managed via checking a flag in keeping with custom storage).
     *      Since we inherit PausableUpgradeable in implementation, that covers the paused state storage
     *      typically in its own slot.
     *      However, for clear custom storage referencing, we might want our own.
     *      Project plan said "PausableUpgradeable". So we rely on OZ storage for that.
     */

    /**
     * @dev Address of the Price Oracle.
     */
    address internal _addressesProvider; // Or just _priceOracle direct storage if simple

    // We specified direct Oracle storage in the plan interfaces, let's store it here.
    address internal _priceOracle;

    // ~~~~~ Gap for future upgrades ~~~~~
    uint256[50] private __gap;
}
