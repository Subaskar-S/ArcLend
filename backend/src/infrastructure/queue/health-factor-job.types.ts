/**
 * Job payload for the 'health-factor-updates' BullMQ queue.
 *
 * Enqueued by PricesService.create() whenever a new price is recorded
 * for a market. The worker recomputes health_factor for every user
 * that holds a position in that market.
 */
export const HEALTH_FACTOR_QUEUE = 'health-factor-updates';

export interface HealthFactorJobData {
    /** UUID of the market whose price just changed */
    marketId: string;
    /** The new WAD price string (for logging only — worker re-fetches latest) */
    newPrice: string;
}
