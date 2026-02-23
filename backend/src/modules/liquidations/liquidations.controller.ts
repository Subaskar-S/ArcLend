import { Controller, Get, Post, Body, Param, ParseUUIDPipe } from '@nestjs/common';
import { LiquidationsService } from './liquidations.service';
import { CreateLiquidationDto } from './dto/create-liquidation.dto';
import { Liquidation } from './entities/liquidation.entity';

@Controller('liquidations')
export class LiquidationsController {
  constructor(private readonly liquidationsService: LiquidationsService) {}

  @Post()
  create(@Body() createLiquidationDto: CreateLiquidationDto): Promise<Liquidation> {
    return this.liquidationsService.create(createLiquidationDto);
  }

  @Get('user/:userId')
  findAllByUserId(@Param('userId', ParseUUIDPipe) userId: string): Promise<Liquidation[]> {
    return this.liquidationsService.findAllByUserId(userId);
  }
}
