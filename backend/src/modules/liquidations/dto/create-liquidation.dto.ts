import { IsString, IsNotEmpty, IsInt, Min, IsUUID, IsNumberString, IsDateString, Length, Matches } from 'class-validator';

export class CreateLiquidationDto {
  @IsString()
  @IsNotEmpty()
  txHash: string;

  @IsInt()
  @Min(0)
  logIndex: number;

  @IsUUID()
  collateralMarketId: string;

  @IsUUID()
  debtMarketId: string;

  @IsUUID()
  liquidatedUserId: string;

  @IsString()
  @Length(42, 42)
  @Matches(/^0x[a-fA-F0-9]{40}$/)
  liquidatorAddress: string;

  @IsNumberString()
  debtToCover: string;

  @IsNumberString()
  collateralSeized: string;

  @IsDateString()
  timestamp: string;
}
