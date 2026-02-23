// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title IAToken
 * @notice Interface for the interest-bearing aToken.
 */
interface IAToken {
    event Mint(address indexed from, uint256 value, uint256 index);
    event Burn(
        address indexed from,
        address indexed target,
        uint256 value,
        uint256 index
    );

    /**
     * @notice Mints aTokens to the user.
     * @dev Only callable by the LendingPool.
     * @param user The address receiving the minted tokens
     * @param amount The amount of tokens to mint (in underlying terms)
     * @param index The current liquidity index (ray)
     * @return Whether this is the first deposit for this user in this reserve
     */
    function mint(
        address user,
        uint256 amount,
        uint256 index
    ) external returns (bool);

    /**
     * @notice Burns aTokens from the user and sends underlying to the receiver.
     * @dev Only callable by the LendingPool.
     * @param user The owner of the aTokens
     * @param receiverOfUnderlying The address that will receive the underlying
     * @param amount The amount of underlying to withdraw
     * @param index The current liquidity index (ray)
     */
    function burn(
        address user,
        address receiverOfUnderlying,
        uint256 amount,
        uint256 index
    ) external;

    /**
     * @notice Returns the scaled balance of the user.
     * @dev The scaled balance is the balance divided by the liquidity index at the time of deposit.
     *      balanceOf(user) = scaledBalance * currentLiquidityIndex
     * @param user The user address
     * @return The scaled balance
     */
    function scaledBalanceOf(address user) external view returns (uint256);

    /**
     * @notice Returns the scaled total supply.
     * @return The scaled total supply
     */
    function scaledTotalSupply() external view returns (uint256);

    /**
     * @notice Returns the address of the underlying asset.
     */
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    /**
     * @notice Transfers the underlying asset to the target.
     * @dev Used during liquidation to transfer collateral.
     * @param target The recipient of the underlying
     * @param amount The amount to transfer
     */
    function transferUnderlyingTo(address target, uint256 amount) external;
}
