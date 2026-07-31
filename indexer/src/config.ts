import { ethers } from "ethers";

/**
 * Combined ABI fragment for all events emitted by the Diamond proxy.
 * Covers LendingPoolFacet, BorrowFacet, LiquidationFacet, and ConfiguratorFacet.
 */
export const DIAMOND_ABI_FRAGMENTS = [
    // LendingPoolFacet
    "event Deposit(address indexed reserve, address user, address indexed onBehalfOf, uint256 amount)",
    "event Withdraw(address indexed reserve, address indexed user, address indexed to, uint256 amount)",
    // BorrowFacet
    "event Borrow(address indexed reserve, address user, address indexed onBehalfOf, uint256 amount, uint256 borrowRate)",
    "event Repay(address indexed reserve, address indexed user, address indexed repayer, uint256 amount)",
    // LiquidationFacet
    "event LiquidationCall(address indexed collateralAsset, address indexed debtAsset, address indexed user, uint256 debtToCover, uint256 liquidatedCollateralAmount, address liquidator)",
    // ConfiguratorFacet
    "event ReserveInitialized(address indexed asset, address indexed aToken, address indexed debtToken, address interestRateStrategy)",
    "event ReserveConfigured(address indexed asset, uint256 ltv, uint256 liquidationThreshold, uint256 liquidationBonus, uint256 reserveFactor)",
    "event ReserveFrozen(address indexed asset, bool frozen)",
    "event ReserveActive(address indexed asset, bool active)",
];

export const DIAMOND_INTERFACE = new ethers.Interface(DIAMOND_ABI_FRAGMENTS);

export const DIAMOND_ADDRESS = (process.env.LENDING_POOL_ADDRESS || "").toLowerCase();

if (!DIAMOND_ADDRESS) {
    console.warn("WARNING: LENDING_POOL_ADDRESS is not set. Indexer will not filter logs by contract address.");
}
