import { Pool } from "pg";
import * as dotenv from "dotenv";
import { BlockWatcher } from "./sync/block-watcher";

dotenv.config();

async function main() {
    const db = new Pool({
        host: process.env.DB_HOST || "localhost",
        port: parseInt(process.env.DB_PORT || "5432"),
        user: process.env.DB_USER || "postgres",
        password: process.env.DB_PASSWORD || "postgres",
        database: process.env.DB_NAME || "arc_lending",
    });

    const rpcUrl = process.env.RPC_URL || "http://localhost:8545";

    const watcher = new BlockWatcher(rpcUrl, db);

    // Handle graceful shutdown
    process.on("SIGINT", async () => {
        console.log("Shutting down...");
        await db.end();
        process.exit(0);
    });

    try {
        await watcher.start();
    } catch (error) {
        console.error("Fatal error:", error);
        process.exit(1);
    }
}

main();
