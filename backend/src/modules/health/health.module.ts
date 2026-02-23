import { Module } from '@nestjs/common';
import { HealthService } from './health.service';
import { HealthController } from './health.controller';
import { UsersModule } from '../users/users.module';
import { DepositsModule } from '../deposits/deposits.module';
import { BorrowsModule } from '../borrows/borrows.module';
import { PricesModule } from '../prices/prices.module';

@Module({
  imports: [UsersModule, DepositsModule, BorrowsModule, PricesModule],
  controllers: [HealthController],
  providers: [HealthService],
  exports: [HealthService],
})
export class HealthModule {}
