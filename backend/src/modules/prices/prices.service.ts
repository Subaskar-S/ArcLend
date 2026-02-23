import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Price } from './entities/price.entity';
import { CreatePriceDto } from './dto/create-price.dto';

@Injectable()
export class PricesService {
  constructor(
    @InjectRepository(Price)
    private pricesRepository: Repository<Price>,
  ) {}

  async create(createPriceDto: CreatePriceDto): Promise<Price> {
    const price = this.pricesRepository.create({
      assetAddress: createPriceDto.assetAddress.toLowerCase(),
      timestamp: new Date(createPriceDto.timestamp),
      price: createPriceDto.price,
    });
    return this.pricesRepository.save(price);
  }

  async getLatestPrice(assetAddress: string): Promise<Price | null> {
    return this.pricesRepository.findOne({
      where: { assetAddress: assetAddress.toLowerCase() },
      order: { timestamp: 'DESC' },
    });
  }
}
