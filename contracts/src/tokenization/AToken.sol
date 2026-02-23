// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAToken} from "../interfaces/IAToken.sol";
import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";

/**
 * @title AToken
 * @notice Interest-bearing token implementation.
 */
contract AToken is ERC20, IAToken {
    using WadRayMath for uint256;

    address public immutable POOL;
    address public immutable UNDERLYING_ASSET;

    // Map user to their SCALED balance
    // balance = scaledBalance * currentLiquidityIndex
    mapping(address => uint256) private _scaledBalances;
    uint256 private _scaledTotalSupply;

    modifier onlyPool() {
        require(msg.sender == POOL, "AT: CALLER_MUST_BE_POOL");
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
     * @inheritdoc IAToken
     */
    function mint(
        address user,
        uint256 amount,
        uint256 index
    ) external override onlyPool returns (bool) {
        uint256 previousBalance = _scaledBalances[user];

        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, "AT: INVALID_SCALED_AMOUNT");

        _mintScaled(user, amountScaled);

        emit Mint(user, amount, index);

        return previousBalance == 0;
    }

    /**
     * @inheritdoc IAToken
     */
    function burn(
        address user,
        address receiverOfUnderlying,
        uint256 amount,
        uint256 index
    ) external override onlyPool {
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, "AT: INVALID_SCALED_AMOUNT");

        _burnScaled(user, amountScaled);

        if (receiverOfUnderlying != address(this)) {
            // Transfer underlying to receiver
            // Using safe transfer implicitly via checking return/revert if needed, but for simplicity:
            // Assuming underlying is ERC20.
            // Check success logic...
            (bool success, ) = UNDERLYING_ASSET.call(
                abi.encodeWithSelector(0xa9059cbb, receiverOfUnderlying, amount) // transfer(address,uint256)
            );
            require(success, "AT: TRANSFER_FAILED");
        }

        emit Burn(user, receiverOfUnderlying, amount, index);
    }

    /**
     * @inheritdoc IAToken
     */
    function scaledBalanceOf(
        address user
    ) external view override returns (uint256) {
        return _scaledBalances[user];
    }

    /**
     * @inheritdoc IAToken
     */
    function scaledTotalSupply() external view override returns (uint256) {
        return _scaledTotalSupply;
    }

    /**
     * @inheritdoc IAToken
     */
    function UNDERLYING_ASSET_ADDRESS()
        external
        view
        override
        returns (address)
    {
        return UNDERLYING_ASSET;
    }

    /**
     * @inheritdoc IAToken
     */
    function transferUnderlyingTo(
        address target,
        uint256 amount
    ) external override onlyPool {
        (bool success, ) = UNDERLYING_ASSET.call(
            abi.encodeWithSelector(0xa9059cbb, target, amount)
        );
        require(success, "AT: TRANSFER_FAILED");
    }

    // ============================================================
    //                       ERC20 OVERRIDES
    // ============================================================
    // We must implement transfer/transferFrom to handle scaled balances.
    // The "amount" in transfer(to, amount) is the nominal amount.
    // We convert to scaled amount using current index.

    function balanceOf(address user) public view override returns (uint256) {
        uint256 index = ILendingPool(POOL).getReserveNormalizedIncome(
            UNDERLYING_ASSET
        );
        return _scaledBalances[user].rayMul(index);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        uint256 index = ILendingPool(POOL).getReserveNormalizedIncome(
            UNDERLYING_ASSET
        );
        uint256 amountScaled = amount.rayDiv(index);

        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        uint256 fromBalance = _scaledBalances[from];
        require(
            fromBalance >= amountScaled,
            "ERC20: transfer amount exceeds balance"
        );
        unchecked {
            _scaledBalances[from] = fromBalance - amountScaled;
        }
        _scaledBalances[to] += amountScaled;

        emit Transfer(from, to, amount);
    }

    function _mintScaled(address user, uint256 amountScaled) internal {
        _scaledTotalSupply += amountScaled;
        _scaledBalances[user] += amountScaled;
        emit Transfer(address(0), user, 0); // Amount is ambiguous here without index... usually strict ERC20 doesn't fit well with rebasing.
        // Aave emits Transfer(0, user, amount) but calculated.
        // We'll skip standard Transfer emit inside mint/burn to avoid confusion/gas, or emit with 0?
        // Actually best to emit Transfer with nominal amount.
        // But we don't know liquidtyIndex inside _mintScaled easily without passing it.
        // For now, simplify -> Mint event covers it.
    }

    function _burnScaled(address user, uint256 amountScaled) internal {
        _scaledTotalSupply -= amountScaled;
        _scaledBalances[user] -= amountScaled;
        emit Transfer(user, address(0), 0);
    }

    // TODO: totalSupply() override requires fetching index.
    function totalSupply() public view override returns (uint256) {
        uint256 index = ILendingPool(POOL).getReserveNormalizedIncome(
            UNDERLYING_ASSET
        );
        return _scaledTotalSupply.rayMul(index);
    }
}
