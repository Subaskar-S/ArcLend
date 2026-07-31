import * as dotenv from "dotenv";
import { dbPool } from "./database/db";
import { BlockWatcher } from "./sync/block-watcher";
import { logger } from "./logger";

dotenv.config();

async function main(): Promise<void> {
    const rpcUrl = process.env.RPC_URL || "http://localhost:8545";

    const watcher = new BlockWatcher(rpcUrl, dbPool);

    process.on("SIGINT", async () => {
        logger.info("Shutting down...");
        await dbPool.end();
        process.exit(0);
    });

    process.on("SIGTERM", async () => {
        logger.info("SIGTERM received. Shutting down...");
        await dbPool.end();
        process.exit(0);
    });

    try {
        await watcher.start();
    } catch (error) {
        logger.error("Fatal error", { error });
        await dbPool.end();
        process.exit(1);
    }
}

main();
