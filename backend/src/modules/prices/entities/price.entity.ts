import { Entity, Column, PrimaryColumn, CreateDateColumn } from 'typeorm';

@Entity('prices')
export class Price {
  @PrimaryColumn({ name: 'asset_address', length: 42 })
  assetAddress: string;

  @PrimaryColumn({ type: 'timestamp with time zone' })
  timestamp: Date;

  @Column('numeric', { precision: 78, scale: 0 })
  price: string;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;
}
