import { Entity, Column, PrimaryGeneratedColumn, CreateDateColumn, UpdateDateColumn } from 'typeorm';

@Entity('markets')
export class Market {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'asset_address', unique: true, length: 42 })
  assetAddress: string;

  @Column({ length: 10 })
  symbol: string;

  @Column('int')
  decimals: number;

  @Column('numeric', { precision: 5, scale: 0, comment: 'Basis points' })
  ltv: number;

  @Column('numeric', { name: 'liquidation_threshold', precision: 5, scale: 0 })
  liquidationThreshold: number;

  @Column('numeric', { name: 'liquidation_bonus', precision: 5, scale: 0 })
  liquidationBonus: number;

  @Column('numeric', { name: 'reserve_factor', precision: 5, scale: 0 })
  reserveFactor: number;

  @Column({ name: 'is_active', default: true })
  isActive: boolean;

  @Column({ name: 'is_frozen', default: false })
  isFrozen: boolean;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;
}
