// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {DataTypes} from "./libraries/DataTypes.sol";

/**
 * @title AppStorage
 * @notice Shared protocol storage for all Diamond facets.
 * @dev ALL facets must use LibAppStorage.appStorage() to access state.
 *      Never inherit from this struct — access via the library.
 *
 * Storage slot:
 *   bytes32 constant ARCLEND_STORAGE_POSITION = keccak256("arclend.protocol.storage");
 *
 * This pattern (AppStorage) ensures no storage collisions between facets.
 * Adding new fields is safe — always append to the END of the struct.
 */
struct AppStorage {
    // ─── Reserve State ────────────────────────────────────────────────────
    mapping(address => DataTypes.ReserveData) reserves;
    mapping(uint256 => address) reservesList;
    uint256 reservesCount;

    // ─── User State ───────────────────────────────────────────────────────
    mapping(address => DataTypes.UserConfigurationMap) usersConfig;

    // ─── Protocol Config ──────────────────────────────────────────────────
    address priceOracle;
    bool paused;

    // ─── Access Control ───────────────────────────────────────────────────
    // owner is stored in LibDiamond separately (standard EIP-2535 slot)
    mapping(bytes32 => mapping(address => bool)) roles;
    mapping(bytes32 => bytes32) roleAdmin;
}

/**
 * @title LibAppStorage
 * @notice Access helper for AppStorage.
 */
library LibAppStorage {
    bytes32 constant ARCLEND_STORAGE_POSITION =
        keccak256("arclend.protocol.storage");

    function appStorage() internal pure returns (AppStorage storage s) {
        bytes32 position = ARCLEND_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
