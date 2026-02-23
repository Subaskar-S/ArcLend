import { Controller, Get, Post, Body, Param, ParseUUIDPipe } from '@nestjs/common';
import { DepositsService } from './deposits.service';
import { CreateDepositDto } from './dto/create-deposit.dto';
import { Deposit } from './entities/deposit.entity';

@Controller('deposits')
export class DepositsController {
  constructor(private readonly depositsService: DepositsService) {}

  @Post()
  create(@Body() createDepositDto: CreateDepositDto): Promise<Deposit> {
    return this.depositsService.create(createDepositDto);
  }

  @Get('user/:userId')
  findAllByUserId(@Param('userId', ParseUUIDPipe) userId: string): Promise<Deposit[]> {
    return this.depositsService.findAllByUserId(userId);
  }
}
