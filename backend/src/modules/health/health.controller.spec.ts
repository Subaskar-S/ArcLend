import { Test, TestingModule } from '@nestjs/testing';
import { HealthController } from './health.controller';
import { HealthService } from './health.service';

describe('HealthController', () => {
  let controller: HealthController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [HealthController],
      providers: [
        {
          provide: HealthService,
          useValue: {
            calculateHealthFactor: jest.fn().mockResolvedValue('1500000000000000000'),
          },
        },
      ],
    }).compile();

    controller = module.get(HealthController);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });

  describe('getUserHealthFactor', () => {
    it('should return health factor data for a user', async () => {
      const result = await controller.getUserHealthFactor('some-uuid');
      expect(result).toEqual({
        userId: 'some-uuid',
        healthFactor: '1500000000000000000',
        isCollateralized: true,
      });
    });
  });
});
