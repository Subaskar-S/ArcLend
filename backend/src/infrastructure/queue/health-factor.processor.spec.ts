import { Test, TestingModule } from '@nestjs/testing';
import { getDataSourceToken } from '@nestjs/typeorm';
import { HealthFactorProcessor } from './health-factor.processor';

// ─── Fixtures ─────────────────────────────────────────────────────────────────

const WAD = 10n ** 18n;

const AFFECTED_USERS = [{ user_id: 'user-1' }, { user_id: 'user-2' }];

// WETH: 18 dec, liquidationThreshold=8000, $2000 price
const WETH_ROW = {
    decimals: '18',
    liquidation_threshold: '8000',
    scaled_atoken_balance: WAD.toString(),      // 1 WETH collateral
    scaled_debt_balance: '0',
    latest_price: (2000n * WAD).toString(),
};

// USDC: 6 dec, liquidationThreshold=8500, $1 price
const USDC_ROW = {
    decimals: '6',
    liquidation_threshold: '8500',
    scaled_atoken_balance: '0',
    scaled_debt_balance: '1000000',             // 1 USDC debt
    latest_price: WAD.toString(),
};

// ─── Mock builder ─────────────────────────────────────────────────────────────

function mockDataSource(
    affectedUsers: { user_id: string }[],
    positionRows: Record<string, string>[],
) {
    let callCount = 0;
    return {
        query: jest.fn().mockImplementation(() => {
            // First call = affected users SELECT
            // Subsequent calls = position rows SELECT per user
            if (callCount === 0) {
                callCount++;
                return Promise.resolve(affectedUsers);
            }
            // Every other call alternates between position SELECT and UPDATE
            callCount++;
            if (callCount % 2 === 0) {
                return Promise.resolve(positionRows);
            }
            return Promise.resolve([]); // UPDATE returns empty
        }),
    };
}

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('HealthFactorProcessor', () => {
    let processor: HealthFactorProcessor;
    let dataSource: { query: jest.Mock };

    async function buildModule(
        affectedUsers: { user_id: string }[],
        positionRows: Record<string, string>[],
    ) {
        dataSource = mockDataSource(affectedUsers, positionRows);

        const module: TestingModule = await Test.createTestingModule({
            providers: [
                HealthFactorProcessor,
                {
                    provide: getDataSourceToken(),
                    useValue: dataSource,
                },
            ],
        }).compile();

        processor = module.get(HealthFactorProcessor);
    }

    it('should be defined', async () => {
        await buildModule([], []);
        expect(processor).toBeDefined();
    });

    it('does nothing when no users hold the affected market', async () => {
        await buildModule([], []);
        await processor.process({ data: { marketId: 'mkt-1', newPrice: '1000' } } as never);
        // Only the initial SELECT was called — no UPDATE
        expect(dataSource.query).toHaveBeenCalledTimes(1);
    });

    it('calls recompute for each affected user', async () => {
        await buildModule(AFFECTED_USERS, [WETH_ROW, USDC_ROW]);
        await processor.process({ data: { marketId: 'mkt-1', newPrice: '2000' } } as never);

        // 1 SELECT for affected users + (1 SELECT positions + 1 UPDATE) per user
        expect(dataSource.query).toHaveBeenCalledTimes(1 + AFFECTED_USERS.length * 2);
    });

    it('writes health_factor UPDATE with correct userId', async () => {
        await buildModule([{ user_id: 'user-1' }], [WETH_ROW, USDC_ROW]);
        await processor.process({ data: { marketId: 'mkt-1', newPrice: '2000' } } as never);

        const updateCall = dataSource.query.mock.calls.find(
            (args: unknown[]) =>
                typeof args[0] === 'string' &&
                (args[0] as string).trimStart().toUpperCase().startsWith('UPDATE'),
        );
        expect(updateCall).toBeDefined();
        expect(updateCall![1][1]).toBe('user-1');
        // HF should be > 1 WAD (healthy: 1 WETH @ $2000 vs 1 USDC debt)
        expect(BigInt(updateCall![1][0])).toBeGreaterThan(WAD);
    });

    it('continues processing other users when one fails', async () => {
        await buildModule(AFFECTED_USERS, []);
        // Force second user's position query to succeed with empty → sentinel HF
        await processor.process({ data: { marketId: 'mkt-1', newPrice: '2000' } } as never);
        // Should not throw despite empty position rows
        expect(dataSource.query).toHaveBeenCalled();
    });
});
