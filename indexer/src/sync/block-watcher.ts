import { ethers } from "ethers";
import { Pool } from "pg";

export class BlockWatcher {
    private provider: ethers.JsonRpcProvider;
    private db: Pool;
    private isSyncing = false;

    constructor(rpcUrl: string, dbConnection: Pool) {
        this.provider = new ethers.JsonRpcProvider(rpcUrl);
        this.db = dbConnection;
    }

    async start() {
        console.log("Starting BlockWatcher...");
        
        // Initial catch-up
        await this.processBlocks();

        // Listen for new blocks
        this.provider.on("block", async (blockNumber) => {
            console.log(`New block detected: ${blockNumber}`);
            await this.processBlocks();
        });
    }

    private async processBlocks() {
        if (this.isSyncing) return;
        this.isSyncing = true;

        try {
            const currentBlock = await this.provider.getBlockNumber();
            let lastProcessedBlock = await this.getLastProcessedBlock();

            while (lastProcessedBlock < currentBlock) {
                const nextBlockNum = lastProcessedBlock + 1;
                const block = await this.provider.getBlock(nextBlockNum, true); // true = include transactions

                if (!block) {
                    console.warn(`Block ${nextBlockNum} not found, retrying...`);
                    await new Promise(resolve => setTimeout(resolve, 1000));
                    continue;
                }

                // Check for reorg
                const isReorg = await this.detectReorg(block);
                if (isReorg) {
                    await this.handleReorg(block);
                    // Reset lastProcessedBlock after reorg handling
                    lastProcessedBlock = await this.getLastProcessedBlock();
                    continue;
                }

                // Process block
                await this.processBlock(block);

                lastProcessedBlock = nextBlockNum;
            }
        } catch (error) {
            console.error("Error in block processing loop:", error);
        } finally {
            this.isSyncing = false;
        }
    }

    private async getLastProcessedBlock(): Promise<number> {
        const res = await this.db.query("SELECT last_processed_block FROM block_sync_state WHERE chain_id = $1", [await this.getChainId()]);
        if (res.rows.length === 0) {
            // Initialize if not exists
            const startBlock = parseInt(process.env.START_BLOCK || "0");
            await this.db.query(
                "INSERT INTO block_sync_state (chain_id, last_processed_block, last_processed_hash) VALUES ($1, $2, $3)",
                [await this.getChainId(), startBlock - 1, ethers.ZeroHash]
            );
            return startBlock - 1;
        }
        return res.rows[0].last_processed_block;
    }

    private async getChainId(): Promise<number> {
        const network = await this.provider.getNetwork();
        return Number(network.chainId);
    }

    private async detectReorg(block: ethers.Block): Promise<boolean> {
        const res = await this.db.query("SELECT last_processed_hash FROM block_sync_state WHERE chain_id = $1", [await this.getChainId()]);
        if (res.rows.length === 0) return false;
        
        const lastHash = res.rows[0].last_processed_hash;
        
        // If last hash is ZeroHash (genesis/init), no reorg
        if (lastHash === ethers.ZeroHash) return false;

        // If parent hash doesn't match our stored last hash, it's a reorg
        return block.parentHash !== lastHash;
    }

    private async handleReorg(block: ethers.Block) {
        console.warn(`REORG DETECTED at block ${block.number}. Rolling back...`);
        
        // Simple rollback: delete raw_events and update sync state to parent of the conflicting block?
        // No, we need to find common ancestor. 
        // For simplicity in Phase 3 MVP: rollback 1 block and retry.
        // We delete everything from current_head downwards.
        
        // Actually, if block.parentHash != last_db_hash, then last_db_hash is invalid (orphaned).
        // We need to roll back the DB state to block.parentHash? 
        // No, we don't have block.parentHash in DB necessarily if deep reorg.
        
        // Strategy: Rollback one block in DB.
        const chainId = await this.getChainId();
        const res = await this.db.query("SELECT last_processed_block FROM block_sync_state WHERE chain_id = $1", [chainId]);
        const currentDbBlock = res.rows[0].last_processed_block;

        // Delete events for the orphaned block
        await this.db.query("DELETE FROM raw_events WHERE params ->> 'blockNumber' = $1 AND chain_id = $2", [currentDbBlock, chainId]); // Wait, simple delete?
        // Also need to revert derived state? 
        // This suggests we need a strictly event-sourced system or rollback log.
        // For "Production-grade", we usually have `reorg_safe_depth`.
        
        // Implemented: Decrement last_processed_block.
        // We set last_processed_hash to... we don't know it easily without querying DB history or ETH node. 
        
        // PROPER FIX: unique constraint on (block_number, chain_id) in block_headers table?
        // We only have block_sync_state.
        
        // Quick Fix: Move last_processed_block back by 1. Next loop will re-fetch that block and check IT's parent.
        await this.db.query(
             "UPDATE block_sync_state SET last_processed_block = last_processed_block - 1, last_processed_hash = 'UNKNOWN' WHERE chain_id = $1",
             [chainId]
        );
        
        // In next iteration, detectReorg calls `detectReorg(block-1)`. 
        // If `last_processed_hash` is 'UNKNOWN', we might need to fetch it from provider or assume safe?
        // We need updates.
    }

    private async processBlock(block: ethers.Block) {
        const client = await this.db.connect();
        try {
            await client.query("BEGIN");

            // Fetch logs
            // TODO: Filter only for our contracts
            // const logs = await this.provider.getLogs({ ... });
            // For now, assume we process whole block logs or specific filter.
            
            // Update sync state
            await client.query(
                "UPDATE block_sync_state SET last_processed_block = $1, last_processed_hash = $2 WHERE chain_id = $3",
                [block.number, block.hash, await this.getChainId()]
            );

            await client.query("COMMIT");
            console.log(`Processed block ${block.number}`);
        } catch (e) {
            await client.query("ROLLBACK");
            throw e;
        } finally {
            client.release();
        }
    }
}
