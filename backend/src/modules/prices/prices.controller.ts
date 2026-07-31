import { Controller, Get, Post, Body, Param, ParseUUIDPipe } from '@nestjs/common';
import { PricesService } from './prices.service';
import { CreatePriceDto } from './dto/create-price.dto';
import { Price } from './entities/price.entity';

@Controller('prices')
export class PricesController {
    constructor(private readonly pricesService: PricesService) {}

    /**
     * POST /api/v1/prices
     * Record a new price observation for a market.
     * Body: { marketId, price, timestamp }
     */
    @Post()
    create(@Body() createPriceDto: CreatePriceDto): Promise<Price> {
        return this.pricesService.create(createPriceDto);
    }

    /**
     * GET /api/v1/prices/latest/:assetAddress
     * Returns the most recent price for an asset by its on-chain address.
     */
    @Get('latest/:assetAddress')
    getLatestPrice(@Param('assetAddress') assetAddress: string): Promise<Price | null> {
        return this.pricesService.getLatestPrice(assetAddress);
    }

    /**
     * GET /api/v1/prices/history/:marketId
     * Returns all price records for a market, newest first.
     */
    @Get('history/:marketId')
    getPriceHistory(@Param('marketId', ParseUUIDPipe) marketId: string): Promise<Price[]> {
        return this.pricesService.getPriceHistory(marketId);
    }
}
