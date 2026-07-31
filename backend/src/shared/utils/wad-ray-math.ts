/**
 * BigInt fixed-point math utilities mirroring the Solidity WadRayMath and
 * PercentageMath libraries used by the on-chain contracts.
 *
 * WAD  = 1e18  — used for token balances, health factor, prices
 * RAY  = 1e27  — used for liquidity index, borrow index, interest rates
 * BPS  = 1e4   — used for LTV, liquidation threshold, bonus, reserve factor
 */

export const WAD = 10n ** 18n;
export const RAY = 10n ** 27n;
export const BPS = 10_000n; // basis points denominator

// ─── Wad math ────────────────────────────────────────────────────────────────

/** Multiply two wad values: (a * b + WAD/2) / WAD */
export function wadMul(a: bigint, b: bigint): bigint {
    if (a === 0n || b === 0n) return 0n;
    return (a * b + WAD / 2n) / WAD;
}

/** Divide two wad values: (a * WAD + b/2) / b */
export function wadDiv(a: bigint, b: bigint): bigint {
    if (b === 0n) throw new Error('WadRayMath: division by zero');
    return (a * WAD + b / 2n) / b;
}

// ─── Ray math ─────────────────────────────────────────────────────────────────

/** Multiply two ray values: (a * b + RAY/2) / RAY */
export function rayMul(a: bigint, b: bigint): bigint {
    if (a === 0n || b === 0n) return 0n;
    return (a * b + RAY / 2n) / RAY;
}

// ─── Basis-point (percentage) math ───────────────────────────────────────────

/** Apply a basis-point factor: (a * bps + BPS/2) / BPS */
export function percentMul(a: bigint, bps: bigint): bigint {
    if (a === 0n || bps === 0n) return 0n;
    return (a * bps + BPS / 2n) / BPS;
}

// ─── Decimal normalisation ────────────────────────────────────────────────────

/**
 * Normalise a token amount to 18-decimal WAD representation.
 * e.g. 1_000_000 USDC (6 decimals) → 1_000_000_000_000_000_000_000_000n (WAD)
 */
export function toWad(amount: bigint, decimals: number): bigint {
    if (decimals === 18) return amount;
    if (decimals < 18) return amount * 10n ** BigInt(18 - decimals);
    return amount / 10n ** BigInt(decimals - 18);
}
