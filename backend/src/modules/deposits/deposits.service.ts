import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Deposit } from './entities/deposit.entity';
import { CreateDepositDto } from './dto/create-deposit.dto';
import { UsersService } from '../users/users.service';
import { MarketsService } from '../markets/markets.service';

@Injectable()
export class DepositsService {
  constructor(
    @InjectRepository(Deposit)
    private depositsRepository: Repository<Deposit>,
    private usersService: UsersService,
    private marketsService: MarketsService,
  ) {}

  async create(createDepositDto: CreateDepositDto): Promise<Deposit> {
    const user = await this.usersService.findOne(createDepositDto.userId);
    if (!user) throw new NotFoundException('User not found');

    const market = await this.marketsService.findOne(createDepositDto.marketId);
    if (!market) throw new NotFoundException('Market not found');

    let onBehalfOfUser = null;
    if (createDepositDto.onBehalfOf) {
      onBehalfOfUser = await this.usersService.findOne(createDepositDto.onBehalfOf);
      if (!onBehalfOfUser) throw new NotFoundException('onBehalfOf user not found');
    }

    const deposit = this.depositsRepository.create({
      txHash: createDepositDto.txHash,
      logIndex: createDepositDto.logIndex,
      user,
      market,
      amount: createDepositDto.amount,
      onBehalfOf: onBehalfOfUser,
      timestamp: new Date(createDepositDto.timestamp),
    });

    return this.depositsRepository.save(deposit);
  }

  async findAllByUserId(userId: string): Promise<Deposit[]> {
    return this.depositsRepository.find({
      where: { user: { id: userId } },
      relations: ['market'],
      order: { timestamp: 'DESC' },
    });
  }
}
