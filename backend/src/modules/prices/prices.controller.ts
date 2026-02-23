import { Controller, Get, Post, Body, Param } from '@nestjs/common';
import { PricesService } from './prices.service';
import { CreatePriceDto } from './dto/create-price.dto';
import { Price } from './entities/price.entity';

@Controller('prices')
export class PricesController {
  constructor(private readonly pricesService: PricesService) {}

  @Post()
  create(@Body() createPriceDto: CreatePriceDto): Promise<Price> {
    return this.pricesService.create(createPriceDto);
  }

  @Get('latest/:assetAddress')
  getLatestPrice(@Param('assetAddress') assetAddress: string): Promise<Price | null> {
    return this.pricesService.getLatestPrice(assetAddress);
  }
}
