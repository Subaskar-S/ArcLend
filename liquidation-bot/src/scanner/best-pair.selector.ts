import { Pool } from 'pg';
import { LiquidationPair, PositionMarket } from '../types';

const WAD = 10n ** 18n;
const CLOSE_FACTOR_BPS = 5000n;   // 50% — matches LIQUIDATION_CLOSE_FACTOR_PERCENT in LiquidationFacet.sol
const BPS = 10_000n;

/**
 * Selects the optimal debt/collateral pair to liquidate for a given user.
 *
 * Strategy:
 *   - Debt asset:       the market with the highest total debt value (in base currency)
 *   - Collateral asset: the market with the highest collateral value × liquidation bonus
 *
 * This maximises the liquidator's profit while staying within the 50% close factor.
 *
 * Prices are read from the latest entry in the `prices` table per market.
 */
export class BestPairSelector {
    constructor(private readonly db: Pool) {}

    async selectPair(userAddress: string): Promise<LiquidationPair | null> {
        // Load all positions for this user joined with market config and latest price
        const rows = await this.db.query<{
            market_id: string;
            asset_address: string;
            decimals: string;
            liquidation_bonus: string;
            scaled_atoken_balance: string;
            scaled_debt_balance: string;
            latest_price: string | null;
        }>(
            `SELECT
                up.market_id,
                m.asset_address,
                m.decimals,
                m.liquidation_bonus,
                up.scaled_atoken_balance,
                up.scaled_debt_balance,
                p.price AS latest_price
             FROM user_positions up
             JOIN users u ON u.id = up.user_id
             JOIN markets m ON m.id = up.market_id
             LEFT JOIN LATERAL (
                 SELECT price
                 FROM prices
                 WHERE market_id = up.market_id
                 ORDER BY timestamp DESC
                 LIMIT 1
             ) p ON true
             WHERE u.address = $1
               AND m.is_active = true`,
            [userAddress.toLowerCase()],
        );

        if (rows.rowCount === 0) return null;

        // Parse rows into typed PositionMarket entries, skipping markets with no price
        const positions: PositionMarket[] = rows.rows
            .filter(r => r.latest_price !== null)
            .map(r => ({
                marketId: r.market_id,
                assetAddress: r.asset_address,
                decimals: parseInt(r.decimals, 10),
                liquidationBonus: parseInt(r.liquidation_bonus, 10),
                scaledATokenBalance: BigInt(r.scaled_atoken_balance ?? '0'),
                scaledDebtBalance: BigInt(r.scaled_debt_balance ?? '0'),
                latestPrice: BigInt(r.latest_price!),
            }));

        // ── Find the highest-value debt market ────────────────────────────────
        const debtMarket = positions
            .filter(p => p.scaledDebtBalance > 0n)
            .reduce<PositionMarket | null>((best, p) => {
                const value = this.toBaseValue(p.scaledDebtBalance, p.decimals, p.latestPrice);
                const bestValue = best
                    ? this.toBaseValue(best.scaledDebtBalance, best.decimals, best.latestPrice)
                    : 0n;
                return value > bestValue ? p : best;
            }, null);

        if (!debtMarket) return null;  // user has no active debt — nothing to liquidate

        // ── Find the highest-value collateral market ──────────────────────────
        const collateralMarket = positions
            .filter(p => p.scaledATokenBalance > 0n && p.assetAddress !== debtMarket.assetAddress)
            .reduce<PositionMarket | null>((best, p) => {
                // Weight collateral value by liquidation bonus so we maximise profit
                const value = this.toBaseValue(p.scaledATokenBalance, p.decimals, p.latestPrice)
                    * BigInt(p.liquidationBonus) / BPS;
                const bestValue = best
                    ? this.toBaseValue(best.scaledATokenBalance, best.decimals, best.latestPrice)
                        * BigInt(best.liquidationBonus) / BPS
                    : 0n;
                return value > bestValue ? p : best;
            }, null);

        if (!collateralMarket) return null;  // no collateral to seize

        // ── Apply 50% close factor to debtToCover ────────────────────────────
        const totalDebt = debtMarket.scaledDebtBalance;
        const debtToCover = totalDebt * CLOSE_FACTOR_BPS / BPS;

        return {
            userAddress,
            debtAsset: debtMarket.assetAddress,
            collateralAsset: collateralMarket.assetAddress,
            debtToCover: debtToCover.toString(),
        };
    }

    /** Convert a raw token balance to WAD-denominated base currency value */
    private toBaseValue(balance: bigint, decimals: number, priceWad: bigint): bigint {
        // Normalise to WAD
        const balanceWad = decimals < 18
            ? balance * 10n ** BigInt(18 - decimals)
            : decimals > 18
                ? balance / 10n ** BigInt(decimals - 18)
                : balance;

        // value = balanceWad * priceWad / WAD
        return balanceWad * priceWad / WAD;
    }
}
