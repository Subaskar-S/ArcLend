// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title IDebtToken
 * @notice Interface for the non-transferable variable debt token.
 */
interface IDebtToken {
    event Mint(address indexed from, uint256 value, uint256 index);
    event Burn(address indexed from, uint256 value, uint256 index);

    /**
     * @notice Mints debt tokens to the user.
     * @dev Only callable by the LendingPool.
     * @param user The address receiving the minted debt tokens
     * @param amount The amount of debt (in underlying terms)
     * @param index The current variable borrow index (ray)
     * @return Whether this is the user's first borrow in this reserve
     */
    function mint(
        address user,
        uint256 amount,
        uint256 index
    ) external returns (bool);

    /**
     * @notice Burns debt tokens from the user.
     * @dev Only callable by the LendingPool.
     * @param user The user whose debt is being burned
     * @param amount The amount of underlying being repaid
     * @param index The current variable borrow index (ray)
     */
    function burn(address user, uint256 amount, uint256 index) external;

    /**
     * @notice Returns the scaled balance of the user.
     * @dev The scaled balance is the principal debt.
     *      balanceOf(user) = scaledBalance * currentVariableBorrowIndex
     */
    function scaledBalanceOf(address user) external view returns (uint256);

    /**
     * @notice Returns the scaled total supply (total principal owed).
     */
    function scaledTotalSupply() external view returns (uint256);

    /**
     * @notice Returns the address of the underlying asset.
     */
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
