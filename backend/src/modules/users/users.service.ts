import { Injectable, ConflictException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User } from './entities/user.entity';
import { CreateUserDto } from './dto/create-user.dto';

@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(User)
    private usersRepository: Repository<User>,
  ) {}

  async create(createUserDto: CreateUserDto): Promise<User> {
    const existing = await this.usersRepository.findOneBy({ address: createUserDto.address.toLowerCase() });
    if (existing) {
      throw new ConflictException('User already exists');
    }
    const user = this.usersRepository.create({
      ...createUserDto,
      address: createUserDto.address.toLowerCase()
    });
    return this.usersRepository.save(user);
  }

  async findAll(): Promise<User[]> {
    return this.usersRepository.find();
  }

  async findOne(id: string): Promise<User | null> {
    return this.usersRepository.findOneBy({ id });
  }

  async findByAddress(address: string): Promise<User | null> {
    return this.usersRepository.findOneBy({ address: address.toLowerCase() });
  }
}
