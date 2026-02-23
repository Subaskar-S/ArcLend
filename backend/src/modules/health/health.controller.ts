import { Controller, Get, Param, ParseUUIDPipe } from '@nestjs/common';
import { HealthService } from './health.service';

@Controller('health')
export class HealthController {
  constructor(private readonly healthService: HealthService) {}

  @Get('user/:userId')
  async getUserHealthFactor(@Param('userId', ParseUUIDPipe) userId: string) {
    const healthFactor = await this.healthService.calculateHealthFactor(userId);
    return {
      userId,
      healthFactor,
      isCollateralized: BigInt(healthFactor) >= BigInt('1000000000000000000')
    };
  }
}
