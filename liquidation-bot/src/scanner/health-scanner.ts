import { Pool } from "pg";

export class HealthScanner {
    private db: Pool;

    constructor(dbConnection: Pool) {
        this.db = dbConnection;
    }

    /**
     * @notice Scans user positions for health factor < 1.0 (1e18)
     * @returns Array of user IDs and their details
     */
    async scanUnhealthyPositions(batchSize: number = 50): Promise<any[]> {
        // Query: JOIN users if we need wallet address
        const query = `
            SELECT 
                up.user_id,
                u.address as user_address,
                up.market_id,
                up.health_factor
            FROM user_positions up
            JOIN users u ON up.user_id = u.id
            WHERE up.health_factor < 1000000000000000000 -- 1e18
            AND up.health_factor > 0 -- 0 often means empty position, depending on logic
            LIMIT $1
        `;
        
        const res = await this.db.query(query, [batchSize]);
        return res.rows;
    }
}
