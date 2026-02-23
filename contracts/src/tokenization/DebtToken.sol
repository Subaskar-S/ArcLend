// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IDebtToken} from "../interfaces/IDebtToken.sol";
import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";

/**
 * @title DebtToken
 * @notice Non-transferable token representing variable debt.
 */
contract DebtToken is IDebtToken, ERC20 {
    using WadRayMath for uint256;

    address public immutable POOL;
    address public immutable UNDERLYING_ASSET;

    mapping(address => uint256) private _scaledBalances;
    uint256 private _scaledTotalSupply;

    modifier onlyPool() {
        require(msg.sender == POOL, "DT: CALLER_MUST_BE_POOL");
        _;
    }

    constructor(
        address pool,
        address underlyingAsset,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) {
        POOL = pool;
        UNDERLYING_ASSET = underlyingAsset;
    }

    /**
     * @notice Mints debt.
     * @param user The user receiving the debt
     * @param amount The amount of debt (underlying)
     * @param index The current variable borrow index
     * @return true if this is the first borrow for the user
     */
    function mint(
        address user,
        uint256 amount,
        uint256 index
    ) external override onlyPool returns (bool) {
        uint256 previousBalance = _scaledBalances[user];

        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, "DT: INVALID_SCALED_AMOUNT");

        _mintScaled(user, amountScaled);

        emit Mint(user, amount, index);

        return previousBalance == 0;
    }

    /**
     * @notice Burns debt.
     * @param user The user repaying the debt
     * @param amount The amount of debt to burn (underlying)
     * @param index The current variable borrow index
     */
    function burn(
        address user,
        uint256 amount,
        uint256 index
    ) external override onlyPool {
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, "DT: INVALID_SCALED_AMOUNT");

        _burnScaled(user, amountScaled);

        emit Burn(user, amount, index);
    }

    function scaledBalanceOf(
        address user
    ) external view override returns (uint256) {
        return _scaledBalances[user];
    }

    function scaledTotalSupply() external view override returns (uint256) {
        return _scaledTotalSupply;
    }

    function UNDERLYING_ASSET_ADDRESS()
        external
        view
        override
        returns (address)
    {
        return UNDERLYING_ASSET;
    }

    // ============================================================
    //                       ERC20 OVERRIDES
    // ============================================================

    function balanceOf(address user) public view override returns (uint256) {
        uint256 index = ILendingPool(POOL).getReserveNormalizedVariableDebt(
            UNDERLYING_ASSET
        );
        return _scaledBalances[user].rayMul(index);
    }

    function totalSupply() public view override returns (uint256) {
        uint256 index = ILendingPool(POOL).getReserveNormalizedVariableDebt(
            UNDERLYING_ASSET
        );
        return _scaledTotalSupply.rayMul(index);
    }

    function transfer(address, uint256) public virtual override returns (bool) {
        revert("DT: TRANSFER_NOT_ALLOWED");
    }

    function transferFrom(
        address,
        address,
        uint256
    ) public virtual override returns (bool) {
        revert("DT: TRANSFER_NOT_ALLOWED");
    }

    function approve(address, uint256) public virtual override returns (bool) {
        revert("DT: APPROVAL_NOT_ALLOWED");
    }

    function increaseAllowance(
        address,
        uint256
    ) public virtual override returns (bool) {
        revert("DT: ALLOWANCE_NOT_ALLOWED");
    }

    function decreaseAllowance(
        address,
        uint256
    ) public virtual override returns (bool) {
        revert("DT: ALLOWANCE_NOT_ALLOWED");
    }

    // Internal helpers
    function _mintScaled(address user, uint256 amountScaled) internal {
        _scaledBalances[user] += amountScaled;
        _scaledTotalSupply += amountScaled;
        emit Transfer(address(0), user, amountScaled); // Emitting scaled amount to comply with ERC20 roughly
    }

    function _burnScaled(address user, uint256 amountScaled) internal {
        _scaledBalances[user] -= amountScaled;
        _scaledTotalSupply -= amountScaled;
        emit Transfer(user, address(0), amountScaled);
    }
}
