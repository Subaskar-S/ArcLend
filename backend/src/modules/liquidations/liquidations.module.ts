import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { LiquidationsService } from './liquidations.service';
import { LiquidationsController } from './liquidations.controller';
import { Liquidation } from './entities/liquidation.entity';
import { UsersModule } from '../users/users.module';
import { MarketsModule } from '../markets/markets.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Liquidation]),
    UsersModule,
    MarketsModule,
  ],
  controllers: [LiquidationsController],
  providers: [LiquidationsService],
  exports: [LiquidationsService],
})
export class LiquidationsModule {}
