import { Injectable, Inject } from '@nestjs/common';
import Redis from 'ioredis';

@Injectable()
export class RedisService {
  constructor(@Inject('REDIS_CLIENT') private readonly redis: Redis) {}

  async set(key: string, value: string, ttlSeconds?: number): Promise<void> {
    if (ttlSeconds) {
      await this.redis.set(key, value, 'EX', ttlSeconds);
    } else {
      await this.redis.set(key, value);
    }
  }

  async get(key: string): Promise<string | null> {
    return this.redis.get(key);
  }

  async del(key: string): Promise<void> {
    await this.redis.del(key);
  }

  // Rate limiting specific
  async incrementAndExpire(key: string, ttlSeconds: number): Promise<number> {
    const multi = this.redis.multi();
    multi.incr(key);
    multi.expire(key, ttlSeconds, 'NX'); // 'NX' only set expire if it has no expiry
    const results = await multi.exec();
    if (!results || results.length === 0) return 0;
    return results[0][1] as number;
  }
}
