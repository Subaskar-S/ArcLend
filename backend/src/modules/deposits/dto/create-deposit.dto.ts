import { IsString, IsNotEmpty, IsInt, Min, IsUUID, IsNumberString, IsOptional, IsDateString } from 'class-validator';

export class CreateDepositDto {
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

  @IsUUID()
  @IsOptional()
  onBehalfOf?: string;

  @IsDateString()
  timestamp: string;
}
