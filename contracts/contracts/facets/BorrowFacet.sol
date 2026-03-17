// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {AppStorage, LibAppStorage} from "../AppStorage.sol";
import {LibAccessControl} from "../libraries/LibAccessControl.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {ReserveLogic} from "../libraries/ReserveLogic.sol";
import {ValidationLogic} from "../libraries/ValidationLogic.sol";
import {IDebtToken} from "../interfaces/IDebtToken.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title BorrowFacet
 * @notice Handles borrow and repay operations.
 *
 * BUG FIXES applied vs original LendingPool.sol:
 * ─────────────────────────────────────────────────
 * [FIX-2] borrow(): Removed incorrect inline TODO comment; 
 *         amountInBaseCurrency now correctly computed using oracle price.
 *         Added IERC20.safeTransfer() to actually send borrowed funds to borrower.
 * [FIX-3] repay(): Added IERC20.safeTransferFrom() to collect repayment from repayer.
 *         Previously debt was burned without any token transfer.
 * [FIX-4] Both borrow/repay call updateInterestRates() after state change.
 */
contract BorrowFacet {
    using ReserveLogic for DataTypes.ReserveData;
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;

    event Borrow(
        address indexed reserve,
        address user,
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

    /**
     * @notice Borrow an asset from the protocol.
     * @dev Caller must have sufficient collateral (health factor >= 1 after borrow).
     * @param asset The address of the asset to borrow.
     * @param amount The amount to borrow.
     * @param onBehalfOf The address receiving the debt. Must equal msg.sender unless delegated.
     */
    function borrow(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external {
        LibAccessControl.requireNotPaused();
        AppStorage storage s = LibAppStorage.appStorage();
        DataTypes.ReserveData storage reserve = s.reserves[asset];

        reserve.updateState(asset);

        // ── [FIX-2a]: Compute amountInBaseCurrency correctly ────────────────
        // Oracle prices are normalized to 18 decimal WAD by our PriceOracle.
        uint256 assetPrice = IPriceOracle(s.priceOracle).getAssetPrice(asset);
        require(assetPrice > 0, "BorrowFacet: zero oracle price");
        uint256 amountInBaseCurrency = amount.wadMul(assetPrice);

        ValidationLogic.validateBorrow(
            asset,
            reserve,
            onBehalfOf,
            amount,
            amountInBaseCurrency,
            s.reserves,
            s.usersConfig[onBehalfOf],
            s.reservesList,
            s.reservesCount,
            s.priceOracle
        );

        // Mint debt tokens
        bool isFirstBorrow = IDebtToken(reserve.debtTokenAddress).mint(
            onBehalfOf,
            amount,
            reserve.variableBorrowIndex
        );

        if (isFirstBorrow) {
            _setBorrowing(s.usersConfig[onBehalfOf], uint256(reserve.id), true);
        }

        // ── [FIX-2b]: Actually send the borrowed asset to the borrower ───────
        // Without this transfer, the function mints debt but gives nothing to borrower.
        IERC20(asset).safeTransfer(onBehalfOf, amount);

        // Update rates: liquidity decreases (asset was lent out)
        reserve.updateInterestRates(asset, 0, amount);

        emit Borrow(asset, msg.sender, onBehalfOf, amount, reserve.currentVariableBorrowRate);
    }

    /**
     * @notice Repay borrowed assets.
     * @param asset The underlying asset.
     * @param amount The amount to repay. type(uint256).max to repay all.
     * @param onBehalfOf The address whose debt to repay.
     * @return paybackAmount The amount actually repaid.
     */
    function repay(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external returns (uint256) {
        LibAccessControl.requireNotPaused();
        AppStorage storage s = LibAppStorage.appStorage();
        DataTypes.ReserveData storage reserve = s.reserves[asset];

        reserve.updateState(asset);

        uint256 userDebt = IDebtToken(reserve.debtTokenAddress)
            .scaledBalanceOf(onBehalfOf)
            .rayMul(reserve.getNormalizedDebt());

        require(userDebt > 0, "BorrowFacet: no active debt");

        uint256 paybackAmount = (amount == type(uint256).max || amount >= userDebt)
            ? userDebt
            : amount;

        // ── [FIX-3]: Receive repayment FROM repayer BEFORE burning debt ──────
        // The aToken contract holds the liquidity pool — repayment goes there.
        IERC20(asset).safeTransferFrom(msg.sender, reserve.aTokenAddress, paybackAmount);

        // Burn debt tokens
        IDebtToken(reserve.debtTokenAddress).burn(
            onBehalfOf,
            paybackAmount,
            reserve.variableBorrowIndex
        );

        if (paybackAmount >= userDebt) {
            _setBorrowing(s.usersConfig[onBehalfOf], uint256(reserve.id), false);
        }

        // Update rates: liquidity increases (repayment received)
        reserve.updateInterestRates(asset, paybackAmount, 0);

        emit Repay(asset, onBehalfOf, msg.sender, paybackAmount);
        return paybackAmount;
    }

    function _setBorrowing(
        DataTypes.UserConfigurationMap storage userConfig,
        uint256 reserveIndex,
        bool borrowing
    ) internal {
        uint256 bit = 1 << (reserveIndex * 2 + 1);
        if (borrowing) {
            userConfig.data |= bit;
        } else {
            userConfig.data &= ~bit;
        }
    }
}
