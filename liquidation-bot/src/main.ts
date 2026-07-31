import * as dotenv from 'dotenv';
import { Pool } from 'pg';
import { HealthScanner } from './scanner/health-scanner';
import { BestPairSelector } from './scanner/best-pair.selector';
import { LiquidationExecutor } from './executor/liquidation-executor';
import { logger } from './logger';

dotenv.config();

const SCAN_INTERVAL_MS = 5_000;
const BATCH_SIZE = 50;

async function main(): Promise<void> {
    // ── Validate required env vars ────────────────────────────────────────────
    const privateKey = process.env.PRIVATE_KEY;
    const lendingPoolAddress = process.env.LENDING_POOL_ADDRESS;

    if (!privateKey) {
        logger.error('PRIVATE_KEY env var is required');
        process.exit(1);
    }
    if (!lendingPoolAddress) {
        logger.error('LENDING_POOL_ADDRESS env var is required');
        process.exit(1);
    }

    // ── DB connection ─────────────────────────────────────────────────────────
    const db = new Pool({
        host: process.env.DB_HOST || 'localhost',
        port: parseInt(process.env.DB_PORT || '5432', 10),
        user: process.env.DB_USER || 'postgres',
        password: process.env.DB_PASSWORD || 'postgres',
        database: process.env.DB_NAME || 'aave_lending',
    });

    const rpcUrl = process.env.RPC_URL || 'http://localhost:8545';
    const redisUrl = process.env.REDIS_URL || 'redis://localhost:6379';

    // ── Service wiring ────────────────────────────────────────────────────────
    const scanner = new HealthScanner(db);
    const pairSelector = new BestPairSelector(db);
    const executor = new LiquidationExecutor(redisUrl, rpcUrl, privateKey, lendingPoolAddress);

    // ── Graceful shutdown ─────────────────────────────────────────────────────
    let running = true;

    const shutdown = async () => {
        logger.info('Shutting down...');
        running = false;
        await db.end();
        process.exit(0);
    };

    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);

    // ── Main loop ─────────────────────────────────────────────────────────────
    logger.info('Liquidation bot started');
    logger.info(`Pool address: ${lendingPoolAddress}`);
    logger.info(`Scan interval: ${SCAN_INTERVAL_MS}ms`);

    while (running) {
        try {
            const unhealthyUsers = await scanner.scanUnhealthyPositions(BATCH_SIZE);

            if (unhealthyUsers.length === 0) {
                logger.debug('No unhealthy positions found');
            } else {
                logger.info(`Found ${unhealthyUsers.length} unhealthy position(s)`);

                // Process each user sequentially to avoid nonce conflicts on the wallet
                for (const user of unhealthyUsers) {
                    if (!running) break;

                    logger.info(`Processing ${user.userAddress} — HF: ${user.healthFactor}`);

                    // Select the best debt/collateral pair for this user
                    const pair = await pairSelector.selectPair(user.userAddress);

                    if (!pair) {
                        logger.warn(`No valid liquidation pair found for ${user.userAddress} — skipping`);
                        continue;
                    }

                    // Execute — errors are caught inside the executor, never throws here
                    await executor.liquidate(
                        pair.userAddress,
                        pair.debtAsset,
                        pair.collateralAsset,
                        pair.debtToCover,
                    );
                }
            }
        } catch (error) {
            logger.error('Scan loop error', { error });
        }

        // Wait before next scan cycle
        await new Promise(resolve => setTimeout(resolve, SCAN_INTERVAL_MS));
    }
}

main();
