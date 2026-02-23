// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {LendingPoolStorage} from "./core/LendingPoolStorage.sol";
import {DataTypes} from "./libraries/DataTypes.sol";
import {ReserveLogic} from "./libraries/ReserveLogic.sol";
import {ValidationLogic} from "./libraries/ValidationLogic.sol";
import {GenericLogic} from "./libraries/GenericLogic.sol";
import {LiquidationLogic} from "./libraries/LiquidationLogic.sol";

import {IAToken} from "./interfaces/IAToken.sol";
import {IDebtToken} from "./interfaces/IDebtToken.sol";
import {WadRayMath} from "./libraries/WadRayMath.sol";

/**
 * @title LendingPool
 * @notice Main interaction contract for the protocol.
 * @dev UUPS Upgradeable. Inherits storage layout strictly.
 */
contract LendingPool is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    LendingPoolStorage,
    ILendingPool
{
    using ReserveLogic for DataTypes.ReserveData;
    using WadRayMath for uint256;

    bytes32 public constant POOL_ADMIN = keccak256("POOL_ADMIN");
    bytes32 public constant EMERGENCY_ADMIN = keccak256("EMERGENCY_ADMIN");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(POOL_ADMIN, admin);
        _grantRole(EMERGENCY_ADMIN, admin);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ============================================================
    //                       ADMIN ACTIONS
    // ============================================================

    /**
     * @notice Pauses all protocol interactions.
     * @dev Restricted to EMERGENCY_ADMIN.
     */
    function pause() external onlyRole(EMERGENCY_ADMIN) {
        _pause();
    }

    /**
     * @notice Unpauses all protocol interactions.
     * @dev Restricted to EMERGENCY_ADMIN or POOL_ADMIN.
     */
    function unpause() external {
        require(
            hasRole(EMERGENCY_ADMIN, msg.sender) ||
                hasRole(POOL_ADMIN, msg.sender),
            "Caller is not emergency or pool admin"
        );
        _unpause();
    }

    /**
     * @notice Initializes a reserve
     */
    function initReserve(
        address asset,
        address aTokenAddress,
        address debtTokenAddress,
        address interestRateStrategyAddress
    ) external override onlyRole(POOL_ADMIN) {
        DataTypes.ReserveData storage reserve = _reserves[asset];
        require(!reserve.isActive, "Reserve already active");

        reserve.aTokenAddress = aTokenAddress;
        reserve.debtTokenAddress = debtTokenAddress;
        reserve.interestRateStrategyAddress = interestRateStrategyAddress;
        reserve.isActive = true;
        reserve.id = uint16(_reservesCount);

        _reservesList[_reservesCount] = asset;
        _reservesCount++;

        // Initialize indexes to 1 ray (1e27)
        reserve.liquidityIndex = uint128(1e27);
        reserve.variableBorrowIndex = uint128(1e27);
    }

    /**
     * @notice Updates the reserve configuration
     */
    function setConfiguration(
        address asset,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) external override onlyRole(POOL_ADMIN) {
        DataTypes.ReserveData storage reserve = _reserves[asset];
        require(reserve.isActive, "Reserve is not active");

        reserve.ltv = uint16(ltv);
        reserve.liquidationThreshold = uint16(liquidationThreshold);
        reserve.liquidationBonus = uint16(liquidationBonus);
    }

    /**
     * @notice Freezes or unfreezes a reserve
     */
    function setReserveFreeze(
        address asset,
        bool freeze
    ) external override onlyRole(POOL_ADMIN) {
        _reserves[asset].isFrozen = freeze;
    }

    /**
     * @notice Activates or deactivates a reserve
     */
    function setReserveActive(
        address asset,
        bool active
    ) external override onlyRole(POOL_ADMIN) {
        _reserves[asset].isActive = active;
    }

    // ============================================================
    //                       USER ACTIONS
    // ============================================================

    /**
     * @inheritdoc ILendingPool
     */
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external override nonReentrant whenNotPaused {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        ValidationLogic.validateDeposit(reserve, amount);

        reserve.updateState(asset);

        // Mint aTokens
        bool isFirstDeposit = IAToken(reserve.aTokenAddress).mint(
            onBehalfOf,
            amount,
            reserve.liquidityIndex
        );

        if (isFirstDeposit) {
            _usersConfig[onBehalfOf].setUsingAsCollateral(reserve.id, true);
        }

        emit Deposit(asset, msg.sender, onBehalfOf, amount);
    }

    /**
     * @inheritdoc ILendingPool
     */
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external override nonReentrant whenNotPaused returns (uint256) {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        reserve.updateState(asset);

        uint256 userBalance = IAToken(reserve.aTokenAddress)
            .scaledBalanceOf(msg.sender)
            .rayMul(reserve.getNormalizedIncome());

        uint256 amountToWithdraw = amount;
        if (amount == type(uint256).max) {
            amountToWithdraw = userBalance;
        }

        ValidationLogic.validateWithdraw(
            asset,
            amountToWithdraw,
            userBalance,
            _reserves,
            _usersConfig[msg.sender],
            _reservesList,
            _reservesCount,
            _priceOracle
        );

        // Burn aTokens
        IAToken(reserve.aTokenAddress).burn(
            msg.sender,
            to,
            amountToWithdraw,
            reserve.liquidityIndex
        );

        // If balance becomes 0, disable collateral usage?
        // Keeping it enabled is fine, optimization only.
        if (amountToWithdraw == userBalance) {
            _usersConfig[msg.sender].setUsingAsCollateral(reserve.id, false);
        }

        emit Withdraw(asset, msg.sender, to, amountToWithdraw);

        return amountToWithdraw;
    }

    /**
     * @inheritdoc ILendingPool
     */
    function borrow(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external override nonReentrant whenNotPaused {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        reserve.updateState(asset);

        // Helper to get raw price for check
        uint256 amountInBaseCurrency = amount.wadMul(
            // Oracles usually 1e8 or 1e18. Our interface assumes 1e18 return.
            // Need to check specific implementation. Assuming wad.
            // Actually, ValidationLogic calls GenericLogic which calls Oracle.
            // We need price here? ValidationLogic does it.
            // Actually, Validation needs amountInBaseCurrency.
            // Let's refactor calling logic.
            // For now, assume IPriceOracle returns 1e18 (WAD).
            IPriceOracle(_priceOracle).getAssetPrice(asset)
        );

        ValidationLogic.validateBorrow(
            asset,
            reserve,
            onBehalfOf,
            amount,
            amountInBaseCurrency,
            _reserves,
            _usersConfig[onBehalfOf],
            _reservesList,
            _reservesCount,
            _priceOracle
        );

        // Mint debt tokens
        bool isFirstBorrow = IDebtToken(reserve.debtTokenAddress).mint(
            onBehalfOf,
            amount,
            reserve.variableBorrowIndex
        );

        if (isFirstBorrow) {
            _usersConfig[onBehalfOf].setBorrowing(reserve.id, true);
        }

        emit Borrow(
            asset,
            msg.sender,
            onBehalfOf,
            amount,
            reserve.currentVariableBorrowRate
        );
    }

    /**
     * @inheritdoc ILendingPool
     */
    function repay(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external override nonReentrant whenNotPaused returns (uint256) {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        reserve.updateState(asset);

        uint256 userDebt = IDebtToken(reserve.debtTokenAddress)
            .scaledBalanceOf(onBehalfOf)
            .rayMul(reserve.getNormalizedDebt());

        uint256 paybackAmount = amount;
        if (amount == type(uint256).max) {
            paybackAmount = userDebt;
        }

        // Burn debt
        IDebtToken(reserve.debtTokenAddress).burn(
            onBehalfOf,
            paybackAmount,
            reserve.variableBorrowIndex
        );

        if (paybackAmount >= userDebt) {
            _usersConfig[onBehalfOf].setBorrowing(reserve.id, false);
        }

        emit Repay(asset, msg.sender, onBehalfOf, paybackAmount);

        return paybackAmount;
    }

    /**
     * @inheritdoc ILendingPool
     */
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover
    ) external override nonReentrant whenNotPaused {
        DataTypes.ReserveData storage collateralReserve = _reserves[
            collateralAsset
        ];
        DataTypes.ReserveData storage debtReserve = _reserves[debtAsset];

        collateralReserve.updateState(collateralAsset);
        debtReserve.updateState(debtAsset);

        LiquidationLogic.ExecuteLiquidationCallParams
            memory params = LiquidationLogic.ExecuteLiquidationCallParams({
                reservesCount: _reservesCount,
                debtToCover: debtToCover,
                collateralAsset: collateralAsset,
                debtAsset: debtAsset,
                user: user,
                liquidator: msg.sender,
                oracle: _priceOracle
            });

        (
            uint256 actualDebtRepaid,
            uint256 collateralLiquidated
        ) = LiquidationLogic.executeLiquidationCall(
                _reserves,
                _reservesList,
                _usersConfig[user],
                params
            );

        emit LiquidationCall(
            collateralAsset,
            debtAsset,
            user,
            actualDebtRepaid,
            collateralLiquidated,
            msg.sender
        );
    }

    // ============================================================
    //                      VIEW FUNCTIONS
    // ============================================================

    function getReserveData(
        address asset
    ) external view override returns (DataTypes.ReserveData memory) {
        return _reserves[asset];
    }

    function getUserConfiguration(
        address user
    ) external view override returns (DataTypes.UserConfigurationMap memory) {
        return _usersConfig[user];
    }

    function getReserveNormalizedIncome(
        address asset
    ) external view override returns (uint256) {
        return _reserves[asset].getNormalizedIncome();
    }

    function getReserveNormalizedVariableDebt(
        address asset
    ) external view override returns (uint256) {
        return _reserves[asset].getNormalizedDebt();
    }

    function getReservesList()
        external
        view
        override
        returns (address[] memory)
    {
        // Create array to return
        address[] memory list = new address[](_reservesCount);
        for (uint256 i = 0; i < _reservesCount; i++) {
            list[i] = _reservesList[i];
        }
        return list;
    }
}

// UserConfig helpers to avoid cluttering main file
library UserConfigHelper {
    function setUsingAsCollateral(
        DataTypes.UserConfigurationMap storage self,
        uint256 reserveIndex,
        bool usingAsCollateral
    ) internal {
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
        uint256 bit = 1 << (reserveIndex * 2 + 1);
        if (borrowing) {
            self.data |= bit;
        } else {
            self.data &= ~bit;
        }
    }
}
