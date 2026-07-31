import { Test, TestingModule } from '@nestjs/testing';
import { NotFoundException } from '@nestjs/common';
import { HealthService } from './health.service';
import { UsersService } from '../users/users.service';
import { PricesService } from '../prices/prices.service';
import { UserPositionRepository } from './user-position.repository';
import { WAD } from '../../shared/utils/wad-ray-math';

// ─── Test fixtures ────────────────────────────────────────────────────────────

const MOCK_USER = { id: 'user-uuid', address: '0xabc' };

const WETH_ADDRESS = '0xweth';
const USDC_ADDRESS = '0xusdc';

// ETH price: $2000 in WAD  →  2000 * 1e18
const ETH_PRICE = (2000n * WAD).toString();
// USDC price: $1 in WAD
const USDC_PRICE = WAD.toString();

// Market params (mirrors real reserves)
// WETH: decimals=18, liquidationThreshold=8000bps (80%)
// USDC: decimals=6,  liquidationThreshold=8500bps (85%)
const WETH_POSITION = {
    marketId: 'mkt-weth',
    assetAddress: WETH_ADDRESS,
    decimals: 18,
    liquidationThreshold: 8000,
    scaledATokenBalance: WAD,       // 1 WETH deposited
    scaledDebtBalance: 0n,
};

const USDC_BORROW_POSITION = {
    marketId: 'mkt-usdc',
    assetAddress: USDC_ADDRESS,
    decimals: 6,
    liquidationThreshold: 8500,
    scaledATokenBalance: 0n,
    scaledDebtBalance: 1_000_000n,  // 1 USDC borrowed (6 decimals)
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

function mockUsersService(user: typeof MOCK_USER | null) {
    return { findOne: jest.fn().mockResolvedValue(user) };
}

function mockPricesService(priceMap: Record<string, string>) {
    return {
        getLatestPrice: jest.fn().mockImplementation((address: string) => {
            const price = priceMap[address];
            return Promise.resolve(price ? { price } : null);
        }),
    };
}

function mockPositionRepo(positions: typeof WETH_POSITION[]) {
    return { findPositionsByUserId: jest.fn().mockResolvedValue(positions) };
}

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('HealthService', () => {
    let service: HealthService;
    let usersService: jest.Mocked<UsersService>;
    let pricesService: jest.Mocked<PricesService>;
    let positionRepo: jest.Mocked<UserPositionRepository>;

    async function buildModule(
        user: typeof MOCK_USER | null,
        positions: typeof WETH_POSITION[],
        prices: Record<string, string>,
    ) {
        const module: TestingModule = await Test.createTestingModule({
            providers: [
                HealthService,
                { provide: UsersService, useValue: mockUsersService(user) },
                { provide: PricesService, useValue: mockPricesService(prices) },
                { provide: UserPositionRepository, useValue: mockPositionRepo(positions) },
            ],
        }).compile();

        service = module.get(HealthService);
        usersService = module.get(UsersService) as jest.Mocked<UsersService>;
        pricesService = module.get(PricesService) as jest.Mocked<PricesService>;
        positionRepo = module.get(UserPositionRepository) as jest.Mocked<UserPositionRepository>;
    }

    it('should be defined', async () => {
        await buildModule(MOCK_USER, [], {});
        expect(service).toBeDefined();
    });

    describe('calculateHealthFactor', () => {
        it('throws NotFoundException when user does not exist', async () => {
            await buildModule(null, [], {});
            await expect(service.calculateHealthFactor('missing-uuid'))
                .rejects.toThrow(NotFoundException);
        });

        it('returns 1 WAD with zero totals when user has no positions', async () => {
            await buildModule(MOCK_USER, [], {});
            const result = await service.calculateHealthFactor('user-uuid');

            expect(result.totalCollateralBase).toBe('0');
            expect(result.totalDebtBase).toBe('0');
            expect(result.isCollateralized).toBe(true);
            expect(BigInt(result.healthFactor)).toBeGreaterThanOrEqual(WAD);
        });

        it('returns high sentinel HF when collateral exists but no debt', async () => {
            await buildModule(
                MOCK_USER,
                [WETH_POSITION],
                { [WETH_ADDRESS]: ETH_PRICE },
            );
            const result = await service.calculateHealthFactor('user-uuid');

            expect(result.totalDebtBase).toBe('0');
            expect(result.isCollateralized).toBe(true);
            // sentinel value: 1000 WAD
            expect(BigInt(result.healthFactor)).toBe(WAD * 1000n);
        });

        it('computes correct HF for a healthy position', async () => {
            // Setup:
            //   Collateral: 1 WETH @ $2000, liquidationThreshold = 80%
            //   Debt:       1 USDC @ $1
            //
            // liquidationScore = 2000e18 * 8000 / 10000 = 1600e18
            // totalDebtBase    = 1e18  (1 USDC normalised from 6 dec → WAD × $1 price)
            // healthFactor     = 1600e18 / 1e18 = 1600 WAD  →  very healthy
            await buildModule(
                MOCK_USER,
                [WETH_POSITION, USDC_BORROW_POSITION],
                { [WETH_ADDRESS]: ETH_PRICE, [USDC_ADDRESS]: USDC_PRICE },
            );
            const result = await service.calculateHealthFactor('user-uuid');

            expect(result.isCollateralized).toBe(true);
            // HF should be approximately 1600 WAD
            const hf = BigInt(result.healthFactor);
            expect(hf).toBeGreaterThan(1000n * WAD);
        });

        it('returns HF < 1 WAD for an underwater position', async () => {
            // Setup:
            //   Collateral: 1 USDC @ $1, liquidationThreshold = 85%
            //   Debt:       1 WETH @ $2000  →  much larger than collateral
            //
            // liquidationScore = 1e18 * 8500 / 10000 = 0.85e18
            // totalDebtBase    = 2000e18
            // healthFactor     = 0.85e18 / 2000e18  →  << 1
            const collateral = { ...USDC_BORROW_POSITION, scaledATokenBalance: 1_000_000n, scaledDebtBalance: 0n };
            const debt = { ...WETH_POSITION, scaledATokenBalance: 0n, scaledDebtBalance: WAD };

            await buildModule(
                MOCK_USER,
                [collateral, debt],
                { [USDC_ADDRESS]: USDC_PRICE, [WETH_ADDRESS]: ETH_PRICE },
            );
            const result = await service.calculateHealthFactor('user-uuid');

            expect(result.isCollateralized).toBe(false);
            expect(BigInt(result.healthFactor)).toBeLessThan(WAD);
        });

        it('skips markets where no price is available', async () => {
            // One position but price fetch returns null — should not throw, HF = sentinel
            await buildModule(
                MOCK_USER,
                [WETH_POSITION],
                {}, // no prices
            );
            const result = await service.calculateHealthFactor('user-uuid');

            expect(result.totalCollateralBase).toBe('0');
            expect(result.totalDebtBase).toBe('0');
            expect(result.isCollateralized).toBe(true);
        });
    });
});
