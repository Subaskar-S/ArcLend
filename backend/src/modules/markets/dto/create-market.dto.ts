import { IsString, IsInt, Min, Max, IsBoolean, IsOptional, Length, Matches } from 'class-validator';

export class CreateMarketDto {
  @IsString()
  @Length(42, 42)
  @Matches(/^0x[a-fA-F0-9]{40}$/, { message: 'Must be a valid Ethereum address' })
  assetAddress: string;

  @IsString()
  @Length(1, 10)
  symbol: string;

  @IsInt()
  @Min(0)
  @Max(18)
  decimals: number;

  @IsInt()
  @Min(0)
  @Max(10000)
  ltv: number;

  @IsInt()
  @Min(0)
  @Max(10000)
  liquidationThreshold: number;

  @IsInt()
  @Min(0)
  @Max(10000)
  liquidationBonus: number;

  @IsInt()
  @Min(0)
  @Max(10000)
  reserveFactor: number;

  @IsBoolean()
  @IsOptional()
  isActive?: boolean;

  @IsBoolean()
  @IsOptional()
  isFrozen?: boolean;
}
