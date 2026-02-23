import { Pool } from "pg";
import * as dotenv from "dotenv";
import { HealthScanner } from "./scanner/health-scanner";
import { LiquidationExecutor } from "./executor/liquidation-executor";

dotenv.config();

async function main() {
    // DB setup
    const db = new Pool({
        host: process.env.DB_HOST || "localhost",
        port: parseInt(process.env.DB_PORT || "5432"),
        user: process.env.DB_USER || "postgres",
        password: process.env.DB_PASSWORD || "postgres",
        database: process.env.DB_NAME || "aave_lending",
    });

    // Executor setup
    const executor = new LiquidationExecutor(
        process.env.REDIS_URL || "redis://localhost:6379",
        process.env.RPC_URL || "http://localhost:8545",
        process.env.PRIVATE_KEY || "", // Liquidator wallet key
        process.env.LENDING_POOL_ADDRESS || ""
    );

    const scanner = new HealthScanner(db);

    console.log("Starting Liquidation Bot...");

    // Main Loop
    while (true) {
        try {
            const unhealthyUsers = await scanner.scanUnhealthyPositions(50);
            
            if (unhealthyUsers.length > 0) {
                console.log(`Found ${unhealthyUsers.length} unhealthy positions.`);
                
                // Process in parallel
                await Promise.all(unhealthyUsers.map(async (user) => {
                    // Logic to determine WHICH debt/collateral to liquidate
                    // For now, assuming we query contract or DB to find max debt/collateral
                    // Simplified: pass placeholder or fetch details
                    
                    // In a real bot, we'd need to fetch the best pair.
                    // await executor.liquidate(user.user_address, ...);
                    console.log(`Would liquidate user ${user.user_address}`);
                }));
            }
        } catch (error) {
            console.error("Error in scan loop:", error);
        }

        // Sleep 5 seconds
        await new Promise(resolve => setTimeout(resolve, 5000));
    }
}

main();
