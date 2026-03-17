// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {AppStorage, LibAppStorage} from "../AppStorage.sol";
import {LibAccessControl} from "../libraries/LibAccessControl.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {ReserveLogic} from "../libraries/ReserveLogic.sol";
import {ValidationLogic} from "../libraries/ValidationLogic.sol";
import {GenericLogic} from "../libraries/GenericLogic.sol";
import {IAToken} from "../interfaces/IAToken.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title LendingPoolFacet
 * @notice Handles deposit and withdraw operations.
 *
 * BUG FIXES applied vs original LendingPool.sol:
 * ─────────────────────────────────────────────────
 * [FIX-1] deposit(): Added IERC20.safeTransferFrom() BEFORE minting aTokens.
 *         Previously, aTokens were minted without receiving the underlying asset.
 * [FIX-2] All storage accessed via LibAppStorage.appStorage() — Diamond-compatible.
 * [FIX-3] Pause check uses LibAccessControl.requireNotPaused() — decoupled from inheritance.
 */
contract LendingPoolFacet {
    using ReserveLogic for DataTypes.ReserveData;
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;

    // ─── Events ──────────────────────────────────────────────────────────
    event Deposit(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount
    );
    event Withdraw(
        address indexed reserve,
        address indexed user,
        address indexed to,
        uint256 amount
    );

    // ─── User-facing actions ──────────────────────────────────────────────

    /**
     * @notice Deposit underlying asset and receive aTokens.
     * @param asset The address of the underlying ERC20 asset.
     * @param amount The amount to deposit (in asset decimals).
     * @param onBehalfOf The address that will receive the aTokens.
     */
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external {
        LibAccessControl.requireNotPaused();
        AppStorage storage s = LibAppStorage.appStorage();
        DataTypes.ReserveData storage reserve = s.reserves[asset];

        ValidationLogic.validateDeposit(reserve, amount);

        reserve.updateState(asset);

        // ── [FIX-1]: Transfer tokens FROM depositor TO aToken contract ─────
        // The underlying asset must be held by the aToken contract so it can
        // be returned to withdrawers. Without this, minting aTokens out of thin air.
        IERC20(asset).safeTransferFrom(msg.sender, reserve.aTokenAddress, amount);

        // Mint aTokens to onBehalfOf
        bool isFirstDeposit = IAToken(reserve.aTokenAddress).mint(
            onBehalfOf,
            amount,
            reserve.liquidityIndex
        );

        if (isFirstDeposit) {
            _setUsingAsCollateral(s.usersConfig[onBehalfOf], uint256(reserve.id), true);
        }

        // Update interest rates after deposit changes liquidity
        reserve.updateInterestRates(asset, amount, 0);

        emit Deposit(asset, msg.sender, onBehalfOf, amount);
    }

    /**
     * @notice Withdraw deposited assets, burning aTokens.
     * @param asset The underlying asset to withdraw.
     * @param amount The amount to withdraw. Use type(uint256).max to withdraw all.
     * @param to The address receiving the underlying asset.
     * @return amountToWithdraw The actual amount withdrawn.
     */
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256) {
        LibAccessControl.requireNotPaused();
        AppStorage storage s = LibAppStorage.appStorage();
        DataTypes.ReserveData storage reserve = s.reserves[asset];

        reserve.updateState(asset);

        uint256 userBalance = IAToken(reserve.aTokenAddress)
            .scaledBalanceOf(msg.sender)
            .rayMul(reserve.getNormalizedIncome());

        uint256 amountToWithdraw = amount == type(uint256).max ? userBalance : amount;

        ValidationLogic.validateWithdraw(
            asset,
            amountToWithdraw,
            userBalance,
            s.reserves,
            s.usersConfig[msg.sender],
            s.reservesList,
            s.reservesCount,
            s.priceOracle
        );

        // Burn aTokens — the aToken contract sends underlying to `to`
        IAToken(reserve.aTokenAddress).burn(
            msg.sender,
            to,
            amountToWithdraw,
            reserve.liquidityIndex
        );

        if (amountToWithdraw == userBalance) {
            _setUsingAsCollateral(s.usersConfig[msg.sender], uint256(reserve.id), false);
        }

        // Update interest rates after withdraw reduces liquidity
        reserve.updateInterestRates(asset, 0, amountToWithdraw);

        emit Withdraw(asset, msg.sender, to, amountToWithdraw);
        return amountToWithdraw;
    }

    // ─── Internal helpers ─────────────────────────────────────────────────
    function _setUsingAsCollateral(
        DataTypes.UserConfigurationMap storage userConfig,
        uint256 reserveIndex,
        bool usingAsCollateral
    ) internal {
        uint256 bit = 1 << (reserveIndex * 2);
        if (usingAsCollateral) {
            userConfig.data |= bit;
        } else {
            userConfig.data &= ~bit;
        }
    }
}
