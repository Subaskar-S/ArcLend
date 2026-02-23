// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title PriceOracle
 * @notice Simple admin-controlled price oracle for Phase 1.
 * @dev Compatible with Chainlink interface expectation (returns prices).
 */
contract PriceOracle is IPriceOracle, AccessControl {
    bytes32 public constant ORACLE_ADMIN = keccak256("ORACLE_ADMIN");

    // Asset => Price in Base Currency (e.g. ETH or USD)
    // Precision: 1e18 (Wad)
    mapping(address => uint256) private _prices;

    event AssetPriceUpdated(
        address indexed asset,
        uint256 price,
        uint256 timestamp
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_ADMIN, msg.sender);
    }

    /**
     * @notice Sets the price for an asset.
     * @param asset The asset address
     * @param price The price (1e18 precision)
     */
    function setAssetPrice(
        address asset,
        uint256 price
    ) external onlyRole(ORACLE_ADMIN) {
        _prices[asset] = price;
        emit AssetPriceUpdated(asset, price, block.timestamp);
    }

    /**
     * @notice Batch set prices.
     */
    function setAssetsPrices(
        address[] calldata assets,
        uint256[] calldata prices
    ) external onlyRole(ORACLE_ADMIN) {
        require(assets.length == prices.length, "PO: ARRAY_LENGTH_MISMATCH");
        for (uint256 i = 0; i < assets.length; i++) {
            _prices[assets[i]] = prices[i];
            emit AssetPriceUpdated(assets[i], prices[i], block.timestamp);
        }
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function getAssetPrice(
        address asset
    ) external view override returns (uint256) {
        return _prices[asset];
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function getAssetsPrices(
        address[] calldata assets
    ) external view override returns (uint256[] memory) {
        uint256[] memory prices = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            prices[i] = _prices[assets[i]];
        }
        return prices;
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function getSourceOfAsset(
        address asset
    ) external view override returns (address) {
        return address(this);
    }
}
