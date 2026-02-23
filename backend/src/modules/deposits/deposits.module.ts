import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { DepositsService } from './deposits.service';
import { DepositsController } from './deposits.controller';
import { Deposit } from './entities/deposit.entity';
import { UsersModule } from '../users/users.module';
import { MarketsModule } from '../markets/markets.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Deposit]),
    UsersModule,
    MarketsModule,
  ],
  controllers: [DepositsController],
  providers: [DepositsService],
  exports: [DepositsService],
})
export class DepositsModule {}
