import Redis from "ioredis";

export class RedisLockService {
    private redis: Redis;

    constructor(redisUrl: string) {
        this.redis = new Redis(redisUrl);
    }

    /**
     * Attempts to acquire a distributed lock.
     * @param resource Specific resource key to lock (e.g. user address)
     * @param ttlMs Time to live in milliseconds
     * @returns true if lock was acquired, false if it is busy
     */
    async acquire(resource: string, ttlMs: number = 30000): Promise<boolean> {
        const key = `lock:${resource}`;
        // NX = Only set if not exists, PX = Milliseconds TTL
        const res = await this.redis.set(key, "LOCKED", "NX", "PX", ttlMs);
        return res === "OK";
    }

    /**
     * Releases a previously acquired lock.
     * @param resource The resource key
     */
    async release(resource: string): Promise<void> {
        const key = `lock:${resource}`;
        await this.redis.del(key);
    }
}
