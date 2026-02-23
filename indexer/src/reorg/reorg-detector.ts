import { Pool } from "pg";
import { ethers } from "ethers";

export class ReorgDetector {
    constructor(private db: Pool) {}

    /**
     * Checks if a newly fetched block represents a chain reorganization.
     * @param block The newly fetched block
     * @param chainId The network ID
     * @returns true if a reorg is detected
     */
    async isReorg(block: ethers.Block, chainId: number): Promise<boolean> {
        const res = await this.db.query(
            "SELECT last_processed_hash FROM block_sync_state WHERE chain_id = $1", 
            [chainId]
        );
        
        if (res.rows.length === 0) return false;
        
        const lastHash = res.rows[0].last_processed_hash;
        
        if (lastHash === ethers.ZeroHash) return false;

        return block.parentHash !== lastHash;
    }

    /**
     * Handles the rollback logic when a reorg is detected.
     */
    async handleRollback(chainId: number) {
        // Decrement sync cursor to re-evaluate the previous block
        await this.db.query(
            "UPDATE block_sync_state SET last_processed_block = last_processed_block - 1, last_processed_hash = 'UNKNOWN' WHERE chain_id = $1",
            [chainId]
        );
        console.warn(`Chain reorg detected on chain ${chainId}. Sync cursor rolled back.`);
    }
}
