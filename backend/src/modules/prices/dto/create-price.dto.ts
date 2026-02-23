import { IsString, IsNotEmpty, IsNumberString, IsDateString, Length, Matches } from 'class-validator';

export class CreatePriceDto {
  @IsString()
  @Length(42, 42)
  @Matches(/^0x[a-fA-F0-9]{40}$/, { message: 'Must be a valid Ethereum address' })
  assetAddress: string;

  @IsDateString()
  timestamp: string;

  @IsNumberString()
  @IsNotEmpty()
  price: string;
}
