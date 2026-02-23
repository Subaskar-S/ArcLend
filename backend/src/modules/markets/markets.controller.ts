import { Controller, Get, Post, Body, Param, ParseUUIDPipe } from '@nestjs/common';
import { MarketsService } from './markets.service';
import { CreateMarketDto } from './dto/create-market.dto';
import { Market } from './entities/market.entity';

@Controller('markets')
export class MarketsController {
  constructor(private readonly marketsService: MarketsService) {}

  @Post()
  create(@Body() createMarketDto: CreateMarketDto): Promise<Market> {
    return this.marketsService.create(createMarketDto);
  }

  @Get()
  findAll(): Promise<Market[]> {
    return this.marketsService.findAll();
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string): Promise<Market | null> {
    return this.marketsService.findOne(id);
  }
}
