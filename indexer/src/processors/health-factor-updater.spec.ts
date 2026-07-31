import { updateHealthFactor } from "./health-factor-updater";
import { PoolClient } from "pg";

// ─── Constants ────────────────────────────────────────────────────────────────

const WAD = 10n ** 18n;
const USER_ID = "user-uuid";

// ─── Mock builder ─────────────────────────────────────────────────────────────

/**
 * Build a mock PoolClient whose query() returns different results depending
 * on which SQL statement is invoked (SELECT vs UPDATE).
 */
function mockClient(positionRows: Record<string, string>[]): jest.Mocked<PoolClient> {
    const queryMock = jest.fn().mockImplementation((sql: string) => {
        if (sql.trimStart().toUpperCase().startsWith("SELECT")) {
            return Promise.resolve({ rows: positionRows, rowCount: positionRows.length });
        }
        // UPDATE — return empty result
        return Promise.resolve({ rows: [], rowCount: positionRows.length });
    });
    return { query: queryMock } as unknown as jest.Mocked<PoolClient>;
}

// ─── Fixtures ─────────────────────────────────────────────────────────────────

// WETH: 18 decimals, liquidationThreshold = 8000 bps (80%), price = $2000 WAD
const WETH_COLLATERAL = {
    market_id: "mkt-weth",
    decimals: "18",
    liquidation_threshold: "8000",
    scaled_atoken_balance: WAD.toString(),        // 1 WETH collateral
    scaled_debt_balance: "0",
    latest_price: (2000n * WAD).toString(),
};

// USDC: 6 decimals, liquidationThreshold = 8500 bps (85%), price = $1 WAD
const USDC_DEBT = {
    market_id: "mkt-usdc",
    decimals: "6",
    liquidation_threshold: "8500",
    scaled_atoken_balance: "0",
    scaled_debt_balance: "1000000",               // 1 USDC debt (6 dec)
    latest_price: WAD.toString(),
};

// ─── Tests ────────────────────────────────────────────────────────────────────

describe("updateHealthFactor", () => {
    it("does nothing when user has no positions", async () => {
        const client = mockClient([]);
        await updateHealthFactor(USER_ID, client);
        // UPDATE should not have been called
        const updateCalls = (client.query as jest.Mock).mock.calls.filter(
            (args: unknown[]) => typeof args[0] === "string" && (args[0] as string).trimStart().toUpperCase().startsWith("UPDATE"),
        );
        expect(updateCalls).toHaveLength(0);
    });

    it("sets sentinel HF (1000 WAD) when user has collateral but no debt", async () => {
        const client = mockClient([WETH_COLLATERAL]);
        await updateHealthFactor(USER_ID, client);

        const updateCall = (client.query as jest.Mock).mock.calls.find(
            (args: unknown[]) => typeof args[0] === "string" && (args[0] as string).trimStart().toUpperCase().startsWith("UPDATE"),
        );
        expect(updateCall).toBeDefined();
        const hf = BigInt(updateCall![1][0]);
        expect(hf).toBe(1000n * WAD);
    });

    it("computes HF correctly for a healthy position", async () => {
        // Collateral: 1 WETH @ $2000, liquidationThreshold = 80%
        // Debt:       1 USDC @ $1
        //
        // collateralValueBase = 1e18 * 2000e18 / 1e18 = 2000e18
        // liquidationScore    = 2000e18 * 8000 / 10000 = 1600e18
        // debtValueBase       = 1e12 (6-dec normalised) * 1e18 / 1e18 = 1e12
        //   toWad(1_000_000, 6) = 1_000_000 * 1e12 = 1e18
        //   debtValueBase = 1e18 * 1e18 / 1e18 = 1e18
        // HF = 1600e18 * 1e18 / 1e18 = 1600e18

        const client = mockClient([WETH_COLLATERAL, USDC_DEBT]);
        await updateHealthFactor(USER_ID, client);

        const updateCall = (client.query as jest.Mock).mock.calls.find(
            (args: unknown[]) => typeof args[0] === "string" && (args[0] as string).trimStart().toUpperCase().startsWith("UPDATE"),
        );
        const hf = BigInt(updateCall![1][0]);

        // HF should be ~1600 WAD — healthy
        expect(hf).toBeGreaterThan(WAD);
        expect(hf).toBeGreaterThan(100n * WAD); // definitely not near liquidation
    });

    it("computes HF below 1 WAD for an underwater position", async () => {
        // Collateral: 1 USDC @ $1, liquidationThreshold = 85%
        // Debt:       1 WETH @ $2000
        //
        // liquidationScore = 1e18 * 8500 / 10000 = 0.85e18
        // debtValueBase    = 1e18 * 2000e18 / 1e18 = 2000e18
        // HF = 0.85e18 * 1e18 / 2000e18 << 1e18
        const usdcCollateral = { ...USDC_DEBT, scaled_atoken_balance: "1000000", scaled_debt_balance: "0" };
        const wethDebt = { ...WETH_COLLATERAL, scaled_atoken_balance: "0", scaled_debt_balance: WAD.toString() };

        const client = mockClient([usdcCollateral, wethDebt]);
        await updateHealthFactor(USER_ID, client);

        const updateCall = (client.query as jest.Mock).mock.calls.find(
            (args: unknown[]) => typeof args[0] === "string" && (args[0] as string).trimStart().toUpperCase().startsWith("UPDATE"),
        );
        const hf = BigInt(updateCall![1][0]);

        expect(hf).toBeLessThan(WAD);
    });

    it("skips markets with no price data and does not throw", async () => {
        const noPrice = { ...WETH_COLLATERAL, latest_price: null as unknown as string };
        const client = mockClient([noPrice]);
        await updateHealthFactor(USER_ID, client);

        const updateCall = (client.query as jest.Mock).mock.calls.find(
            (args: unknown[]) => typeof args[0] === "string" && (args[0] as string).trimStart().toUpperCase().startsWith("UPDATE"),
        );
        // No debt, no collateral (price missing) → sentinel
        const hf = BigInt(updateCall![1][0]);
        expect(hf).toBe(1000n * WAD);
    });

    it("writes health factor to user_positions with correct userId", async () => {
        const client = mockClient([WETH_COLLATERAL, USDC_DEBT]);
        await updateHealthFactor(USER_ID, client);

        const updateCall = (client.query as jest.Mock).mock.calls.find(
            (args: unknown[]) => typeof args[0] === "string" && (args[0] as string).trimStart().toUpperCase().startsWith("UPDATE"),
        );
        expect(updateCall![1][1]).toBe(USER_ID);
    });
});
