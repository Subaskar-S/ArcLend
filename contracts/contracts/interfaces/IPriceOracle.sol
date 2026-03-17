// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IPriceOracle {
    event AssetPriceUpdated(address indexed asset, uint256 price, uint256 timestamp);
    event EthPriceUpdated(uint256 price, uint256 timestamp);

    /**
     * @notice Returns the price of an asset in base currency.
     * @dev MUST return price in 18 decimal WAD precision.
     *      All consumers (GenericLogic, LiquidationFacet, BorrowFacet) rely on this.
     * @param asset The underlying ERC20 token address.
     * @return The price (WAD, 1e18).
     */
    function getAssetPrice(address asset) external view returns (uint256);

    function setAssetPrice(address asset, uint256 price) external;
}
