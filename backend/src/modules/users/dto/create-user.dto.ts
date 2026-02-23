import { IsString, Length, Matches } from 'class-validator';

export class CreateUserDto {
  @IsString()
  @Length(42, 42)
  @Matches(/^0x[a-fA-F0-9]{40}$/, { message: 'Must be a valid Ethereum address' })
  address: string;
}
