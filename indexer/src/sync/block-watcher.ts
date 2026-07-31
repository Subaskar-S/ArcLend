import { ethers } from "ethers";
import { Pool } from "pg";
import { EventProcessor } from "../processors/event-processor";
import { DIAMOND_ADDRESS } from "../config";

export class BlockWatcher {
    private readonly provider: ethers.JsonRpcProvider;
    private readonly db: Pool;
    private eventProcessor: EventProcessor;
    private chainId: number | null = null;
    private isSyncing = false;

    constructor(rpcUrl: string, dbConnection: Pool) {
        this.provider = new ethers.JsonRpcProvider(rpcUrl);
        this.db = dbConnection;
        // chainId is resolved lazily on first use; EventProcessor is re-created in start()
        this.eventProcessor = new EventProcessor(0);
    }

    async start(): Promise<void> {
        // Resolve chain ID once at startup, then rebuild EventProcessor with real chainId
        const resolvedChainId = await this.getChainId();
        this.eventProcessor = new EventProcessor(resolvedChainId);

        console.log(`[BlockWatcher] Starting on chainId=${resolvedChainId}, Diamond=${DIAMOND_ADDRESS || "ALL"}`);

        // Initial catch-up from last processed block to current head
        await this.processBlocks();

        // Subscribe to new blocks for live indexing
        this.provider.on("block", async (blockNumber: number) => {
            console.log(`[BlockWatcher] New block: ${blockNumber}`);
            await this.processBlocks();
        });
    }

    // ─── Main sync loop ───────────────────────────────────────────────────

    private async processBlocks(): Promise<void> {
        if (this.isSyncing) return;
        this.isSyncing = true;

        try {
            const currentBlock = await this.provider.getBlockNumber();
            let lastProcessedBlock = await this.getLastProcessedBlock();

            while (lastProcessedBlock < currentBlock) {
                const nextBlockNum = lastProcessedBlock + 1;
                const block = await this.provider.getBlock(nextBlockNum);

                if (!block) {
                    console.warn(`[BlockWatcher] Block ${nextBlockNum} not found — retrying in 1s`);
                    await this.sleep(1000);
                    continue;
                }

                const isReorg = await this.detectReorg(block);
                if (isReorg) {
                    await this.handleReorg(block);
                    // Reset cursor after rollback and re-evaluate from the new tip
                    lastProcessedBlock = await this.getLastProcessedBlock();
                    continue;
                }

                await this.processBlock(block);
                lastProcessedBlock = nextBlockNum;
            }
        } catch (error) {
            console.error("[BlockWatcher] Error in sync loop:", error);
        } finally {
            this.isSyncing = false;
        }
    }

    // ─── Per-block processing ─────────────────────────────────────────────

    private async processBlock(block: ethers.Block): Promise<void> {
        const chainId = await this.getChainId();
        const client = await this.db.connect();

        try {
            await client.query("BEGIN");

            // Fetch logs for the Diamond contract only (or all logs if address not configured)
            const filter: ethers.Filter = {
                fromBlock: block.number,
                toBlock: block.number,
                ...(DIAMOND_ADDRESS ? { address: DIAMOND_ADDRESS } : {}),
            };

            const logs = await this.provider.getLogs(filter);

            for (const log of logs) {
                await this.eventProcessor.processLog(log, block, client);
            }

            // Advance the sync cursor inside the same transaction
            await client.query(
                `UPDATE block_sync_state
                 SET last_processed_block = $1, last_processed_hash = $2, updated_at = NOW()
                 WHERE chain_id = $3`,
                [block.number, block.hash, chainId],
            );

            await client.query("COMMIT");

            if (logs.length > 0) {
                console.log(`[BlockWatcher] Block ${block.number}: processed ${logs.length} event(s)`);
            }
        } catch (e) {
            await client.query("ROLLBACK");
            throw e;
        } finally {
            client.release();
        }
    }

    // ─── Reorg handling ───────────────────────────────────────────────────

