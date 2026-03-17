// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {AppStorage, LibAppStorage} from "../AppStorage.sol";
import {LibAccessControl} from "../libraries/LibAccessControl.sol";
import {DataTypes} from "../libraries/DataTypes.sol";

/**
 * @title ConfiguratorFacet
 * @notice Admin-only functions to configure reserves and protocol state.
 * @dev All functions require POOL_ADMIN or EMERGENCY_ADMIN role.
 */
contract ConfiguratorFacet {
    event ReserveInitialized(
        address indexed asset,
        address indexed aToken,
        address indexed debtToken,
        address interestRateStrategy
    );
    event ReserveConfigured(
        address indexed asset,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 reserveFactor
    );
    event ReserveFrozen(address indexed asset, bool frozen);
    event ReserveActive(address indexed asset, bool active);
    event BorrowingEnabled(address indexed asset, bool enabled);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    event Paused();
    event Unpaused();
    event RoleGranted(bytes32 indexed role, address indexed account);
    event RoleRevoked(bytes32 indexed role, address indexed account);

    // ─── Reserve Management ───────────────────────────────────────────────

    /**
     * @notice Initialize a new lending reserve.
     * @param asset The underlying ERC20 token address.
     * @param aTokenAddress The corresponding aToken contract.
     * @param debtTokenAddress The DebtToken contract for this reserve.
     * @param interestRateStrategyAddress The interest rate model contract.
     */
    function initReserve(
        address asset,
        address aTokenAddress,
        address debtTokenAddress,
        address interestRateStrategyAddress
    ) external {
        LibAccessControl.requirePoolAdmin();
        AppStorage storage s = LibAppStorage.appStorage();
        DataTypes.ReserveData storage reserve = s.reserves[asset];

        require(!reserve.isActive, "Configurator: reserve already active");
        require(aTokenAddress != address(0), "Configurator: invalid aToken");
        require(debtTokenAddress != address(0), "Configurator: invalid debtToken");
        require(interestRateStrategyAddress != address(0), "Configurator: invalid strategy");

        reserve.aTokenAddress = aTokenAddress;
        reserve.debtTokenAddress = debtTokenAddress;
        reserve.interestRateStrategyAddress = interestRateStrategyAddress;
        reserve.isActive = true;
        reserve.id = uint8(s.reservesCount);

        s.reservesList[s.reservesCount] = asset;
        s.reservesCount++;

        // Initialize indexes to 1 RAY (neutral — no interest yet)
        reserve.liquidityIndex = uint128(1e27);
        reserve.variableBorrowIndex = uint128(1e27);
        reserve.lastUpdateTimestamp = uint40(block.timestamp);

        emit ReserveInitialized(asset, aTokenAddress, debtTokenAddress, interestRateStrategyAddress);
    }

    /**
     * @notice Configure risk parameters for a reserve.
     * @param asset The reserve asset.
     * @param ltv Loan-to-value ratio in basis points (e.g. 7500 = 75%).
     * @param liquidationThreshold Liquidation threshold in basis points.
     * @param liquidationBonus Bonus for liquidators in basis points (e.g. 10500 = 105%).
     * @param reserveFactor Protocol fee in basis points (e.g. 1000 = 10%).
     */
    function setReserveConfiguration(
        address asset,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 reserveFactor
    ) external {
        LibAccessControl.requirePoolAdmin();
        require(ltv <= liquidationThreshold, "Configurator: LTV > threshold");
        require(liquidationThreshold <= 10000, "Configurator: threshold > 100%");
        require(liquidationBonus >= 10000, "Configurator: bonus must be >= 100%");
        require(reserveFactor <= 5000, "Configurator: reserve factor > 50%");

        AppStorage storage s = LibAppStorage.appStorage();
        DataTypes.ReserveData storage reserve = s.reserves[asset];
        require(reserve.isActive, "Configurator: reserve not active");

        reserve.ltv = uint16(ltv);
        reserve.liquidationThreshold = uint16(liquidationThreshold);
        reserve.liquidationBonus = uint16(liquidationBonus);
        reserve.reserveFactor = uint16(reserveFactor);

        emit ReserveConfigured(asset, ltv, liquidationThreshold, liquidationBonus, reserveFactor);
    }

    function setReserveFreeze(address asset, bool frozen) external {
        LibAccessControl.requirePoolAdmin();
        LibAppStorage.appStorage().reserves[asset].isFrozen = frozen;
        emit ReserveFrozen(asset, frozen);
    }

    function setReserveActive(address asset, bool active) external {
        LibAccessControl.requirePoolAdmin();
        LibAppStorage.appStorage().reserves[asset].isActive = active;
        emit ReserveActive(asset, active);
    }

    function setBorrowingEnabled(address asset, bool enabled) external {
        LibAccessControl.requirePoolAdmin();
        LibAppStorage.appStorage().reserves[asset].borrowingEnabled = enabled;
        emit BorrowingEnabled(asset, enabled);
    }

    // ─── Oracle ───────────────────────────────────────────────────────────

    function setOracle(address newOracle) external {
        LibAccessControl.requirePoolAdmin();
        require(newOracle != address(0), "Configurator: zero oracle");
        AppStorage storage s = LibAppStorage.appStorage();
        emit OracleUpdated(s.priceOracle, newOracle);
        s.priceOracle = newOracle;
    }

    // ─── Emergency ────────────────────────────────────────────────────────

    function pause() external {
        LibAccessControl.requireEmergencyAdmin();
        LibAppStorage.appStorage().paused = true;
        emit Paused();
    }

    function unpause() external {
        AppStorage storage s = LibAppStorage.appStorage();
        require(
            s.roles[LibAccessControl.EMERGENCY_ADMIN_ROLE][msg.sender] ||
            s.roles[LibAccessControl.POOL_ADMIN_ROLE][msg.sender],
            "Configurator: not admin"
        );
        s.paused = false;
        emit Unpaused();
    }

    // ─── Access Control ───────────────────────────────────────────────────

    function grantRole(bytes32 role, address account) external {
        LibAccessControl.grantRole(role, account);
        emit RoleGranted(role, account);
    }

    function revokeRole(bytes32 role, address account) external {
        LibAccessControl.revokeRole(role, account);
        emit RoleRevoked(role, account);
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return LibAccessControl.hasRole(role, account);
    }
}
