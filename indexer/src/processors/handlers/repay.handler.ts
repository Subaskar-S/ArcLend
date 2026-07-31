import { ethers } from "ethers";
import { PoolClient } from "pg";
import { upsertUser, resolveUserId, resolveMarketId } from "./helpers";

/**
 * Handles the Repay event emitted by BorrowFacet.
 *
 * event Repay(
 *     address indexed reserve,
 *     address indexed user,
 *     address indexed repayer,
 *     uint256 amount
 * )
 *
 * Writes to: users, repayments, user_positions (decrements scaled_debt_balance)
 */
export async function handleRepay(
    parsed: ethers.LogDescription,
    log: ethers.Log,
    blockTimestamp: Date,
    client: PoolClient,
): Promise<void> {
    const reserve: string = (parsed.args.reserve as string).toLowerCase();
    const user: string = (parsed.args.user as string).toLowerCase();
    const repayer: string = (parsed.args.repayer as string).toLowerCase();
    const amount: bigint = parsed.args.amount as bigint;

    await upsertUser(user, client);
    if (repayer !== user) {
        await upsertUser(repayer, client);
    }

    const userId = await resolveUserId(user, client);
    const marketId = await resolveMarketId(reserve, client);

    if (!marketId) {
        console.warn(`[handleRepay] Unknown market for asset ${reserve} — tx ${log.transactionHash}. Skipping.`);
        return;
    }

    // Append-only repayment history record.
    // Note: repayments table must be added via migration 002.
    await client.query(
        `INSERT INTO repayments (tx_hash, log_index, user_id, market_id, repayer_id, amount, timestamp)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (tx_hash, log_index) DO NOTHING`,
        [
            log.transactionHash,
            log.index,
            userId,
            marketId,
            await resolveUserId(repayer, client),
            amount.toString(),
            blockTimestamp,
        ],
    ).catch((err: unknown) => {
        if (err instanceof Error && (err as Error & { code?: string }).code === "42P01") {
            console.warn("[handleRepay] repayments table does not exist. Run migration 002.");
        } else {
            throw err;
        }
    });

    // Decrement scaled_debt_balance — clamp at 0
    await client.query(
        `UPDATE user_positions
         SET
             scaled_debt_balance = GREATEST(0, scaled_debt_balance - $1),
             updated_at = NOW()
         WHERE user_id = $2 AND market_id = $3`,
        [amount.toString(), userId, marketId],
    );
}
