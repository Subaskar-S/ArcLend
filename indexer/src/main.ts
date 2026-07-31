import * as dotenv from "dotenv";
import { dbPool } from "./database/db";
import { BlockWatcher } from "./sync/block-watcher";

dotenv.config();

async function main(): Promise<void> {
    const rpcUrl = process.env.RPC_URL || "http://localhost:8545";

    const watcher = new BlockWatcher(rpcUrl, dbPool);

    process.on("SIGINT", async () => {
        console.log("[main] Shutting down...");
        await dbPool.end();
        process.exit(0);
    });

    process.on("SIGTERM", async () => {
        console.log("[main] SIGTERM received. Shutting down...");
        await dbPool.end();
        process.exit(0);
    });

    try {
        await watcher.start();
    } catch (error) {
        console.error("[main] Fatal error:", error);
        await dbPool.end();
        process.exit(1);
    }
}

main();
