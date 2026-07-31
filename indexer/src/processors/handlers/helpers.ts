import { PoolClient } from "pg";

/**
 * Upserts a user row by wallet address (lowercase).
 * Updates last_active on every interaction.
 */
export async function upsertUser(address: string, client: PoolClient): Promise<void> {
    await client.query(
        `INSERT INTO users (address)
         VALUES ($1)
         ON CONFLICT (address) DO UPDATE SET last_active = NOW()`,
        [address.toLowerCase()],
    );
}

/**
 * Returns the UUID of a user by wallet address.
 * Assumes upsertUser() was already called for this address in this transaction.
 */
export async function resolveUserId(address: string, client: PoolClient): Promise<string> {
    const res = await client.query<{ id: string }>(
        "SELECT id FROM users WHERE address = $1",
        [address.toLowerCase()],
    );
    if (res.rows.length === 0) {
        throw new Error(`resolveUserId: user not found for address ${address}`);
    }
    return res.rows[0].id;
}

/**
 * Returns the UUID of a market by its on-chain asset address.
 * Returns null if the market has not been initialized in the database yet.
 */
export async function resolveMarketId(assetAddress: string, client: PoolClient): Promise<string | null> {
    const res = await client.query<{ id: string }>(
        "SELECT id FROM markets WHERE asset_address = $1",
        [assetAddress.toLowerCase()],
    );
    if (res.rows.length === 0) return null;
    return res.rows[0].id;
}
