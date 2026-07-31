import { ethers } from "ethers";

/** Minimal ERC20 ABI — only symbol() and decimals() */
const ERC20_META_ABI = [
    "function symbol() view returns (string)",
    "function decimals() view returns (uint8)",
];

export interface Erc20Metadata {
    symbol: string;
    decimals: number;
}

/**
 * Fetches ERC20 symbol and decimals for a token contract by calling the chain.
 *
 * Both calls use staticCall so they never send a transaction.
 * Falls back to safe defaults if either call reverts (e.g. non-standard tokens).
 *
 * @param assetAddress  Lowercase ERC20 contract address
 * @param provider      ethers JsonRpcProvider
 */
export async function fetchErc20Metadata(
    assetAddress: string,
    provider: ethers.JsonRpcProvider,
): Promise<Erc20Metadata> {
    const contract = new ethers.Contract(assetAddress, ERC20_META_ABI, provider);

    const [symbol, decimals] = await Promise.all([
        contract.symbol().catch(() => {
            console.warn(`[fetchErc20Metadata] symbol() failed for ${assetAddress} — defaulting to UNKNOWN`);
            return "UNKNOWN";
        }),
        contract.decimals().catch(() => {
            console.warn(`[fetchErc20Metadata] decimals() failed for ${assetAddress} — defaulting to 18`);
            return 18;
        }),
    ]);

    return {
        symbol: String(symbol).slice(0, 10), // markets.symbol is VARCHAR(10)
        decimals: Number(decimals),
    };
}
