import { ethers } from "ethers";
import { PoolClient } from "pg";
import { DIAMOND_INTERFACE } from "../config";
import { handleDeposit } from "./handlers/deposit.handler";
import { handleWithdraw } from "./handlers/withdraw.handler";
import { handleBorrow } from "./handlers/borrow.handler";
import { handleRepay } from "./handlers/repay.handler";
import { handleLiquidation } from "./handlers/liquidation.handler";
import { handleReserveInitialized, handleReserveConfigured } from "./handlers/reserve-initialized.handler";

export class EventProcessor {
    private readonly chainId: number;
    private readonly provider: ethers.JsonRpcProvider;

    constructor(chainId: number, provider: ethers.JsonRpcProvider) {
        this.chainId = chainId;
        this.provider = provider;
    }

    /**
     * Processes a single on-chain log within an active DB transaction.
     *
     * Steps:
     *  1. Insert into raw_events (idempotent — ON CONFLICT DO NOTHING)
     *  2. Parse the log using the Diamond ABI
     *  3. Route to the correct handler
     *  4. Mark raw_events row as processed
     *
     * @param log       The raw ethers Log object
     * @param block     The block that contains this log (for parentHash + timestamp)
     * @param client    An active pg PoolClient inside a BEGIN/COMMIT transaction
     */
    async processLog(
        log: ethers.Log,
        block: ethers.Block,
        client: PoolClient,
    ): Promise<void> {
        const blockTimestamp = new Date(block.timestamp * 1000);

        // ── Step 1: Insert raw event (idempotent) ────────────────────────
        const insertRes = await client.query<{ id: string }>(
            `INSERT INTO raw_events
                 (chain_id, block_number, block_hash, parent_hash, tx_hash, log_index,
                  event_name, data, processed)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false)
             ON CONFLICT (tx_hash, log_index) DO NOTHING
             RETURNING id`,
            [
                this.chainId,
                block.number,
                block.hash,
                block.parentHash,
                log.transactionHash,
                log.index,
                "UNKNOWN",                  // updated below after parsing
                JSON.stringify(log),
            ],
        );

        // rowCount === 0 means this log was already processed in a previous run
        if (insertRes.rowCount === 0) {
            return;
        }

        // ── Step 2: Parse the log ────────────────────────────────────────
        let parsed: ethers.LogDescription;
        try {
            const result = DIAMOND_INTERFACE.parseLog({
                topics: [...log.topics],
                data: log.data,
            });
            if (!result) {
                await this.markProcessed(log, client);
                return;
            }
            parsed = result;
        } catch {
            // Event signature not in our ABI — a different contract or unknown event
            console.debug(
                `[EventProcessor] Unrecognised event in tx ${log.transactionHash} log ${log.index} — skipping.`,
            );
            await this.markProcessed(log, client);
            return;
        }

        // ── Step 3: Update event_name now that we've parsed it ───────────
        await client.query(
            "UPDATE raw_events SET event_name = $1 WHERE tx_hash = $2 AND log_index = $3",
            [parsed.name, log.transactionHash, log.index],
        );

        // ── Step 4: Route to handler ─────────────────────────────────────
        await this.routeEvent(parsed, log, block, blockTimestamp, client);

        // ── Step 5: Mark as processed ────────────────────────────────────
        await this.markProcessed(log, client);
    }

    private async routeEvent(
        parsed: ethers.LogDescription,
        log: ethers.Log,
        block: ethers.Block,
        blockTimestamp: Date,
        client: PoolClient,
    ): Promise<void> {
        switch (parsed.name) {
            case "Deposit":
                await handleDeposit(parsed, log, blockTimestamp, client);
                break;

            case "Withdraw":
                await handleWithdraw(parsed, log, blockTimestamp, client);
                break;

            case "Borrow":
                await handleBorrow(parsed, log, blockTimestamp, client);
                break;

            case "Repay":
                await handleRepay(parsed, log, blockTimestamp, client);
                break;

            case "LiquidationCall":
                await handleLiquidation(parsed, log, blockTimestamp, client);
                break;

            case "ReserveInitialized":
                await handleReserveInitialized(parsed, log, client, this.provider);
                break;

            case "ReserveConfigured":
                await handleReserveConfigured(parsed, log, client);
                break;

            // These events are informational — no DB writes needed
            case "ReserveFrozen":
            case "ReserveActive":
            case "Paused":
            case "Unpaused":
            case "OracleUpdated":
            case "RoleGranted":
            case "RoleRevoked":
                console.log(`[EventProcessor] Config event "${parsed.name}" recorded — tx ${log.transactionHash}`);
                break;

            default:
                console.warn(`[EventProcessor] No handler for event "${parsed.name}" — tx ${log.transactionHash}`);
        }
    }

    private async markProcessed(log: ethers.Log, client: PoolClient): Promise<void> {
        await client.query(
            "UPDATE raw_events SET processed = true WHERE tx_hash = $1 AND log_index = $2",
            [log.transactionHash, log.index],
        );
    }
}
