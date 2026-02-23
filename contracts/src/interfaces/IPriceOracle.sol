// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title IPriceOracle
 * @notice Interface for the price oracle.
 * @dev Chainlink-compatible interface with staleness protection.
 */
interface IPriceOracle {
    /**
     * @notice Returns the asset price in the base currency (ETH/USD).
     * @param asset The address of the asset
     * @return The price in base currency units (wad precision, 1e18)
     */
    function getAssetPrice(address asset) external view returns (uint256);

    /**
     * @notice Returns the prices of all supported assets.
     * @param assets Array of asset addresses
     * @return Array of prices in base currency units
     */
    function getAssetsPrices(
        address[] calldata assets
    ) external view returns (uint256[] memory);

    /**
     * @notice Returns the address of the price source for an asset.
     */
    function getSourceOfAsset(address asset) external view returns (address);
}
