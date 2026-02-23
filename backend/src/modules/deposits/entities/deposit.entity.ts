import { Entity, Column, PrimaryGeneratedColumn, CreateDateColumn, ManyToOne, JoinColumn } from 'typeorm';
import { User } from '../../users/entities/user.entity';
import { Market } from '../../markets/entities/market.entity';

@Entity('deposits')
export class Deposit {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'tx_hash', length: 66 })
  txHash: string;

  @Column('int', { name: 'log_index' })
  logIndex: number;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'user_id' })
  user: User;

  @ManyToOne(() => Market)
  @JoinColumn({ name: 'market_id' })
  market: Market;

  @Column('numeric', { precision: 78, scale: 0 })
  amount: string;

  @ManyToOne(() => User, { nullable: true })
  @JoinColumn({ name: 'on_behalf_of' })
  onBehalfOf: User;

  @Column({ type: 'timestamp with time zone' })
  timestamp: Date;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;
}
