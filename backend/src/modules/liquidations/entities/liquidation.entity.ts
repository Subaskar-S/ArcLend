import { Entity, Column, PrimaryGeneratedColumn, CreateDateColumn, ManyToOne, JoinColumn } from 'typeorm';
import { User } from '../../users/entities/user.entity';
import { Market } from '../../markets/entities/market.entity';

@Entity('liquidations')
export class Liquidation {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'tx_hash', length: 66 })
  txHash: string;

  @Column('int', { name: 'log_index' })
  logIndex: number;

  @ManyToOne(() => Market)
  @JoinColumn({ name: 'collateral_market_id' })
  collateralMarket: Market;

  @ManyToOne(() => Market)
  @JoinColumn({ name: 'debt_market_id' })
  debtMarket: Market;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'liquidated_user_id' })
  liquidatedUser: User;

  @Column({ name: 'liquidator_address', length: 42 })
  liquidatorAddress: string;

  @Column('numeric', { name: 'debt_to_cover', precision: 78, scale: 0 })
  debtToCover: string;

  @Column('numeric', { name: 'collateral_seized', precision: 78, scale: 0 })
  collateralSeized: string;

  @Column({ type: 'timestamp with time zone' })
  timestamp: Date;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;
}
