import {
    Entity,
    Column,
    PrimaryGeneratedColumn,
    CreateDateColumn,
    ManyToOne,
    JoinColumn,
} from 'typeorm';
import { Market } from '../../markets/entities/market.entity';

/**
 * Mirrors the `prices` table defined in 001_initial_schema.sql.
 *
 * Schema:
 *   id          UUID PK
 *   market_id   UUID FK → markets.id
 *   price       NUMERIC(78,0)  — WAD (1e18), base currency
 *   timestamp   TIMESTAMPTZ
 *   created_at  TIMESTAMPTZ
 *
 * The previous entity used assetAddress + timestamp as a composite PK which
 * did not match the DB schema and caused TypeORM queries to silently fail.
 */
@Entity('prices')
export class Price {
    @PrimaryGeneratedColumn('uuid')
    id: string;

    @ManyToOne(() => Market, { nullable: false, eager: false })
    @JoinColumn({ name: 'market_id' })
    market: Market;

    @Column('numeric', { precision: 78, scale: 0 })
    price: string;

    @Column({ type: 'timestamp with time zone' })
    timestamp: Date;

    @CreateDateColumn({ name: 'created_at' })
    createdAt: Date;
}
