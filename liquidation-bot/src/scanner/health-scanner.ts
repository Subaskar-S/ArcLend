import { Pool } from 'pg';
import { UnhealthyUser } from '../types';

const WAD = 1_000_000_000_000_000_000n; // 1e18

export class HealthScanner {
    constructor(private readonly db: Pool) {}

    /**
     * Returns users whose cached health_factor < 1.0 WAD.
     * Results are ordered by health_factor ASC (most critical first).
     *
     * Relies on the partial index:
     *   idx_user_positions_health ON user_positions(health_factor)
     *   WHERE health_factor < 1000000000000000000
     */
    async scanUnhealthyPositions(batchSize = 50): Promise<UnhealthyUser[]> {
        const res = await this.db.query<{
            user_id: string;
            user_address: string;
            health_factor: string;
        }>(
            `SELECT DISTINCT ON (up.user_id)
                up.user_id,
                u.address   AS user_address,
                up.health_factor
             FROM user_positions up
             JOIN users u ON u.id = up.user_id
             WHERE up.health_factor < $1
               AND up.health_factor > 0
             ORDER BY up.user_id, up.health_factor ASC
             LIMIT $2`,
            [WAD.toString(), batchSize],
        );

        return res.rows.map(r => ({
            userId: r.user_id,
            userAddress: r.user_address,
            healthFactor: r.health_factor,
        }));
    }
}
