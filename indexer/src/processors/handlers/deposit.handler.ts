import { ethers } from "ethers";
import { PoolClient } from "pg";
import { upsertUser, resolveUserId, resolveMarketId } from "./helpers";
import { updateHealthFactor } from "../health-factor-updater";
import { createLogger } from "../../logger";

const logger = createLogger("deposit-handler");

/**
 * Handles the Deposit event emitted by LendingPoolFacet.
 *
 * event Deposit(
 *     address indexed reserve,
 *     address user,
 *     address indexed onBehalfOf,
 *     uint256 amount
 * )
 *
 * Writes to: users, deposits, user_positions (scaled_atoken_balance)
 */
export async function handleDeposit(
    parsed: ethers.LogDescription,
    log: ethers.Log,
    blockTimestamp: Date,
    client: PoolClient,
): Promise<void> {
    const reserve: string = (parsed.args.reserve as string).toLowerCase();
    const onBehalfOf: string = (parsed.args.onBehalfOf as string).toLowerCase();
    const depositor: string = (parsed.args.user as string).toLowerCase();
    const amount: bigint = parsed.args.amount as bigint;

    // Upsert both addresses — depositor and the recipient of aTokens
    await upsertUser(depositor, client);
    if (onBehalfOf !== depositor) {
        await upsertUser(onBehalfOf, client);
    }

    const userId = await resolveUserId(onBehalfOf, client);
    const marketId = await resolveMarketId(reserve, client);

    if (!marketId) {
        logger.warn(`Unknown market for asset ${reserve} — tx ${log.transactionHash}. Skipping.`);
        return;
    }

    // Append-only deposit history record
    await client.query(
        `INSERT INTO deposits (tx_hash, log_index, user_id, market_id, amount, on_behalf_of, timestamp)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (tx_hash, log_index) DO NOTHING`,
        [
            log.transactionHash,
            log.index,
            userId,
            marketId,
            amount.toString(),
            userId,             // on_behalf_of == onBehalfOf == the aToken recipient
            blockTimestamp,
        ],
    );

    // Upsert position — increment scaled_atoken_balance.
    // We store the raw nominal amount here. The health-factor updater job converts
    // nominal → scaled using the reserve's current liquidityIndex.
    await client.query(
        `INSERT INTO user_positions (user_id, market_id, scaled_atoken_balance, scaled_debt_balance)
         VALUES ($1, $2, $3, 0)
         ON CONFLICT (user_id, market_id)
         DO UPDATE SET
             scaled_atoken_balance = user_positions.scaled_atoken_balance + EXCLUDED.scaled_atoken_balance,
             updated_at = NOW()`,
        [userId, marketId, amount.toString()],
    );

    // Recompute health factor for this user across all markets
    await updateHealthFactor(userId, client);
}
