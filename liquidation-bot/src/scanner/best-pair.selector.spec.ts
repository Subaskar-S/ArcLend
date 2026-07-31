import { BestPairSelector } from './best-pair.selector';
import { Pool } from 'pg';

// ─── Fixtures ─────────────────────────────────────────────────────────────────

const WAD = 10n ** 18n;

/** Build a mock pg Pool whose query() returns the given rows */
function mockPool(rows: Record<string, string>[]): Pool {
    return {
        query: jest.fn().mockResolvedValue({ rows, rowCount: rows.length }),
    } as unknown as Pool;
}

const USER_ADDRESS = '0xuser';

// WETH market — 18 decimals, price $2000, bonus 10500 (105%)
const WETH_COLLATERAL_ROW = {
    market_id: 'mkt-weth',
    asset_address: '0xweth',
    decimals: '18',
    liquidation_bonus: '10500',
    scaled_atoken_balance: WAD.toString(),        // 1 WETH collateral
    scaled_debt_balance: '0',
    latest_price: (2000n * WAD).toString(),
};

// USDC market — 6 decimals, price $1, bonus 10500 (105%)
const USDC_DEBT_ROW = {
    market_id: 'mkt-usdc',
    asset_address: '0xusdc',
    decimals: '6',
    liquidation_bonus: '10500',
    scaled_atoken_balance: '0',
    scaled_debt_balance: '1000000',               // 1 USDC debt (6 decimals)
    latest_price: WAD.toString(),
};

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('BestPairSelector', () => {
    describe('selectPair', () => {
        it('returns null when user has no positions', async () => {
            const selector = new BestPairSelector(mockPool([]));
            const result = await selector.selectPair(USER_ADDRESS);
            expect(result).toBeNull();
        });

        it('returns null when user has collateral but no debt', async () => {
            const selector = new BestPairSelector(mockPool([WETH_COLLATERAL_ROW]));
            const result = await selector.selectPair(USER_ADDRESS);
            expect(result).toBeNull();
        });

        it('returns null when user has debt but no collateral', async () => {
            const selector = new BestPairSelector(mockPool([USDC_DEBT_ROW]));
            const result = await selector.selectPair(USER_ADDRESS);
            expect(result).toBeNull();
        });

        it('returns null when market has no price data', async () => {
            const rowNullPrice = { ...USDC_DEBT_ROW, latest_price: null as unknown as string };
            const selector = new BestPairSelector(mockPool([WETH_COLLATERAL_ROW, rowNullPrice]));
            // debt market has no price — can't select pair
            const result = await selector.selectPair(USER_ADDRESS);
            expect(result).toBeNull();
        });

        it('selects correct debt and collateral assets', async () => {
            const selector = new BestPairSelector(
                mockPool([WETH_COLLATERAL_ROW, USDC_DEBT_ROW]),
            );
            const result = await selector.selectPair(USER_ADDRESS);

            expect(result).not.toBeNull();
            expect(result!.userAddress).toBe(USER_ADDRESS);
            expect(result!.debtAsset).toBe('0xusdc');
            expect(result!.collateralAsset).toBe('0xweth');
        });

        it('applies 50% close factor to debtToCover', async () => {
            const selector = new BestPairSelector(
                mockPool([WETH_COLLATERAL_ROW, USDC_DEBT_ROW]),
            );
            const result = await selector.selectPair(USER_ADDRESS);

            // total debt = 1_000_000 (1 USDC in 6-dec units)
            // 50% close factor → 500_000
            expect(result!.debtToCover).toBe('500000');
        });

        it('picks highest-value debt when user has multiple debt markets', async () => {
            // WETH debt ($2000 value) vs USDC debt ($1 value)
            // Selector should pick WETH as the debt to cover
            const wethDebtRow = {
                ...WETH_COLLATERAL_ROW,
                scaled_atoken_balance: '0',
                scaled_debt_balance: WAD.toString(),    // 1 WETH debt = $2000
            };
            const usdcCollateralRow = {
                ...USDC_DEBT_ROW,
                scaled_atoken_balance: (10_000_000n).toString(), // 10 USDC collateral
                scaled_debt_balance: '1000000',                  // 1 USDC debt = $1
            };

            const selector = new BestPairSelector(
                mockPool([wethDebtRow, usdcCollateralRow]),
            );
            const result = await selector.selectPair(USER_ADDRESS);

            expect(result!.debtAsset).toBe('0xweth');
            expect(result!.collateralAsset).toBe('0xusdc');
        });
    });
});
