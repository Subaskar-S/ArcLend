import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Price } from './entities/price.entity';
import { Market } from '../markets/entities/market.entity';
import { CreatePriceDto } from './dto/create-price.dto';

@Injectable()
export class PricesService {
    constructor(
        @InjectRepository(Price)
        private readonly pricesRepository: Repository<Price>,
        @InjectRepository(Market)
        private readonly marketsRepository: Repository<Market>,
    ) {}

    /**
     * Record a new price observation for a market.
     * @param createPriceDto  Contains marketId (UUID), price (WAD string), timestamp
     */
    async create(createPriceDto: CreatePriceDto): Promise<Price> {
        const market = await this.marketsRepository.findOneBy({ id: createPriceDto.marketId });
        if (!market) {
            throw new NotFoundException(`Market ${createPriceDto.marketId} not found`);
        }

        const price = this.pricesRepository.create({
            market,
            price: createPriceDto.price,
            timestamp: new Date(createPriceDto.timestamp),
        });
        return this.pricesRepository.save(price);
    }

    /**
     * Returns the most recent price record for a given asset (by on-chain address).
     * Used by HealthService to value collateral and debt positions.
     *
     * @param assetAddress  Lowercase ERC20 contract address
     */
    async getLatestPrice(assetAddress: string): Promise<Price | null> {
        return this.pricesRepository
            .createQueryBuilder('p')
            .innerJoin('p.market', 'm')
            .where('m.asset_address = :address', { address: assetAddress.toLowerCase() })
            .orderBy('p.timestamp', 'DESC')
            .limit(1)
            .getOne();
    }

    /**
     * Returns all price records for a market, ordered newest first.
     * Useful for APY charts and historical data endpoints.
     *
     * @param marketId  UUID of the market
     */
    async getPriceHistory(marketId: string): Promise<Price[]> {
        return this.pricesRepository
            .createQueryBuilder('p')
            .innerJoin('p.market', 'm')
            .where('m.id = :marketId', { marketId })
            .orderBy('p.timestamp', 'DESC')
            .getMany();
    }
}
