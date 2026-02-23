import { Test, TestingModule } from '@nestjs/testing';
import { HealthService } from './health.service';
import { UsersService } from '../users/users.service';
import { DepositsService } from '../deposits/deposits.service';
import { BorrowsService } from '../borrows/borrows.service';
import { PricesService } from '../prices/prices.service';

describe('HealthService', () => {
  let service: HealthService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        HealthService,
        { provide: UsersService, useValue: { findOne: jest.fn().mockResolvedValue({}) } },
        { provide: DepositsService, useValue: { findAllByUserId: jest.fn().mockResolvedValue([]) } },
        { provide: BorrowsService, useValue: { findAllByUserId: jest.fn().mockResolvedValue([]) } },
        { provide: PricesService, useValue: {} },
      ],
    }).compile();

    service = module.get(HealthService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  describe('calculateHealthFactor', () => {
    it('should return a default health factor', async () => {
      const hf = await service.calculateHealthFactor('some-uuid');
      expect(hf).toEqual('1500000000000000000');
    });
  });
});
