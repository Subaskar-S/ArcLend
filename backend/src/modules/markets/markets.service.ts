import { Injectable, ConflictException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Market } from './entities/market.entity';
import { CreateMarketDto } from './dto/create-market.dto';

@Injectable()
export class MarketsService {
  constructor(
    @InjectRepository(Market)
    private marketsRepository: Repository<Market>,
  ) {}

  async create(createMarketDto: CreateMarketDto): Promise<Market> {
    const existing = await this.marketsRepository.findOne({ 
      where: { assetAddress: createMarketDto.assetAddress } 
    });
    
    if (existing) {
      throw new ConflictException('Market with this asset address already exists');
    }

    const market = this.marketsRepository.create(createMarketDto);
    return this.marketsRepository.save(market);
  }

  async findAll(): Promise<Market[]> {
    return this.marketsRepository.find({
      order: { symbol: 'ASC' }
    });
  }

  async findOne(id: string): Promise<Market | null> {
    return this.marketsRepository.findOneBy({ id });
  }
}
