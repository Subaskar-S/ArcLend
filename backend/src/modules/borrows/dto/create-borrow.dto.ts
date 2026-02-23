import { IsString, IsNotEmpty, IsInt, Min, IsUUID, IsNumberString, IsDateString } from 'class-validator';

export class CreateBorrowDto {
  @IsString()
  @IsNotEmpty()
  txHash: string;

  @IsInt()
  @Min(0)
  logIndex: number;

  @IsUUID()
  userId: string;

  @IsUUID()
  marketId: string;

  @IsNumberString()
  amount: string;

  @IsNumberString()
  borrowRate: string;

  @IsDateString()
  timestamp: string;
}
