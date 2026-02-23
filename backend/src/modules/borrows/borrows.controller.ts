import { Controller, Get, Post, Body, Param, ParseUUIDPipe } from '@nestjs/common';
import { BorrowsService } from './borrows.service';
import { CreateBorrowDto } from './dto/create-borrow.dto';
import { Borrow } from './entities/borrow.entity';

@Controller('borrows')
export class BorrowsController {
  constructor(private readonly borrowsService: BorrowsService) {}

  @Post()
  create(@Body() createBorrowDto: CreateBorrowDto): Promise<Borrow> {
    return this.borrowsService.create(createBorrowDto);
  }

  @Get('user/:userId')
  findAllByUserId(@Param('userId', ParseUUIDPipe) userId: string): Promise<Borrow[]> {
    return this.borrowsService.findAllByUserId(userId);
  }
}
