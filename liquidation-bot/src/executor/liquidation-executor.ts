import { ethers } from 'ethers';
import { RedisLockService } from '../locking/redis-lock';

/** Minimal ABIs — only the functions the bot needs */
const LIQUIDATION_CALL_ABI = [
    'function liquidationCall(address collateralAsset, address debtAsset, address user, uint256 debtToCover) external',
];

const ERC20_APPROVE_ABI = [
    'function approve(address spender, uint256 amount) external returns (bool)',
    'function allowance(address owner, address spender) external view returns (uint256)',
];

/** Lock TTL — enough for 1 tx broadcast + 1 confirmation */
const LOCK_TTL_MS = 30_000;

/** Max uint256 — used for unlimited approval */
const MAX_UINT256 = 2n ** 256n - 1n;

export class LiquidationExecutor {
    private readonly provider: ethers.JsonRpcProvider;
    private readonly wallet: ethers.Wallet;
    private readonly lockService: RedisLockService;

    constructor(
        redisUrl: string,
        rpcUrl: string,
        privateKey: string,
        private readonly lendingPoolAddress: string,
    ) {
        this.provider = new ethers.JsonRpcProvider(rpcUrl);
        this.wallet = new ethers.Wallet(privateKey, this.provider);
        this.lockService = new RedisLockService(redisUrl);
    }

    /**
     * Attempts to liquidate an undercollateralised position.
     *
     * Steps:
     *  1. Acquire a per-user Redis distributed lock (prevents concurrent races)
     *  2. Simulate the call via eth_call to confirm it won't revert
     *  3. Approve the lending pool to spend debtToCover of debtAsset (if needed)
     *  4. Execute liquidationCall()
     *  5. Wait for confirmation
     *  6. Release lock
     *
     * @param userAddress     The liquidatable user's wallet address
     * @param debtAsset       ERC20 address of the asset to repay
     * @param collateralAsset ERC20 address of the collateral to seize
     * @param debtToCover     Amount of debt to cover (string to avoid JS number overflow)
     */
    async liquidate(
        userAddress: string,
        debtAsset: string,
        collateralAsset: string,
        debtToCover: string,
    ): Promise<void> {
        const lockResource = `liquidation:${userAddress.toLowerCase()}`;

        // ── Step 1: Acquire distributed lock ─────────────────────────────────
        const acquired = await this.lockService.acquire(lockResource, LOCK_TTL_MS);
        if (!acquired) {
            console.log(`[Executor] Lock busy — another instance is processing ${userAddress}`);
            return;
        }

        try {
            console.log(`[Executor] Starting liquidation for ${userAddress}`);
            console.log(`[Executor]   debt asset:       ${debtAsset}`);
            console.log(`[Executor]   collateral asset: ${collateralAsset}`);
            console.log(`[Executor]   debt to cover:    ${debtToCover}`);

            const debtToCoverBn = BigInt(debtToCover);

            // ── Step 2: Simulate via eth_call ─────────────────────────────────
            const profitable = await this.simulate(
                collateralAsset,
                debtAsset,
                userAddress,
                debtToCoverBn,
            );
            if (!profitable) {
                console.log(`[Executor] Simulation failed for ${userAddress} — skipping`);
                return;
            }

            // ── Step 3: Approve lending pool to spend debt asset ──────────────
            await this.ensureApproval(debtAsset, debtToCoverBn);

            // ── Step 4: Execute liquidationCall ───────────────────────────────
            await this.executeCall(collateralAsset, debtAsset, userAddress, debtToCoverBn);

        } catch (error) {
            console.error(`[Executor] Liquidation failed for ${userAddress}:`, error);
            // Do not rethrow — the outer loop continues with the next user
        } finally {
            // ── Step 6: Always release the lock ──────────────────────────────
            await this.lockService.release(lockResource);
        }
    }

    /**
     * Broadcasts the liquidationCall transaction and waits for confirmation.
     */
    private async executeCall(
        collateralAsset: string,
        debtAsset: string,
        userAddress: string,
        debtToCover: bigint,
    ): Promise<void> {
        const pool = new ethers.Contract(
            this.lendingPoolAddress,
            LIQUIDATION_CALL_ABI,
            this.wallet,
        );

        const tx = await pool.liquidationCall(collateralAsset, debtAsset, userAddress, debtToCover);
        console.log(`[Executor] TX sent: ${tx.hash}`);

        // ── Step 5: Wait for on-chain confirmation ────────────────────────────
        const receipt = await tx.wait();
        console.log(`[Executor] Confirmed in block ${receipt.blockNumber} — gas used: ${receipt.gasUsed}`);
    }

    /**
     * Simulates the liquidation call via eth_call.
     * Returns true if the call succeeds, false if it would revert.
     */
    private async simulate(
        collateralAsset: string,
        debtAsset: string,
        userAddress: string,
        debtToCover: bigint,
    ): Promise<boolean> {
        try {
            const pool = new ethers.Contract(
                this.lendingPoolAddress,
                LIQUIDATION_CALL_ABI,
                this.wallet,
            );
            // staticCall does not broadcast — uses eth_call
            await pool.liquidationCall.staticCall(
                collateralAsset,
                debtAsset,
                userAddress,
                debtToCover,
            );
            return true;
        } catch (err) {
            const message = err instanceof Error ? err.message : String(err);
            console.warn(`[Executor] Simulation reverted: ${message}`);
            return false;
        }
    }

    /**
     * Ensures the lending pool has sufficient allowance to spend debtToCover
     * of the given ERC20 token on behalf of the liquidator wallet.
     * Sends an approve() tx only if current allowance is insufficient.
     */
    private async ensureApproval(debtAsset: string, debtToCover: bigint): Promise<void> {
        const token = new ethers.Contract(debtAsset, ERC20_APPROVE_ABI, this.wallet);

        const currentAllowance: bigint = await token.allowance(
            this.wallet.address,
            this.lendingPoolAddress,
        );

        if (currentAllowance >= debtToCover) {
            return; // already approved
        }

        console.log(`[Executor] Approving lending pool to spend ${debtAsset}...`);
        const approveTx = await token.approve(this.lendingPoolAddress, MAX_UINT256);
        await approveTx.wait();
        console.log(`[Executor] Approval confirmed for ${debtAsset}`);
    }
}
