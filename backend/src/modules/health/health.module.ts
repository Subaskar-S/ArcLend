import { Module } from '@nestjs/common';
import { HealthService } from './health.service';
import { HealthController } from './health.controller';
import { UserPositionRepository } from './user-position.repository';
import { UsersModule } from '../users/users.module';
import { PricesModule } from '../prices/prices.module';

@Module({
    imports: [
        UsersModule,
        PricesModule,
    ],
    controllers: [HealthController],
    providers: [HealthService, UserPositionRepository],
    exports: [HealthService],
})
export class HealthModule {}
