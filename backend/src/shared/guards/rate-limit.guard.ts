import { Injectable, CanActivate, ExecutionContext, HttpException, HttpStatus } from '@nestjs/common';
import { RedisService } from '../../infrastructure/redis/redis.service';

@Injectable()
export class RateLimitGuard implements CanActivate {
  private readonly RATE_LIMIT = 60; // Max requests
  private readonly WINDOW_SECONDS = 60; // Per 60 seconds

  constructor(private redisService: RedisService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest();
    const ip = req.ip || req.connection.remoteAddress;
    const endpoint = req.url.split('?')[0];

    const key = `rl:${ip}:${endpoint}`;
    
    // Increment counter and set expiry if it's new
    const count = await this.redisService.incrementAndExpire(key, this.WINDOW_SECONDS);

    if (count > this.RATE_LIMIT) {
      throw new HttpException('Too Many Requests', HttpStatus.TOO_MANY_REQUESTS);
    }

    return true;
  }
}
