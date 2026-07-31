import { Controller, Get, Param, ParseUUIDPipe } from '@nestjs/common';
import { HealthService, HealthFactorResult } from './health.service';

@Controller('health')
export class HealthController {
    constructor(private readonly healthService: HealthService) {}

    /**
     * Returns the current health factor and position summary for a user.
     *
     * GET /api/v1/health/user/:userId
     *
     * Response:
     *   userId              — the queried user UUID
     *   healthFactor        — WAD-scaled string (1e18 = 1.0; below 1e18 = liquidatable)
     *   totalCollateralBase — total collateral value in base currency (WAD string)
     *   totalDebtBase       — total debt value in base currency (WAD string)
     *   isCollateralized    — true if HF >= 1.0
     */
    @Get('user/:userId')
    async getUserHealthFactor(
        @Param('userId', ParseUUIDPipe) userId: string,
    ): Promise<{ userId: string } & HealthFactorResult> {
        const result = await this.healthService.calculateHealthFactor(userId);
        return { userId, ...result };
    }
}
