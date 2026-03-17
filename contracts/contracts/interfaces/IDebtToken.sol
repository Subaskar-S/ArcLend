// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IDebtToken {
    event Mint(address indexed user, uint256 amount, uint256 index);
    event Burn(address indexed user, uint256 amount, uint256 index);

    function mint(address user, uint256 amount, uint256 index) external returns (bool);
    function burn(address user, uint256 amount, uint256 index) external;
    function scaledBalanceOf(address user) external view returns (uint256);
    function scaledTotalSupply() external view returns (uint256);
}
