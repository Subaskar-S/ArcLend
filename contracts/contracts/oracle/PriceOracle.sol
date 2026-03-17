// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";

/**
 * @title PriceOracle
 * @notice Admin-controlled price oracle with staleness protection.
 * @dev All prices are stored and returned in 18 decimal WAD precision.
 *      For production, this should be replaced with Chainlink integration
 *      that normalizes Chainlink's 8-decimal prices to 18 decimals.
 */
contract PriceOracle is IPriceOracle {
    address public owner;

    // Maximum age for a price before it's considered stale (1 hour)
    uint256 public constant MAX_PRICE_STALENESS = 1 hours;

    struct PriceData {
        uint256 price;
        uint256 timestamp;
    }

    mapping(address => PriceData) private _prices;

    modifier onlyOwner() {
        require(msg.sender == owner, "PriceOracle: not owner");
        _;
    }

    constructor(address _owner) {
        require(_owner != address(0), "PriceOracle: zero owner");
        owner = _owner;
    }

    /**
     * @notice Returns the price of an asset in WAD (18 decimal) precision.
     * @dev Reverts if price is not set or is stale (>1 hour old).
     */
    function getAssetPrice(address asset) external view override returns (uint256) {
        PriceData memory pd = _prices[asset];
        require(pd.price > 0, "PriceOracle: price not set");
        require(
            block.timestamp - pd.timestamp <= MAX_PRICE_STALENESS,
            "PriceOracle: price stale"
        );
        return pd.price;
    }

    /**
     * @notice Set the price for an asset.
     * @param asset The underlying token address.
     * @param price Price in WAD (1e18). E.g., 2000e18 = $2000.
     */
    function setAssetPrice(address asset, uint256 price) external override onlyOwner {
        require(asset != address(0), "PriceOracle: zero asset");
        require(price > 0, "PriceOracle: zero price");
        _prices[asset] = PriceData({price: price, timestamp: block.timestamp});
        emit AssetPriceUpdated(asset, price, block.timestamp);
    }

    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "PriceOracle: zero owner");
        owner = newOwner;
    }
}
