import { ethers } from "ethers";
import { Pool, PoolClient } from "pg";

export class EventProcessor {
    private db: Pool;

    constructor(dbConnection: Pool) {
        this.db = dbConnection;
    }

    async processLog(log: ethers.Log, client: PoolClient) {
        // Idempotency check: INSERT ON CONFLICT DO NOTHING
        // We insert into raw_events first.
        const { transactionHash, index: logIndex, blockNumber, blockHash } = log;
        
        const chainId = 31337; // Hardcoded for local dev, should come from config

        // 1. Insert Raw Event
        const insertRes = await client.query(
            `INSERT INTO raw_events 
            (chain_id, block_number, block_hash, parent_hash, tx_hash, log_index, event_name, data, processed)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            ON CONFLICT (tx_hash, log_index) DO NOTHING
            RETURNING id`,
            [
                chainId,
                blockNumber,
                blockHash,
                "UNKNOWN", // Parent hash not in Log object, need to fetch block or pass it down
                transactionHash,
                logIndex,
                "UNKNOWN_YET", // Need to parse
                JSON.stringify(log),
                false
            ]
        );

        if (insertRes.rowCount === 0) {
            console.log(`Event ${transactionHash}-${logIndex} already known.`);
            return; // Already processed
        }

        // 2. Parse and Process (Business Logic)
        // Here we would use the contract interface to parse the log.
        // For this file, I'll outline the structure.
        // await this.routeEvent(log, client);
        
        // Mark as processed
        await client.query("UPDATE raw_events SET processed = TRUE WHERE tx_hash = $1 AND log_index = $2", [transactionHash, logIndex]);
    }

    // Example routing logic (placeholder)
    async routeEvent(parsedLog: ethers.LogDescription, client: PoolClient) {
        switch (parsedLog.name) {
            case "Deposit":
                // await this.handleDeposit(parsedLog, client);
                break;
            case "Borrow":
                 // await this.handleBorrow(parsedLog, client);
                 break;
            // ...
        }
    }
}
