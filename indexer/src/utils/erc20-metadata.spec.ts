import { fetchErc20Metadata } from "./erc20-metadata";
import { ethers } from "ethers";

// ─── Mocks ────────────────────────────────────────────────────────────────────

jest.mock("ethers", () => {
    const mockSymbol = jest.fn();
    const mockDecimals = jest.fn();
    const MockContract = jest.fn().mockImplementation(() => ({
        symbol: mockSymbol,
        decimals: mockDecimals,
    }));

    return {
        ethers: {
            Contract: MockContract,
            JsonRpcProvider: jest.fn(),
        },
        __mockSymbol: mockSymbol,
        __mockDecimals: mockDecimals,
    };
});

function getMocks() {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const m = require("ethers");
    return { symbol: m.__mockSymbol as jest.Mock, decimals: m.__mockDecimals as jest.Mock };
}

const mockProvider = {} as ethers.JsonRpcProvider;

// ─── Tests ────────────────────────────────────────────────────────────────────

describe("fetchErc20Metadata", () => {
    beforeEach(() => jest.clearAllMocks());

    it("returns real symbol and decimals from a standard ERC20", async () => {
        const { symbol, decimals } = getMocks();
        symbol.mockResolvedValue("WETH");
        decimals.mockResolvedValue(18);

        const result = await fetchErc20Metadata("0xweth", mockProvider);

        expect(result).toEqual({ symbol: "WETH", decimals: 18 });
    });

    it("returns real decimals for a 6-decimal token (USDC)", async () => {
        const { symbol, decimals } = getMocks();
        symbol.mockResolvedValue("USDC");
        decimals.mockResolvedValue(6);

        const result = await fetchErc20Metadata("0xusdc", mockProvider);

        expect(result).toEqual({ symbol: "USDC", decimals: 6 });
    });

    it("falls back to UNKNOWN when symbol() reverts", async () => {
        const { symbol, decimals } = getMocks();
        symbol.mockRejectedValue(new Error("revert"));
        decimals.mockResolvedValue(18);

        const result = await fetchErc20Metadata("0xbad", mockProvider);

        expect(result.symbol).toBe("UNKNOWN");
        expect(result.decimals).toBe(18);
    });

    it("falls back to 18 decimals when decimals() reverts", async () => {
        const { symbol, decimals } = getMocks();
        symbol.mockResolvedValue("TKN");
        decimals.mockRejectedValue(new Error("revert"));

        const result = await fetchErc20Metadata("0xbad", mockProvider);

        expect(result.symbol).toBe("TKN");
        expect(result.decimals).toBe(18);
    });

    it("truncates symbol to 10 characters", async () => {
        const { symbol, decimals } = getMocks();
        symbol.mockResolvedValue("VERYLONGSYMBOL");
        decimals.mockResolvedValue(18);

        const result = await fetchErc20Metadata("0xlong", mockProvider);

        expect(result.symbol).toBe("VERYLONGSY"); // VARCHAR(10) limit
        expect(result.symbol.length).toBeLessThanOrEqual(10);
    });
});
