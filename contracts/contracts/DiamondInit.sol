// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {AppStorage, LibAppStorage} from "./AppStorage.sol";
import {DataTypes} from "./libraries/DataTypes.sol";

/**
 * @title DiamondInit
 * @notice One-time initialization for the Diamond.
 * @dev Called via delegatecall from Diamond constructor or during DiamondCut.
 *      Sets up roles, oracle address, and marks the protocol as live.
 */
contract DiamondInit {
    bytes32 public constant POOL_ADMIN_ROLE = keccak256("POOL_ADMIN");
    bytes32 public constant EMERGENCY_ADMIN_ROLE = keccak256("EMERGENCY_ADMIN");

    /**
     * @notice Initialize the protocol.
     * @param admin The initial admin address.
     * @param oracle The initial price oracle address.
     */
    function init(address admin, address oracle) external {
        AppStorage storage s = LibAppStorage.appStorage();
        s.priceOracle = oracle;
        s.paused = false;

        // Grant all roles to the initial admin
        s.roles[POOL_ADMIN_ROLE][admin] = true;
        s.roles[EMERGENCY_ADMIN_ROLE][admin] = true;

        // Grant DEFAULT_ADMIN_ROLE so admin can grant/revoke others
        s.roles[bytes32(0)][admin] = true;

        // Set role admins
        s.roleAdmin[POOL_ADMIN_ROLE] = bytes32(0); // DEFAULT_ADMIN_ROLE
        s.roleAdmin[EMERGENCY_ADMIN_ROLE] = bytes32(0);
    }
}
