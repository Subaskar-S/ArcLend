import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Liquidation } from './entities/liquidation.entity';
import { CreateLiquidationDto } from './dto/create-liquidation.dto';
import { UsersService } from '../users/users.service';
import { MarketsService } from '../markets/markets.service';

@Injectable()
export class LiquidationsService {
  constructor(
    @InjectRepository(Liquidation)
    private liquidationsRepository: Repository<Liquidation>,
    private usersService: UsersService,
    private marketsService: MarketsService,
  ) {}

  async create(createLiquidationDto: CreateLiquidationDto): Promise<Liquidation> {
    const liquidatedUser = await this.usersService.findOne(createLiquidationDto.liquidatedUserId);
    if (!liquidatedUser) throw new NotFoundException('Liquidated User not found');

    const collateralMarket = await this.marketsService.findOne(createLiquidationDto.collateralMarketId);
    if (!collateralMarket) throw new NotFoundException('Collateral Market not found');

    const debtMarket = await this.marketsService.findOne(createLiquidationDto.debtMarketId);
    if (!debtMarket) throw new NotFoundException('Debt Market not found');

    const liquidation = this.liquidationsRepository.create({
      txHash: createLiquidationDto.txHash,
      logIndex: createLiquidationDto.logIndex,
      collateralMarket,
      debtMarket,
      liquidatedUser,
      liquidatorAddress: createLiquidationDto.liquidatorAddress,
      debtToCover: createLiquidationDto.debtToCover,
      collateralSeized: createLiquidationDto.collateralSeized,
      timestamp: new Date(createLiquidationDto.timestamp),
    });

    return this.liquidationsRepository.save(liquidation);
  }

  async findAllByUserId(userId: string): Promise<Liquidation[]> {
    return this.liquidationsRepository.find({
      where: { liquidatedUser: { id: userId } },
      relations: ['collateralMarket', 'debtMarket'],
      order: { timestamp: 'DESC' },
    });
  }
}
