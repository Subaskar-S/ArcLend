import { IsUUID, IsNotEmpty, IsNumberString, IsDateString } from 'class-validator';

export class CreatePriceDto {
    /** UUID of the market (from the markets table) */
    @IsUUID()
    @IsNotEmpty()
    marketId: string;

    @IsDateString()
    timestamp: string;

    /** Price in WAD (1e18), denominated in base currency */
    @IsNumberString()
    @IsNotEmpty()
    price: string;
}
