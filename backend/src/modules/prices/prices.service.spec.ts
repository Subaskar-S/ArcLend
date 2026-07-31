import { Test, TestingModule } from '@nestjs/testing';
import { NotFoundException } from '@nestjs/common';
import { getRepositoryToken } from '@nestjs/typeorm';
import { SelectQueryBuilder } from 'typeorm';
import { PricesService } from './prices.service';
import { Price } from './entities/price.entity';
import { Market } from '../markets/entities/market.entity';

// ─── Helpers ──────────────────────────────────────────────────────────────────

const MOCK_MARKET: Market = {
    id: 'market-uuid',
    assetAddress: '0xweth',
    symbol: 'WETH',
    decimals: 18,
    ltv: 7500,
    liquidationThreshold: 8000,
    liquidationBonus: 10500,
    reserveFactor: 1000,
    isActive: true,
    isFrozen: false,
    createdAt: new Date(),
    updatedAt: new Date(),
};

const MOCK_PRICE: Price = {
    id: 'price-uuid',
    market: MOCK_MARKET,
    price: '2000000000000000000000',
    timestamp: new Date(),
    createdAt: new Date(),
};

/** Build a mock QueryBuilder for getLatestPrice / getPriceHistory */
function mockQB(result: Price | Price[] | null) {
    const qb = {
        innerJoin: jest.fn().mockReturnThis(),
        where: jest.fn().mockReturnThis(),
        orderBy: jest.fn().mockReturnThis(),
        limit: jest.fn().mockReturnThis(),
        getOne: jest.fn().mockResolvedValue(Array.isArray(result) ? result[0] : result),
        getMany: jest.fn().mockResolvedValue(Array.isArray(result) ? result : []),
    } as unknown as SelectQueryBuilder<Price>;
    return qb;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('PricesService', () => {
    let service: PricesService;
    let priceRepo: { create: jest.Mock; save: jest.Mock; createQueryBuilder: jest.Mock };
    let marketRepo: { findOneBy: jest.Mock };

    beforeEach(async () => {
        priceRepo = {
            create: jest.fn().mockReturnValue(MOCK_PRICE),
            save: jest.fn().mockResolvedValue(MOCK_PRICE),
            createQueryBuilder: jest.fn(),
        };
        marketRepo = {
            findOneBy: jest.fn(),
        };

        const module: TestingModule = await Test.createTestingModule({
            providers: [
                PricesService,
                { provide: getRepositoryToken(Price), useValue: priceRepo },
                { provide: getRepositoryToken(Market), useValue: marketRepo },
            ],
        }).compile();

        service = module.get(PricesService);
    });

    describe('create', () => {
        it('throws NotFoundException when market does not exist', async () => {
            marketRepo.findOneBy.mockResolvedValue(null);
            await expect(
                service.create({ marketId: 'missing-uuid', price: '1000', timestamp: new Date().toISOString() }),
            ).rejects.toThrow(NotFoundException);
        });

        it('creates and saves a price record for a known market', async () => {
            marketRepo.findOneBy.mockResolvedValue(MOCK_MARKET);

            const result = await service.create({
                marketId: MOCK_MARKET.id,
                price: '2000000000000000000000',
                timestamp: new Date().toISOString(),
            });

            expect(priceRepo.create).toHaveBeenCalledWith(
                expect.objectContaining({ market: MOCK_MARKET, price: '2000000000000000000000' }),
            );
            expect(priceRepo.save).toHaveBeenCalled();
            expect(result).toEqual(MOCK_PRICE);
        });
    });

    describe('getLatestPrice', () => {
        it('returns the latest price for a known asset address', async () => {
            const qb = mockQB(MOCK_PRICE);
            priceRepo.createQueryBuilder.mockReturnValue(qb);

            const result = await service.getLatestPrice('0xweth');

            expect(result).toEqual(MOCK_PRICE);
            expect(qb.where).toHaveBeenCalledWith(
                'm.asset_address = :address',
                { address: '0xweth' },
            );
        });

        it('normalises asset address to lowercase', async () => {
            const qb = mockQB(MOCK_PRICE);
            priceRepo.createQueryBuilder.mockReturnValue(qb);

            await service.getLatestPrice('0xWETH');

            expect(qb.where).toHaveBeenCalledWith(
                'm.asset_address = :address',
                { address: '0xweth' },
            );
        });

        it('returns null when no price exists', async () => {
            const qb = mockQB(null);
            priceRepo.createQueryBuilder.mockReturnValue(qb);

            const result = await service.getLatestPrice('0xunknown');
            expect(result).toBeNull();
        });
    });

    describe('getPriceHistory', () => {
        it('returns all price records for a market', async () => {
            const qb = mockQB([MOCK_PRICE]);
            priceRepo.createQueryBuilder.mockReturnValue(qb);

            const result = await service.getPriceHistory(MOCK_MARKET.id);
            expect(result).toHaveLength(1);
            expect(result[0]).toEqual(MOCK_PRICE);
        });
    });
});
