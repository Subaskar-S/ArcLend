import { ethers } from "ethers";
import Redis from "ioredis";

export class LiquidationExecutor {
    private redis: Redis;
    private provider: ethers.JsonRpcProvider;
    private wallet: ethers.Wallet;

    constructor(
        redisUrl: string,
        rpcUrl: string,
        privateKey: string,
        private lendingPoolAddress: string
    ) {
        this.redis = new Redis(redisUrl);
        this.provider = new ethers.JsonRpcProvider(rpcUrl);
        this.wallet = new ethers.Wallet(privateKey, this.provider);
    }

    async liquidate(userAddress: string, debtAsset: string, collateralAsset: string, debtToCover: string) {
        const lockKey = `lock:liq:${userAddress}`;
        
        // 1. Acquire distributed lock (TTL 30s)
        const acquired = await this.acquireLock(lockKey, 30000);
        if (!acquired) {
            console.log(`Lock busy for user ${userAddress}`);
            return;
        }

        try {
            console.log(`Attempting liquidation for ${userAddress}`);

            // 2. Simulate via eth_call (optional but recommended)
            // await this.simulate(...) 

            // 3. Execute Transaction
            const contract = new ethers.Contract(
                this.lendingPoolAddress, 
                [ "function liquidationCall(address,address,address,uint256)" ],
                this.wallet
            );

            // Note: In production, we need to approve the LendingPool to spend the liquidator's debtAsset tokens first!
            // Assuming liquidator has infinite approval or approves JIT.

            const tx = await contract.liquidationCall(
                collateralAsset,
                debtAsset,
                userAddress,
                debtToCover
            );
            
            console.log(`Liquidation TX sent: ${tx.hash}`);
            await tx.wait();
            console.log(`Liquidation confirmed: ${tx.hash}`);

        } catch (error) {
            console.error(`Liquidation failed for ${userAddress}:`, error);
        } finally {
            // 4. Release lock?
            // Usually we keep the lock until TTL or explicitly release.
            // Explicit release allows faster retry if partial fail, but TTL is safer against crash.
            await this.redis.del(lockKey);
        }
    }

    private async acquireLock(key: string, ttlMs: number): Promise<boolean> {
        // SET key value NX PX ttl
        const res = await this.redis.set(key, "LOCKED", "NX", "PX", ttlMs);
        return res === "OK";
    }
}
