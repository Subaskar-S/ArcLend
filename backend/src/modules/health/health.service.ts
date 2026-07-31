import { Injectable, NotFoundException } from '@nestjs/common';
import { UsersService } from '../users/users.service';
import { PricesService } from '../prices/prices.service';
import { UserPositionRepository } from './user-position.repository';
import { WAD, wadMul, wadDiv, percentMul, toWad } from '../../shared/utils/wad-ray-math';

export interface HealthFactorResult {
    /** WAD-scaled health factor as a decimal string, e.g. "1500000000000000000" */
    healthFactor: string;
    /** Total collateral value in base currency (WAD) */
    totalCollateralBase: string;
    /** Total debt value in base currency (WAD) */
    totalDebtBase: string;
    /** true if HF >= 1.0 WAD */
    isCollateralized: boolean;
}

@Injectable()
export class HealthService {
    constructor(
        private readonly usersService: UsersService,
        private readonly pricesService: PricesService,
        private readonly userPositionRepository: UserPositionRepository,
    ) {}

    /**
     * Computes the health factor for a user from on-chain-mirrored DB state.
     *
     * Formula (mirrors GenericLogic.sol):
     *
     *   totalCollateralBase = Σ (nominalATokenBalance_i * price_i)          [WAD]
     *   totalDebtBase       = Σ (nominalDebtBalance_i  * price_i)           [WAD]
     *   liquidationScore    = Σ (collateralValue_i * liquidationThreshold_i) [WAD * BPS → WAD after percentMul]
     *   healthFactor        = liquidationScore / totalDebtBase               [WAD]
     *
     * Notes:
     * - scaled_atoken_balance and scaled_debt_balance stored by the indexer are
     *   the raw nominal amounts (not truly scaled by the liquidity index).
     *   When the indexer is upgraded to store real scaled balances and the
     *   current index is available, replace with: rayMul(scaledBalance, index).
     * - Prices are in WAD (1e18) from PriceOracle, denominated in base currency.
     * - Non-18-decimal tokens are normalised to WAD via toWad().
     */
    async calculateHealthFactor(userId: string): Promise<HealthFactorResult> {
        // 1. Verify user exists
        const user = await this.usersService.findOne(userId);
        if (!user) {
            throw new NotFoundException(`User ${userId} not found`);
        }

        // 2. Load all active positions for this user (joined with market params)
        const positions = await this.userPositionRepository.findPositionsByUserId(userId);

        if (positions.length === 0) {
            // No positions — health factor is effectively infinite (no debt risk)
            return {
                healthFactor: WAD.toString(),   // return 1.0 WAD as a safe neutral value
                totalCollateralBase: '0',
                totalDebtBase: '0',
                isCollateralized: true,
            };
        }

        // 3. Accumulate totals in WAD across all markets
        let totalCollateralBase = 0n;   // Σ collateralValue_i (WAD)
        let liquidationScore = 0n;      // Σ collateralValue_i * liquidationThreshold_i (WAD)
        let totalDebtBase = 0n;         // Σ debtValue_i (WAD)

        for (const position of positions) {
            // Skip markets with no balance at all
            if (position.scaledATokenBalance === 0n && position.scaledDebtBalance === 0n) {
                continue;
            }

            // 3a. Fetch latest price for this asset (WAD — 1e18 base currency)
            const priceRecord = await this.pricesService.getLatestPrice(position.assetAddress);
            if (!priceRecord) {
                // No price available for this asset — skip rather than corrupt HF
                continue;
            }
            const price = BigInt(priceRecord.price);

            // 3b. Normalise balances to WAD (handles USDC 6-decimal etc.)
            const collateralWad = toWad(position.scaledATokenBalance, position.decimals);
            const debtWad = toWad(position.scaledDebtBalance, position.decimals);

            // 3c. Value in base currency: amount (WAD) × price (WAD) → WAD
            const collateralValue = wadMul(collateralWad, price);
            const debtValue = wadMul(debtWad, price);

            totalCollateralBase += collateralValue;
            totalDebtBase += debtValue;

            // 3d. Weighted collateral by liquidation threshold (basis points)
            liquidationScore += percentMul(
                collateralValue,
                BigInt(position.liquidationThreshold),
            );
        }

        // 4. Compute health factor
        //    HF = liquidationScore / totalDebtBase
        //    If there is no debt, position is fully safe — return max sentinel value
        let healthFactor: bigint;
        if (totalDebtBase === 0n) {
            healthFactor = WAD * 1000n; // sentinel: 1000 WAD = "no debt / infinite HF"
        } else {
            healthFactor = wadDiv(liquidationScore, totalDebtBase);
        }

        return {
            healthFactor: healthFactor.toString(),
            totalCollateralBase: totalCollateralBase.toString(),
            totalDebtBase: totalDebtBase.toString(),
            isCollateralized: healthFactor >= WAD,
        };
    }
}
