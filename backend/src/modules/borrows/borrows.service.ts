import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Borrow } from './entities/borrow.entity';
import { CreateBorrowDto } from './dto/create-borrow.dto';
import { UsersService } from '../users/users.service';
import { MarketsService } from '../markets/markets.service';

@Injectable()
export class BorrowsService {
  constructor(
    @InjectRepository(Borrow)
    private borrowsRepository: Repository<Borrow>,
    private usersService: UsersService,
    private marketsService: MarketsService,
  ) {}

  async create(createBorrowDto: CreateBorrowDto): Promise<Borrow> {
    const user = await this.usersService.findOne(createBorrowDto.userId);
    if (!user) throw new NotFoundException('User not found');

    const market = await this.marketsService.findOne(createBorrowDto.marketId);
    if (!market) throw new NotFoundException('Market not found');

    const borrow = this.borrowsRepository.create({
      txHash: createBorrowDto.txHash,
      logIndex: createBorrowDto.logIndex,
      user,
      market,
      amount: createBorrowDto.amount,
      borrowRate: createBorrowDto.borrowRate,
      timestamp: new Date(createBorrowDto.timestamp),
    });

    return this.borrowsRepository.save(borrow);
  }

  async findAllByUserId(userId: string): Promise<Borrow[]> {
    return this.borrowsRepository.find({
      where: { user: { id: userId } },
      relations: ['market'],
      order: { timestamp: 'DESC' },
    });
  }
}
