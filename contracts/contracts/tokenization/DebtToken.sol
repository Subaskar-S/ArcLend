// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IDebtToken} from "../interfaces/IDebtToken.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";

/**
 * @title DebtToken
 * @notice Non-transferable debt token. Balance grows as borrowers accrue interest.
 * @dev Transfer functions are disabled — debt is tied to the borrower's address.
 *      Scaled balance × current borrow index = actual debt owed.
 */
contract DebtToken is IDebtToken {
    using WadRayMath for uint256;

    address public immutable POOL;
    address public immutable UNDERLYING_ASSET;
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    mapping(address => uint256) private _scaledBalances;
    uint256 private _scaledTotalSupply;

    event Transfer(address indexed from, address indexed to, uint256 value);

    modifier onlyPool() {
        require(msg.sender == POOL, "DebtToken: caller not pool");
        _;
    }

    constructor(
        address pool,
        address underlyingAsset,
        string memory _name,
        string memory _symbol
    ) {
        require(pool != address(0), "DebtToken: zero pool");
        POOL = pool;
        UNDERLYING_ASSET = underlyingAsset;
        name = _name;
        symbol = _symbol;
    }

    /**
     * @notice Mint debt tokens when a user borrows.
     * @param user The borrower address.
     * @param amount The nominal borrow amount.
     * @param index The current variable borrow index.
     * @return isFirstBorrow True if this is the user's first borrow.
     */
    function mint(
        address user,
        uint256 amount,
        uint256 index
    ) external override onlyPool returns (bool) {
        uint256 previousScaledBalance = _scaledBalances[user];
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, "DebtToken: invalid amount");

        _scaledTotalSupply += amountScaled;
        _scaledBalances[user] += amountScaled;

        emit Transfer(address(0), user, amount);
        emit Mint(user, amount, index);

        return previousScaledBalance == 0;
    }

    /**
     * @notice Burn debt tokens when a user repays or is liquidated.
     * @param user The borrower address.
     * @param amount The nominal amount being repaid.
     * @param index The current variable borrow index.
     */
    function burn(
        address user,
        uint256 amount,
        uint256 index
    ) external override onlyPool {
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, "DebtToken: invalid amount");
        require(_scaledBalances[user] >= amountScaled, "DebtToken: burn exceeds balance");

        _scaledTotalSupply -= amountScaled;
        _scaledBalances[user] -= amountScaled;

        emit Transfer(user, address(0), amount);
        emit Burn(user, amount, index);
    }

    // ─── View ─────────────────────────────────────────────────────────────

    function scaledBalanceOf(address user) external view override returns (uint256) {
        return _scaledBalances[user];
    }

    function scaledTotalSupply() external view override returns (uint256) {
        return _scaledTotalSupply;
    }

    function balanceOf(address user) external view returns (uint256) {
        (bool success, bytes memory data) = POOL.staticcall(
            abi.encodeWithSignature("getReserveNormalizedVariableDebt(address)", UNDERLYING_ASSET)
        );
        if (!success || data.length == 0) return _scaledBalances[user];
        uint256 index = abi.decode(data, (uint256));
        return _scaledBalances[user].rayMul(index);
    }

    function totalSupply() external view returns (uint256) {
        (bool success, bytes memory data) = POOL.staticcall(
            abi.encodeWithSignature("getReserveNormalizedVariableDebt(address)", UNDERLYING_ASSET)
        );
        if (!success || data.length == 0) return _scaledTotalSupply;
        uint256 index = abi.decode(data, (uint256));
        return _scaledTotalSupply.rayMul(index);
    }

    // ─── Non-transferable ─────────────────────────────────────────────────

    function transfer(address, uint256) external pure returns (bool) {
        revert("DebtToken: transfer not allowed");
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert("DebtToken: transfer not allowed");
    }

    function approve(address, uint256) external pure returns (bool) {
        revert("DebtToken: approve not allowed");
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }
}
