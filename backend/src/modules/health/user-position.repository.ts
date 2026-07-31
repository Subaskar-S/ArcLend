import { Injectable } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';

export interface UserPositionRow {
    marketId: string;
    assetAddress: string;
    decimals: number;
    liquidationThreshold: number;   // basis points
    scaledATokenBalance: bigint;    // from user_positions (raw NUMERIC string → bigint)
    scaledDebtBalance: bigint;
}

/**
 * Raw query against user_positions joined with markets.
 * TypeORM entities are not used here because user_positions is written
 * directly by the indexer (raw pg) and has no TypeORM entity yet.
 */
@Injectable()
export class UserPositionRepository {
    constructor(
        @InjectDataSource()
        private readonly dataSource: DataSource,
    ) {}

    async findPositionsByUserId(userId: string): Promise<UserPositionRow[]> {
        const rows = await this.dataSource.query<Array<Record<string, string>>>(
            `SELECT
                up.market_id                  AS "marketId",
                m.asset_address               AS "assetAddress",
                m.decimals                    AS "decimals",
                m.liquidation_threshold       AS "liquidationThreshold",
                up.scaled_atoken_balance      AS "scaledATokenBalance",
                up.scaled_debt_balance        AS "scaledDebtBalance"
             FROM user_positions up
             JOIN markets m ON m.id = up.market_id
             WHERE up.user_id = $1
               AND m.is_active = true`,
            [userId],
        );

        return rows.map(r => ({
            marketId: r.marketId,
            assetAddress: r.assetAddress,
            decimals: parseInt(r.decimals, 10),
            liquidationThreshold: parseInt(r.liquidationThreshold, 10),
            scaledATokenBalance: BigInt(r.scaledATokenBalance ?? '0'),
            scaledDebtBalance: BigInt(r.scaledDebtBalance ?? '0'),
        }));
    }
}
