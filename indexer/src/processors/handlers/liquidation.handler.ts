import { ethers } from "ethers";
import { PoolClient } from "pg";
import { upsertUser, resolveUserId, resolveMarketId } from "./helpers";
import { updateHealthFactor } from "../health-factor-updater";

/**
 * Handles the LiquidationCall event emitted by LiquidationFacet.
 *
 * event LiquidationCall(
 *     address indexed collateralAsset,
 *     address indexed debtAsset,
 *     address indexed user,
 *     uint256 debtToCover,
 *     uint256 liquidatedCollateralAmount,
 *     address liquidator
 * )
 *
 * Writes to: users, liquidations, user_positions (decrements both balances)
 */
export async function handleLiquidation(
    parsed: ethers.LogDescription,
    log: ethers.Log,
    blockTimestamp: Date,
    client: PoolClient,
): Promise<void> {
    const collateralAsset: string = (parsed.args.collateralAsset as string).toLowerCase();
    const debtAsset: string = (parsed.args.debtAsset as string).toLowerCase();
    const liquidatedUser: string = (parsed.args.user as string).toLowerCase();
    const liquidator: string = (parsed.args.liquidator as string).toLowerCase();
    const debtToCover: bigint = parsed.args.debtToCover as bigint;
    const collateralSeized: bigint = parsed.args.liquidatedCollateralAmount as bigint;

    await upsertUser(liquidatedUser, client);
    await upsertUser(liquidator, client);

    const liquidatedUserId = await resolveUserId(liquidatedUser, client);
    const collateralMarketId = await resolveMarketId(collateralAsset, client);
    const debtMarketId = await resolveMarketId(debtAsset, client);

    if (!collateralMarketId || !debtMarketId) {
        console.warn(
            `[handleLiquidation] Unknown market(s) — collateral: ${collateralAsset}, debt: ${debtAsset} — tx ${log.transactionHash}. Skipping.`,
        );
        return;
    }

    // Append-only liquidation history record
    await client.query(
        `INSERT INTO liquidations
             (tx_hash, log_index, collateral_market_id, debt_market_id, liquidated_user_id,
              liquidator_address, debt_to_cover, collateral_seized, timestamp)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         ON CONFLICT (tx_hash, log_index) DO NOTHING`,
        [
            log.transactionHash,
            log.index,
            collateralMarketId,
            debtMarketId,
            liquidatedUserId,
            liquidator,         // stored as raw address — liquidator may not be a protocol user
            debtToCover.toString(),
            collateralSeized.toString(),
            blockTimestamp,
        ],
    );

    // Decrement the liquidated user's collateral position
    await client.query(
        `UPDATE user_positions
         SET
             scaled_atoken_balance = GREATEST(0, scaled_atoken_balance - $1),
             updated_at = NOW()
         WHERE user_id = $2 AND market_id = $3`,
        [collateralSeized.toString(), liquidatedUserId, collateralMarketId],
    );

    // Decrement the liquidated user's debt position
    await client.query(
        `UPDATE user_positions
         SET
             scaled_debt_balance = GREATEST(0, scaled_debt_balance - $1),
             updated_at = NOW()
         WHERE user_id = $2 AND market_id = $3`,
        [debtToCover.toString(), liquidatedUserId, debtMarketId],
    );

    // Recompute health factor for the liquidated user across all markets
    await updateHealthFactor(liquidatedUserId, client);
}
