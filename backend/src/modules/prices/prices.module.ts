import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { PricesService } from './prices.service';
import { PricesController } from './prices.controller';
import { Price } from './entities/price.entity';
import { Market } from '../markets/entities/market.entity';
import { QueueModule } from '../../infrastructure/queue/queue.module';

@Module({
    imports: [
        TypeOrmModule.forFeature([Price, Market]),
        QueueModule,
    ],
    controllers: [PricesController],
    providers: [PricesService],
    exports: [PricesService],
})
export class PricesModule {}
