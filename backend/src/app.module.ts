import { Module, ValidationPipe } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { APP_PIPE } from '@nestjs/core';
import { MarketsModule } from './modules/markets/markets.module';
import { UsersModule } from './modules/users/users.module';
import { DepositsModule } from './modules/deposits/deposits.module';
import { BorrowsModule } from './modules/borrows/borrows.module';
import { LiquidationsModule } from './modules/liquidations/liquidations.module';
import { PricesModule } from './modules/prices/prices.module';
import { HealthModule } from './modules/health/health.module';
import { RedisModule } from './infrastructure/redis/redis.module';
import { QueueModule } from './infrastructure/queue/queue.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
    }),
    TypeOrmModule.forRoot({
      type: 'postgres',
      host: process.env.DB_HOST || 'localhost',
      port: parseInt(process.env.DB_PORT || '5432'),
      username: process.env.DB_USER || 'postgres',
      password: process.env.DB_PASSWORD || 'postgres',
      database: process.env.DB_NAME || 'aave_lending',
      entities: [__dirname + '/**/*.entity{.ts,.js}'],
      synchronize: false, // Production: always false, use migrations
      logging: true,
    }),
    MarketsModule,
    UsersModule,
    DepositsModule,
    BorrowsModule,
    LiquidationsModule,
    PricesModule,
    HealthModule,
    RedisModule,
    QueueModule,
  ],
  controllers: [],
  providers: [
    {
      provide: APP_PIPE,
      useValue: new ValidationPipe({
        whitelist: true,
        transform: true,
        forbidNonWhitelisted: true,
      }),
    },
  ],
})
export class AppModule {}
