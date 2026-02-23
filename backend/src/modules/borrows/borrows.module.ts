import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { BorrowsService } from './borrows.service';
import { BorrowsController } from './borrows.controller';
import { Borrow } from './entities/borrow.entity';
import { UsersModule } from '../users/users.module';
import { MarketsModule } from '../markets/markets.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Borrow]),
    UsersModule,
    MarketsModule,
  ],
  controllers: [BorrowsController],
  providers: [BorrowsService],
  exports: [BorrowsService],
})
export class BorrowsModule {}
