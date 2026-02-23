// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {DataTypes} from "../libraries/DataTypes.sol";

/**
 * @title ILendingPool
 * @notice Interface for the core lending pool contract.
 */
interface ILendingPool {
    // ============================================================
    //                          EVENTS
    // ============================================================

    event Deposit(
        address indexed reserve,
        address indexed user,
        address indexed onBehalfOf,
        uint256 amount
    );

    event Withdraw(
        address indexed reserve,
        address indexed user,
        address indexed to,
        uint256 amount
    );

    event Borrow(
        address indexed reserve,
        address indexed user,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 borrowRate
    );

    event Repay(
        address indexed reserve,
        address indexed user,
        address indexed repayer,
        uint256 amount
    );

    event LiquidationCall(
        address indexed collateralAsset,
        address indexed debtAsset,
        address indexed user,
        uint256 debtToCover,
        uint256 liquidatedCollateralAmount,
        address liquidator
    );

    event ReserveDataUpdated(
        address indexed reserve,
        uint256 liquidityRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex
    );

    event Paused();
    event Unpaused();

    // ============================================================
    //                       USER ACTIONS
    // ============================================================

    /**
     * @notice Deposits an amount of underlying asset into the reserve.
     * @param asset The address of the underlying asset to deposit
     * @param amount The amount to deposit (in underlying decimals)
     * @param onBehalfOf The address that will receive the aTokens
     */
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external;

    /**
     * @notice Withdraws an amount of underlying asset from the reserve.
     * @param asset The address of the underlying asset
     * @param amount The amount to withdraw (type(uint256).max for full balance)
     * @param to The address that will receive the underlying
     * @return The final amount withdrawn
     */
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    /**
     * @notice Borrows an amount of underlying asset.
     * @param asset The address of the underlying asset to borrow
     * @param amount The amount to borrow
     * @param onBehalfOf The address receiving the debt (must have sufficient collateral)
     */
    function borrow(address asset, uint256 amount, address onBehalfOf) external;

    /**
     * @notice Repays a borrowed amount.
     * @param asset The address of the borrowed underlying asset
     * @param amount The amount to repay (type(uint256).max for full debt)
     * @param onBehalfOf The address of the user who will have their debt reduced
     * @return The final amount repaid
     */
    function repay(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external returns (uint256);

    /**
     * @notice Liquidates an undercollateralized position.
     * @param collateralAsset The address of the collateral asset to seize
     * @param debtAsset The address of the debt asset to repay
     * @param user The address of the borrower getting liquidated
     * @param debtToCover The amount of debt to cover (limited by close factor)
     */
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover
    ) external;

    // ============================================================
    //                        VIEW FUNCTIONS
    // ============================================================

    function getReserveData(
        address asset
    ) external view returns (DataTypes.ReserveData memory);

    function getUserConfiguration(
        address user
    ) external view returns (DataTypes.UserConfigurationMap memory);

    function getReserveNormalizedIncome(
        address asset
    ) external view returns (uint256);

    function getReserveNormalizedVariableDebt(
        address asset
    ) external view returns (uint256);

    function getReservesList() external view returns (address[] memory);

    // ============================================================
    //                        ADMIN FUNCTIONS
    // ============================================================

    function initReserve(
        address asset,
        address aTokenAddress,
        address debtTokenAddress,
        address interestRateStrategyAddress
    ) external;

    function setConfiguration(
        address asset,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) external;

    function setReserveFreeze(address asset, bool freeze) external;

    function setReserveActive(address asset, bool active) external;
}
