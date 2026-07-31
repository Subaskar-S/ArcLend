import { LiquidationExecutor } from './liquidation-executor';
import { RedisLockService } from '../locking/redis-lock';

// ─── Mock external dependencies ───────────────────────────────────────────────

jest.mock('ethers', () => ({
    ethers: {
        JsonRpcProvider: jest.fn().mockReturnValue({}),
        Wallet: jest.fn().mockReturnValue({ address: '0xliquidator' }),
        Contract: jest.fn(),
    },
}));

jest.mock('../locking/redis-lock');

// ─── Helpers ──────────────────────────────────────────────────────────────────

function buildExecutor() {
    return new LiquidationExecutor(
        'redis://localhost:6379',
        'http://localhost:8545',
        '0xprivatekey',
        '0xpooladdress',
    );
}

function getLockInstance(): jest.Mocked<RedisLockService> {
    const MockClass = RedisLockService as jest.MockedClass<typeof RedisLockService>;
    return MockClass.mock.instances[MockClass.mock.instances.length - 1] as jest.Mocked<RedisLockService>;
}

const TX_RECEIPT = { blockNumber: 100, gasUsed: 120000n };
const TX = { hash: '0xtxhash', wait: jest.fn().mockResolvedValue(TX_RECEIPT) };

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('LiquidationExecutor', () => {
    let executor: LiquidationExecutor;
    let lock: jest.Mocked<RedisLockService>;

    beforeEach(() => {
        jest.clearAllMocks();
        executor = buildExecutor();
        lock = getLockInstance();
        lock.acquire = jest.fn().mockResolvedValue(true);
        lock.release = jest.fn().mockResolvedValue(undefined);
    });

    describe('lock behaviour', () => {
        it('skips execution when lock is busy', async () => {
            lock.acquire.mockResolvedValue(false);
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const simulateSpy = jest.spyOn(executor as any, 'simulate');

            await executor.liquidate('0xuser', '0xdebt', '0xcollateral', '1000');

            expect(simulateSpy).not.toHaveBeenCalled();
        });

        it('always releases lock after execution', async () => {
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            jest.spyOn(executor as any, 'simulate').mockResolvedValue(false);

            await executor.liquidate('0xuser', '0xdebt', '0xcollateral', '1000');

            expect(lock.release).toHaveBeenCalledWith('liquidation:0xuser');
        });

        it('releases lock even when an unexpected error is thrown', async () => {
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            jest.spyOn(executor as any, 'simulate').mockRejectedValue(new Error('network error'));

            await executor.liquidate('0xuser', '0xdebt', '0xcollateral', '1000');

            expect(lock.release).toHaveBeenCalledWith('liquidation:0xuser');
        });
    });

    describe('simulate', () => {
        it('skips liquidation when simulation returns false', async () => {
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            jest.spyOn(executor as any, 'simulate').mockResolvedValue(false);
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const approvalSpy = jest.spyOn(executor as any, 'ensureApproval');

            await executor.liquidate('0xuser', '0xdebt', '0xcollateral', '1000');

            expect(approvalSpy).not.toHaveBeenCalled();
        });

        it('proceeds to approval when simulation returns true', async () => {
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            jest.spyOn(executor as any, 'simulate').mockResolvedValue(true);
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const approvalSpy = jest.spyOn(executor as any, 'ensureApproval').mockImplementation(async () => {});
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            jest.spyOn(executor as any, 'executeCall').mockImplementation(async () => {});

            await executor.liquidate('0xuser', '0xdebt', '0xcollateral', '1000');

            expect(approvalSpy).toHaveBeenCalledWith('0xdebt', 1000n);
        });
    });

    describe('executeCall', () => {
        it('calls liquidationCall with correct argument order', async () => {
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            jest.spyOn(executor as any, 'simulate').mockResolvedValue(true);
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            jest.spyOn(executor as any, 'ensureApproval').mockImplementation(async () => {});
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const executeCallSpy = jest.spyOn(executor as any, 'executeCall').mockImplementation(async () => {});

            await executor.liquidate('0xuser', '0xdebt', '0xcollateral', '500000');

            // collateralAsset, debtAsset, userAddress, debtToCoverBn
            expect(executeCallSpy).toHaveBeenCalledWith('0xcollateral', '0xdebt', '0xuser', 500000n);
        });
    });
});
