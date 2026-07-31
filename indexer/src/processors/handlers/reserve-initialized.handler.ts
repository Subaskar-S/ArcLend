import { ethers } from "ethers";
import { PoolClient } from "pg";

/**
 * Handles the ReserveInitialized event emitted by ConfiguratorFacet.
 *
 * event ReserveInitialized(
 *     address indexed asset,
 *     address indexed aToken,
 *     address indexed debtToken,
 *     address interestRateStrategy
 * )
 *
 * Inserts a new row into markets. Risk params (ltv, threshold, bonus) default to 0
 * and are filled in by the subsequent ReserveConfigured event.
 *
 * Writes to: markets
 */
export async function handleReserveInitialized(
    parsed: ethers.LogDescription,
    log: ethers.Log,
    client: PoolClient,
): Promise<void> {
    const asset: string = (parsed.args.asset as string).toLowerCase();

    // We don't know the symbol or decimals from the event alone.
    // Use placeholder values; these should be updated by an admin seed script
    // or by calling the ERC20 contract for symbol/decimals.
    await client.query(
        `INSERT INTO markets
             (asset_address, symbol, decimals, ltv, liquidation_threshold, liquidation_bonus,
              reserve_factor, is_active, is_frozen)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         ON CONFLICT (asset_address) DO UPDATE SET
             is_active = TRUE,
             updated_at = NOW()`,
        [
            asset,
            "UNKNOWN",  // symbol — update via admin seed or ERC20 metadata call
            18,         // decimals — update via admin seed or ERC20 metadata call
            0,          // ltv — filled by ReserveConfigured
            0,          // liquidation_threshold — filled by ReserveConfigured
            10000,      // liquidation_bonus — 100% baseline (no bonus yet)
            0,          // reserve_factor — filled by ReserveConfigured
            true,       // is_active — set to true on initialization
            false,      // is_frozen
        ],
    );

    console.log(`[handleReserveInitialized] Market upserted for asset ${asset} — tx ${log.transactionHash}`);
}

/**
 * Handles the ReserveConfigured event emitted by ConfiguratorFacet.
 *
 * event ReserveConfigured(
 *     address indexed asset,
 *     uint256 ltv,
 *     uint256 liquidationThreshold,
 *     uint256 liquidationBonus,
 *     uint256 reserveFactor
 * )
 *
 * Updates risk parameters on an existing market row.
 *
 * Writes to: markets
 */
export async function handleReserveConfigured(
    parsed: ethers.LogDescription,
    log: ethers.Log,
    client: PoolClient,
): Promise<void> {
    const asset: string = (parsed.args.asset as string).toLowerCase();
    const ltv: bigint = parsed.args.ltv as bigint;
    const liquidationThreshold: bigint = parsed.args.liquidationThreshold as bigint;
    const liquidationBonus: bigint = parsed.args.liquidationBonus as bigint;
    const reserveFactor: bigint = parsed.args.reserveFactor as bigint;

    await client.query(
        `UPDATE markets
         SET
             ltv = $1,
             liquidation_threshold = $2,
             liquidation_bonus = $3,
             reserve_factor = $4,
             updated_at = NOW()
         WHERE asset_address = $5`,
        [
            ltv.toString(),
            liquidationThreshold.toString(),
            liquidationBonus.toString(),
            reserveFactor.toString(),
            asset,
        ],
    );

    console.log(`[handleReserveConfigured] Risk params updated for asset ${asset} — tx ${log.transactionHash}`);
}
