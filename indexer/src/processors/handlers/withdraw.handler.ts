import { ethers } from "ethers";
import { PoolClient } from "pg";
import { upsertUser, resolveUserId, resolveMarketId } from "./helpers";

/**
 * Handles the Withdraw event emitted by LendingPoolFacet.
 *
 * event Withdraw(
 *     address indexed reserve,
 *     address indexed user,
 *     address indexed to,
 *     uint256 amount
 * )
 *
 * Writes to: users, withdrawals, user_positions (decrements scaled_atoken_balance)
 */
export async function handleWithdraw(
    parsed: ethers.LogDescription,
    log: ethers.Log,
    blockTimestamp: Date,
    client: PoolClient,
): Promise<void> {
    const reserve: string = (parsed.args.reserve as string).toLowerCase();
    const user: string = (parsed.args.user as string).toLowerCase();
    const amount: bigint = parsed.args.amount as bigint;

    await upsertUser(user, client);

    const userId = await resolveUserId(user, client);
    const marketId = await resolveMarketId(reserve, client);

    if (!marketId) {
        console.warn(`[handleWithdraw] Unknown market for asset ${reserve} — tx ${log.transactionHash}. Skipping.`);
        return;
    }

    // Append-only withdrawal history record.
    // Note: withdrawals table must be added via migration 002.
    // Guarded with DO NOTHING in case the table doesn't exist yet.
    await client.query(
        `INSERT INTO withdrawals (tx_hash, log_index, user_id, market_id, to_address, amount, timestamp)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (tx_hash, log_index) DO NOTHING`,
        [
            log.transactionHash,
            log.index,
            userId,
            marketId,
            (parsed.args.to as string).toLowerCase(),
            amount.toString(),
            blockTimestamp,
        ],
    ).catch((err: unknown) => {
        // If the withdrawals table doesn't exist yet, log a warning and continue.
        // Run migration 002 to add it.
        if (err instanceof Error && (err as Error & { code?: string }).code === "42P01") {
            console.warn("[handleWithdraw] withdrawals table does not exist. Run migration 002.");
        } else {
            throw err;
        }
    });

    // Decrement scaled_atoken_balance — clamp at 0 to avoid negative values
    await client.query(
        `UPDATE user_positions
         SET
             scaled_atoken_balance = GREATEST(0, scaled_atoken_balance - $1),
             updated_at = NOW()
         WHERE user_id = $2 AND market_id = $3`,
        [amount.toString(), userId, marketId],
    );
}
