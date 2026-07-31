import { PoolClient } from "pg";

/**
 * WAD / BPS constants — mirrors WadRayMath.sol and PercentageMath.sol.
 * Kept local to avoid a cross-package dependency on the backend utility.
 */
const WAD = 10n ** 18n;
const BPS = 10_000n;

interface PositionRow {
    marketId: string;
    decimals: number;
    liquidationThreshold: bigint;   // basis points
    scaledATokenBalance: bigint;
    scaledDebtBalance: bigint;
    latestPrice: bigint | null;     // WAD (1e18) — null if no price record exists
}

/**
 * Recomputes health_factor for every market position of a given user and
 * writes it back to user_positions inside the caller's open transaction.
 *
 * Formula (mirrors GenericLogic.calculateUserHealthFactor):
 *
 *   collateralValueBase_i = toWad(scaledATokenBalance_i) × price_i  / WAD
 *   debtValueBase_i       = toWad(scaledDebtBalance_i)   × price_i  / WAD
 *   liquidationScore      = Σ collateralValueBase_i × liquidationThreshold_i / BPS
 *   totalDebtBase         = Σ debtValueBase_i
 *   healthFactor          = liquidationScore × WAD / totalDebtBase
 *
 * Health factor is stored as a WAD (1e18) integer in user_positions.health_factor.
 * A value below 1e18 means the position is liquidatable.
 *
 * If totalDebtBase = 0 the user has no debt — health factor is set to a
 * large sentinel (1000 WAD) so it never accidentally triggers liquidation scans.
 *
 * @param userId  The UUID of the user whose HF should be recomputed.
 * @param client  An active PoolClient inside a BEGIN/COMMIT transaction.
 */
export async function updateHealthFactor(userId: string, client: PoolClient): Promise<void> {
    // ── 1. Fetch all active positions + latest price per market ──────────────
    const rows = await client.query<{
        market_id: string;
        decimals: string;
        liquidation_threshold: string;
        scaled_atoken_balance: string;
        scaled_debt_balance: string;
        latest_price: string | null;
    }>(
        `SELECT
             up.market_id,
             m.decimals,
             m.liquidation_threshold,
             up.scaled_atoken_balance,
             up.scaled_debt_balance,
             p.price AS latest_price
         FROM user_positions up
         JOIN markets m ON m.id = up.market_id
         LEFT JOIN LATERAL (
             SELECT price
             FROM prices
             WHERE market_id = up.market_id
             ORDER BY timestamp DESC
             LIMIT 1
         ) p ON true
         WHERE up.user_id = $1
           AND m.is_active = true`,
        [userId],
    );

    if (rows.rowCount === 0) return;

    // ── 2. Parse into typed structs ───────────────────────────────────────────
    const positions: PositionRow[] = rows.rows.map(r => ({
        marketId: r.market_id,
        decimals: parseInt(r.decimals, 10),
        liquidationThreshold: BigInt(r.liquidation_threshold),
        scaledATokenBalance: BigInt(r.scaled_atoken_balance ?? "0"),
        scaledDebtBalance: BigInt(r.scaled_debt_balance ?? "0"),
        latestPrice: r.latest_price !== null ? BigInt(r.latest_price) : null,
    }));

    // ── 3. Accumulate totals ──────────────────────────────────────────────────
    let liquidationScore = 0n;   // Σ collateralValue × liquidationThreshold
    let totalDebtBase = 0n;      // Σ debtValue

    for (const pos of positions) {
        if (pos.latestPrice === null) continue; // no price → skip market

        const price = pos.latestPrice;
        const collateralWad = toWad(pos.scaledATokenBalance, pos.decimals);
        const debtWad = toWad(pos.scaledDebtBalance, pos.decimals);

        // value = balance (WAD) × price (WAD) / WAD  →  WAD
        const collateralValue = collateralWad * price / WAD;
        const debtValue = debtWad * price / WAD;

        // weighted collateral by liquidation threshold (basis points)
        liquidationScore += collateralValue * pos.liquidationThreshold / BPS;
        totalDebtBase += debtValue;
    }

    // ── 4. Compute health factor ──────────────────────────────────────────────
    let healthFactor: bigint;
    if (totalDebtBase === 0n) {
        healthFactor = 1000n * WAD; // sentinel — no debt, no liquidation risk
    } else {
        // HF = liquidationScore (WAD) × WAD / totalDebtBase (WAD) = WAD
        healthFactor = liquidationScore * WAD / totalDebtBase;
    }

    // ── 5. Upsert health_factor for ALL market rows of this user ─────────────
    // We write the same aggregate HF to every user_positions row for this user.
    // The liquidation bot scans with "WHERE health_factor < 1e18" so any row
    // being updated is sufficient for detection.
    await client.query(
        `UPDATE user_positions
         SET health_factor = $1, updated_at = NOW()
         WHERE user_id = $2`,
        [healthFactor.toString(), userId],
    );
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/** Normalise a raw token amount to 18-decimal WAD representation */
function toWad(amount: bigint, decimals: number): bigint {
    if (decimals === 18) return amount;
    if (decimals < 18) return amount * 10n ** BigInt(18 - decimals);
    return amount / 10n ** BigInt(decimals - 18);
}
