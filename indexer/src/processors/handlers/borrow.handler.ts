import { ethers } from "ethers";
import { PoolClient } from "pg";
import { upsertUser, resolveUserId, resolveMarketId } from "./helpers";

/**
 * Handles the Borrow event emitted by BorrowFacet.
 *
 * event Borrow(
 *     address indexed reserve,
 *     address user,
 *     address indexed onBehalfOf,
 *     uint256 amount,
 *     uint256 borrowRate
 * )
 *
 * Writes to: users, borrows, user_positions (increments scaled_debt_balance)
 */
export async function handleBorrow(
    parsed: ethers.LogDescription,
    log: ethers.Log,
    blockTimestamp: Date,
    client: PoolClient,
): Promise<void> {
    const reserve: string = (parsed.args.reserve as string).toLowerCase();
    const onBehalfOf: string = (parsed.args.onBehalfOf as string).toLowerCase();
    const caller: string = (parsed.args.user as string).toLowerCase();
    const amount: bigint = parsed.args.amount as bigint;
    const borrowRate: bigint = parsed.args.borrowRate as bigint;

    await upsertUser(caller, client);
    if (onBehalfOf !== caller) {
        await upsertUser(onBehalfOf, client);
    }

    const userId = await resolveUserId(onBehalfOf, client);
    const marketId = await resolveMarketId(reserve, client);

    if (!marketId) {
        console.warn(`[handleBorrow] Unknown market for asset ${reserve} — tx ${log.transactionHash}. Skipping.`);
        return;
    }

    // Append-only borrow history record
    await client.query(
        `INSERT INTO borrows (tx_hash, log_index, user_id, market_id, amount, borrow_rate, timestamp)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (tx_hash, log_index) DO NOTHING`,
        [
            log.transactionHash,
            log.index,
            userId,
            marketId,
            amount.toString(),
            borrowRate.toString(),
            blockTimestamp,
        ],
    );

    // Upsert position — increment scaled_debt_balance
    await client.query(
        `INSERT INTO user_positions (user_id, market_id, scaled_atoken_balance, scaled_debt_balance)
         VALUES ($1, $2, 0, $3)
         ON CONFLICT (user_id, market_id)
         DO UPDATE SET
             scaled_debt_balance = user_positions.scaled_debt_balance + EXCLUDED.scaled_debt_balance,
             updated_at = NOW()`,
        [userId, marketId, amount.toString()],
    );
}
