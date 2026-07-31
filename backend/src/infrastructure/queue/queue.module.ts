import { Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { HealthFactorProcessor } from './health-factor.processor';
import { HEALTH_FACTOR_QUEUE } from './health-factor-job.types';

@Module({
    imports: [
        BullModule.forRootAsync({
            imports: [ConfigModule],
            useFactory: async (configService: ConfigService) => {
                const url = new URL(configService.get('REDIS_URL') || 'redis://localhost:6379');
                return {
                    connection: {
                        host: url.hostname,
                        port: parseInt(url.port, 10),
                        password: url.password || undefined,
                    },
                };
            },
            inject: [ConfigService],
        }),
        BullModule.registerQueue({
            name: HEALTH_FACTOR_QUEUE,
        }),
    ],
    providers: [HealthFactorProcessor],
    exports: [BullModule],
})
export class QueueModule {}
