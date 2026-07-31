import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job } from 'bullmq';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';
import { HEALTH_FACTOR_QUEUE, HealthFactorJobData } from './health-factor-job.types';

const WAD = 10n ** 18n;
const BPS = 10_000n;

/**
 * BullMQ processor for the 'health-factor-updates' queue.
 *
 * Triggered when a new price is recorded for a market (via POST /api/v1/prices).
 * Recomputes user_positions.health_factor for every user that holds a position
 * in the affected market using the same BigInt WAD formula as the indexer.
 *
 * This ensures health factors stay current after a price change even when
 * no on-chain position event fires.
 */
@Processor(HEALTH_FACTOR_QUEUE)
export class HealthFactorProcessor extends WorkerHost {
    private readonly logger = new Logger(HealthFactorProcessor.name);

    constructor(
        @InjectDataSource()
        private readonly dataSource: DataSource,
    ) {
        super();
    }

    async process(job: Job<HealthFactorJobData>): Promise<void> {
        const { marketId, newPrice } = job.data;
        this.logger.log(`Processing HF update for market ${marketId} — new price: ${newPrice}`);

        // 1. Find all users with a non-zero position in this market
        const affectedUsers = await this.dataSource.query<{ user_id: string }[]>(
            `SELECT DISTINCT user_id
             FROM user_positions
             WHERE market_id = $1
               AND (scaled_atoken_balance > 0 OR scaled_debt_balance > 0)`,
            [marketId],
        );

        if (!affectedUsers.length) {
            this.logger.debug(`No active positions found for market ${marketId} — skipping`);
            return;
        }

        this.logger.log(`Recomputing HF for ${affectedUsers.length} user(s)`);
        let updated = 0;

        for (const { user_id } of affectedUsers) {
            try {
                await this.recomputeHealthFactor(user_id);
                updated++;
            } catch (err) {
                // Log and continue — one user failure should not block others
                this.logger.error(`Failed to recompute HF for user ${user_id}:`, err);
            }
        }

        this.logger.log(`HF update complete: ${updated}/${affectedUsers.length} users updated`);
    }

    /**
     * Recomputes and writes health_factor for all market positions of a given user.
     * Mirrors the formula in indexer/src/processors/health-factor-updater.ts.
     */
    private async recomputeHealthFactor(userId: string): Promise<void> {
        const rows = await this.dataSource.query<{
            decimals: string;
            liquidation_threshold: string;
            scaled_atoken_balance: string;
            scaled_debt_balance: string;
            latest_price: string | null;
        }[]>(
            `SELECT
                 m.decimals,
                 m.liquidation_threshold,
                 up.scaled_atoken_balance,
                 up.scaled_debt_balance,
                 p.price AS latest_price
             FROM user_positions up
             JOIN markets m ON m.id = up.market_id
             LEFT JOIN LATERAL (
                 SELECT price
                 FROM prices pr
                 JOIN markets pm ON pm.id = pr.market_id
                 WHERE pm.id = up.market_id
                 ORDER BY pr.timestamp DESC
                 LIMIT 1
             ) p ON true
             WHERE up.user_id = $1
               AND m.is_active = true`,
            [userId],
        );

        if (!rows.length) return;

        let liquidationScore = 0n;
        let totalDebtBase = 0n;

        for (const r of rows) {
            if (r.latest_price === null) continue;

            const price = BigInt(r.latest_price);
            const decimals = parseInt(r.decimals, 10);
            const liquidationThreshold = BigInt(r.liquidation_threshold);
            const aTokenBal = BigInt(r.scaled_atoken_balance ?? '0');
            const debtBal = BigInt(r.scaled_debt_balance ?? '0');

            const collateralWad = toWad(aTokenBal, decimals);
            const debtWad = toWad(debtBal, decimals);

            const collateralValue = collateralWad * price / WAD;
            const debtValue = debtWad * price / WAD;

            liquidationScore += collateralValue * liquidationThreshold / BPS;
            totalDebtBase += debtValue;
        }

        const healthFactor = totalDebtBase === 0n
            ? 1000n * WAD
            : liquidationScore * WAD / totalDebtBase;

        await this.dataSource.query(
            `UPDATE user_positions SET health_factor = $1, updated_at = NOW() WHERE user_id = $2`,
            [healthFactor.toString(), userId],
        );
    }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function toWad(amount: bigint, decimals: number): bigint {
    if (decimals === 18) return amount;
    if (decimals < 18) return amount * 10n ** BigInt(18 - decimals);
    return amount / 10n ** BigInt(decimals - 18);
}
