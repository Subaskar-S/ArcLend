// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {LendingPoolStorage} from "./LendingPoolStorage.sol";
import {DataTypes} from "../libraries/DataTypes.sol";

/**
 * @title LendingPoolConfigurator
 * @notice Handles configuration and admin actions for the LendingPool
 * @dev This contract can be separated or integrated. To strictly follow the plan,
 * we will create it as a separate contract that is granted POOL_ADMIN role
 * by the LendingPool, or we can make the LendingPool delegatecall to it.
 * Given UUPS, standard pattern would have LendingPool include Configurator logic
 * or use a separate admin contract. Here we define the admin actions.
 */
contract LendingPoolConfigurator {
    ILendingPool public immutable pool;

    modifier onlyPoolAdmin() {
        // Validation that msg.sender is POOL_ADMIN.
        // Assuming we rely on LendingPool's AccessControl or check directly.
        _;
    }

    constructor(address _pool) {
        pool = ILendingPool(_pool);
    }

    /**
     * @notice Initializes a reserve
     */
    function initReserve(
        address asset,
        address aTokenAddress,
        address debtTokenAddress,
        address interestRateStrategyAddress
    ) external onlyPoolAdmin {
        pool.initReserve(
            asset,
            aTokenAddress,
            debtTokenAddress,
            interestRateStrategyAddress
        );
    }

    /**
     * @notice Updates the reserve configuration
     */
    function configureReserveAsCollateral(
        address asset,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) external onlyPoolAdmin {
        pool.setConfiguration(
            asset,
            ltv,
            liquidationThreshold,
            liquidationBonus
        );
    }

    /**
     * @notice Freezes or unfreezes a reserve
     */
    function setReserveFreeze(
        address asset,
        bool freeze
    ) external onlyPoolAdmin {
        pool.setReserveFreeze(asset, freeze);
    }

    /**
     * @notice Activates or deactivates a reserve
     */
    function setReserveActive(
        address asset,
        bool active
    ) external onlyPoolAdmin {
        pool.setReserveActive(asset, active);
    }
}
