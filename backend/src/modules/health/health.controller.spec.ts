import { Test, TestingModule } from '@nestjs/testing';
import { HealthController } from './health.controller';
import { HealthService } from './health.service';
import { WAD } from '../../shared/utils/wad-ray-math';

const MOCK_HEALTHY_RESULT = {
    healthFactor: (1500n * WAD).toString(),
    totalCollateralBase: (3000n * WAD).toString(),
    totalDebtBase: (1000n * WAD).toString(),
    isCollateralized: true,
};

const MOCK_UNDERWATER_RESULT = {
    healthFactor: (8n * WAD / 10n).toString(),   // 0.8 WAD — liquidatable
    totalCollateralBase: (500n * WAD).toString(),
    totalDebtBase: (1000n * WAD).toString(),
    isCollateralized: false,
};

describe('HealthController', () => {
    let controller: HealthController;
    let service: jest.Mocked<HealthService>;

    beforeEach(async () => {
        const module: TestingModule = await Test.createTestingModule({
            controllers: [HealthController],
            providers: [
                {
                    provide: HealthService,
                    useValue: {
                        calculateHealthFactor: jest.fn(),
                    },
                },
            ],
        }).compile();

        controller = module.get(HealthController);
        service = module.get(HealthService) as jest.Mocked<HealthService>;
    });

    it('should be defined', () => {
        expect(controller).toBeDefined();
    });

    describe('getUserHealthFactor', () => {
        it('returns full health data for a healthy user', async () => {
            service.calculateHealthFactor.mockResolvedValue(MOCK_HEALTHY_RESULT);

            const result = await controller.getUserHealthFactor('user-uuid');

            expect(result).toEqual({ userId: 'user-uuid', ...MOCK_HEALTHY_RESULT });
            expect(service.calculateHealthFactor).toHaveBeenCalledWith('user-uuid');
        });

        it('returns isCollateralized false for an underwater user', async () => {
            service.calculateHealthFactor.mockResolvedValue(MOCK_UNDERWATER_RESULT);

            const result = await controller.getUserHealthFactor('user-uuid');

            expect(result.isCollateralized).toBe(false);
            expect(BigInt(result.healthFactor)).toBeLessThan(WAD);
        });
    });
});