    private async detectReorg(block: ethers.Block): Promise<boolean> {
        const chainId = await this.getChainId();
        const res = await this.db.query<{ last_processed_hash: string }>(
            "SELECT last_processed_hash FROM block_sync_state WHERE chain_id = $1",
            [chainId],
        );

        if (res.rows.length === 0) return false;

        const lastHash = res.rows[0].last_processed_hash;

        // ZeroHash means we haven't processed any block yet — no reorg possible
        if (lastHash === ethers.ZeroHash || lastHash === "") return false;

        // If this block's parentHash doesn't match what we last stored, the chain forked
        return block.parentHash !== lastHash;
    }

    private async handleReorg(block: ethers.Block): Promise<void> {
        const chainId = await this.getChainId();

        console.warn(
            `[BlockWatcher] REORG detected at block ${block.number} on chain ${chainId}. Rolling back...`,
        );

        // Determine the last safe block (one before the divergence)
        const res = await this.db.query<{ last_processed_block: number }>(
            "SELECT last_processed_block FROM block_sync_state WHERE chain_id = $1",
            [chainId],
        );

        const currentDbBlock: number = res.rows[0]?.last_processed_block ?? -1;
        const rollbackToBlock = currentDbBlock - 1;

        // Fetch the real hash of the rollback target from the provider
        const safeBlock = rollbackToBlock >= 0
            ? await this.provider.getBlock(rollbackToBlock)
            : null;

        const safeHash = safeBlock?.hash ?? ethers.ZeroHash;

        const client = await this.db.connect();
        try {
            await client.query("BEGIN");

            // Roll back derived tables — delete everything from the orphaned block onwards
            await client.query(
                `DELETE FROM deposits
                 WHERE tx_hash IN (
                     SELECT tx_hash FROM raw_events
                     WHERE block_number > $1 AND chain_id = $2
                 )`,
                [rollbackToBlock, chainId],
            );

            await client.query(
                `DELETE FROM borrows
                 WHERE tx_hash IN (
                     SELECT tx_hash FROM raw_events
                     WHERE block_number > $1 AND chain_id = $2
                 )`,
                [rollbackToBlock, chainId],
            );

            await client.query(
                `DELETE FROM liquidations
                 WHERE tx_hash IN (
                     SELECT tx_hash FROM raw_events
                     WHERE block_number > $1 AND chain_id = $2
                 )`,
                [rollbackToBlock, chainId],
            );

            // Roll back raw events
            await client.query(
                "DELETE FROM raw_events WHERE block_number > $1 AND chain_id = $2",
                [rollbackToBlock, chainId],
            );

            // Reset sync cursor to the last safe block
            await client.query(
                `UPDATE block_sync_state
                 SET last_processed_block = $1, last_processed_hash = $2, updated_at = NOW()
                 WHERE chain_id = $3`,
                [rollbackToBlock, safeHash, chainId],
            );

            await client.query("COMMIT");

            console.warn(
                `[BlockWatcher] Rolled back to block ${rollbackToBlock} (hash: ${safeHash})`,
            );
        } catch (e) {
            await client.query("ROLLBACK");
            throw e;
        } finally {
            client.release();
        }
    }

    // ─── Sync state helpers ───────────────────────────────────────────────

    private async getLastProcessedBlock(): Promise<number> {
        const chainId = await this.getChainId();
        const res = await this.db.query<{ last_processed_block: number }>(
            "SELECT last_processed_block FROM block_sync_state WHERE chain_id = $1",
            [chainId],
        );

        if (res.rows.length === 0) {
            const startBlock = parseInt(process.env.START_BLOCK || "0", 10);
            await this.db.query(
                `INSERT INTO block_sync_state (chain_id, last_processed_block, last_processed_hash)
                 VALUES ($1, $2, $3)`,
                [chainId, startBlock - 1, ethers.ZeroHash],
            );
            return startBlock - 1;
        }

        return res.rows[0].last_processed_block;
    }

    private async getChainId(): Promise<number> {
        if (this.chainId === null) {
            const network = await this.provider.getNetwork();
            this.chainId = Number(network.chainId);
        }
        return this.chainId;
    }

    // ─── Utilities ────────────────────────────────────────────────────────

    private sleep(ms: number): Promise<void> {
        return new Promise(resolve => setTimeout(resolve, ms));
    }
}
