// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IAToken {
    event Mint(address indexed user, uint256 amount, uint256 index);
    event Burn(address indexed user, address indexed receiver, uint256 amount, uint256 index);

    function mint(address user, uint256 amount, uint256 index) external returns (bool);
    function burn(address user, address receiverOfUnderlying, uint256 amount, uint256 index) external;
    function transferUnderlyingTo(address target, uint256 amount) external;
    function scaledBalanceOf(address user) external view returns (uint256);
    function scaledTotalSupply() external view returns (uint256);
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
