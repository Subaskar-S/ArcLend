// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAToken} from "../interfaces/IAToken.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";

/**
 * @title AToken
 * @notice Interest-bearing receipt token. Balance grows as the pool earns interest.
 *
 * BUG FIXES vs original:
 * ─────────────────────────────────────────────────────────────────────
 * [FIX-4a] _mintScaled(): Now emits Transfer(address(0), user, nominalAmount)
 *           The original emitted Transfer with amount=0, breaking wallets and indexers.
 * [FIX-4b] _burnScaled(): Emits Transfer(user, address(0), nominalAmount).
 * [FIX-4c] burn(): Uses SafeERC20.safeTransfer() instead of low-level .call().
 *           The original used raw call with ABI encoding, which silently fails for
 *           non-standard ERC20 tokens (e.g., USDT does not return bool on transfer).
 *
 * Design:
 * ────────
 * Balances are stored as SCALED values. The actual balance is:
 *   actualBalance = scaledBalance * currentLiquidityIndex
 *
 * This makes deposits/withdrawals O(1) regardless of time elapsed.
 * The pool calls mint() on deposit and burn() on withdrawal/liquidation.
 */
contract AToken is ERC20, IAToken {
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;

    address public immutable POOL;
    address public immutable UNDERLYING_ASSET;

    mapping(address => uint256) private _scaledBalances;
    uint256 private _scaledTotalSupply;

    modifier onlyPool() {
        require(msg.sender == POOL, "AToken: caller not pool");
        _;
    }

    constructor(
        address pool,
        address underlyingAsset,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) {
        require(pool != address(0), "AToken: zero pool");
        require(underlyingAsset != address(0), "AToken: zero asset");
        POOL = pool;
        UNDERLYING_ASSET = underlyingAsset;
    }

    // ─── Pool-only ────────────────────────────────────────────────────────

    /**
     * @notice Mint aTokens on deposit.
     * @param user The recipient address.
     * @param amount The nominal amount deposited.
     * @param index The current liquidity index (ray).
     * @return isFirstDeposit True if this was the user's first deposit.
     */
    function mint(
        address user,
        uint256 amount,
        uint256 index
    ) external override onlyPool returns (bool) {
        uint256 previousScaledBalance = _scaledBalances[user];
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, "AToken: invalid scaled amount");

        _scaledTotalSupply += amountScaled;
        _scaledBalances[user] += amountScaled;

        // ── [FIX-4a]: Emit Transfer with the nominal (not scaled) amount ─────
        emit Transfer(address(0), user, amount);
        emit Mint(user, amount, index);

        return previousScaledBalance == 0;
    }

    /**
     * @notice Burn aTokens on withdrawal or liquidation.
     * @param user The address whose aTokens are burned.
     * @param receiverOfUnderlying The address receiving the underlying asset.
     * @param amount The nominal amount to return.
     * @param index The current liquidity index (ray).
     */
    function burn(
        address user,
        address receiverOfUnderlying,
        uint256 amount,
        uint256 index
    ) external override onlyPool {
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, "AToken: invalid scaled amount");
        require(_scaledBalances[user] >= amountScaled, "AToken: burn exceeds balance");

        _scaledTotalSupply -= amountScaled;
        _scaledBalances[user] -= amountScaled;

        // ── [FIX-4b]: Emit Transfer with nominal amount ───────────────────────
        emit Transfer(user, address(0), amount);

        if (receiverOfUnderlying != address(this)) {
            // ── [FIX-4c]: Use SafeERC20 instead of raw call ───────────────────
            // SafeERC20 handles USDT-style tokens that don't return bool.
            IERC20(UNDERLYING_ASSET).safeTransfer(receiverOfUnderlying, amount);
        }

        emit Burn(user, receiverOfUnderlying, amount, index);
    }

    function transferUnderlyingTo(
        address target,
        uint256 amount
    ) external override onlyPool {
        IERC20(UNDERLYING_ASSET).safeTransfer(target, amount);
    }

    // ─── View ─────────────────────────────────────────────────────────────

    function scaledBalanceOf(address user) external view override returns (uint256) {
        return _scaledBalances[user];
    }

    function scaledTotalSupply() external view override returns (uint256) {
        return _scaledTotalSupply;
    }

    function UNDERLYING_ASSET_ADDRESS() external view override returns (address) {
        return UNDERLYING_ASSET;
    }

    // ─── ERC20 Overrides ─────────────────────────────────────────────────
    // balanceOf and totalSupply reflect the nominal (interest-accrued) balance
    // by calling back to the pool for the current liquidity index.

    function balanceOf(address user) public view override returns (uint256) {
        // Fetch current normalized income from pool
        (bool success, bytes memory data) = POOL.staticcall(
            abi.encodeWithSignature("getReserveNormalizedIncome(address)", UNDERLYING_ASSET)
        );
        if (!success || data.length == 0) return _scaledBalances[user];
        uint256 index = abi.decode(data, (uint256));
        return _scaledBalances[user].rayMul(index);
    }

    function totalSupply() public view override returns (uint256) {
        (bool success, bytes memory data) = POOL.staticcall(
            abi.encodeWithSignature("getReserveNormalizedIncome(address)", UNDERLYING_ASSET)
        );
        if (!success || data.length == 0) return _scaledTotalSupply;
        uint256 index = abi.decode(data, (uint256));
        return _scaledTotalSupply.rayMul(index);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        (bool success, bytes memory data) = POOL.staticcall(
            abi.encodeWithSignature("getReserveNormalizedIncome(address)", UNDERLYING_ASSET)
        );
        require(success && data.length > 0, "AToken: pool call failed");
        uint256 index = abi.decode(data, (uint256));
        uint256 amountScaled = amount.rayDiv(index);

        require(from != address(0), "ERC20: transfer from zero");
        require(to != address(0), "ERC20: transfer to zero");
        require(_scaledBalances[from] >= amountScaled, "ERC20: transfer amount exceeds balance");

        unchecked {
            _scaledBalances[from] -= amountScaled;
        }
        _scaledBalances[to] += amountScaled;
        emit Transfer(from, to, amount);
    }
}
