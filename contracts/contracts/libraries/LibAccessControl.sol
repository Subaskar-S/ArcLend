// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {AppStorage, LibAppStorage} from "../AppStorage.sol";

/**
 * @title LibAccessControl
 * @notice Shared role-based access control helpers for all facets.
 */
library LibAccessControl {
    bytes32 public constant POOL_ADMIN_ROLE = keccak256("POOL_ADMIN");
    bytes32 public constant EMERGENCY_ADMIN_ROLE = keccak256("EMERGENCY_ADMIN");

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    function hasRole(bytes32 role, address account) internal view returns (bool) {
        return LibAppStorage.appStorage().roles[role][account];
    }

    function requireRole(bytes32 role) internal view {
        require(hasRole(role, msg.sender), "AccessControl: missing role");
    }

    function requirePoolAdmin() internal view {
        requireRole(POOL_ADMIN_ROLE);
    }

    function requireEmergencyAdmin() internal view {
        requireRole(EMERGENCY_ADMIN_ROLE);
    }

    function requireNotPaused() internal view {
        require(!LibAppStorage.appStorage().paused, "Protocol: paused");
    }

    function grantRole(bytes32 role, address account) internal {
        AppStorage storage s = LibAppStorage.appStorage();
        // Caller must have the admin role for this role
        bytes32 adminRole = s.roleAdmin[role];
        require(s.roles[adminRole][msg.sender], "AccessControl: not role admin");
        if (!s.roles[role][account]) {
            s.roles[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function revokeRole(bytes32 role, address account) internal {
        AppStorage storage s = LibAppStorage.appStorage();
        bytes32 adminRole = s.roleAdmin[role];
        require(s.roles[adminRole][msg.sender], "AccessControl: not role admin");
        if (s.roles[role][account]) {
            s.roles[role][account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }
}
