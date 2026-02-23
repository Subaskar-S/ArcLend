import { Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { ConfigModule, ConfigService } from '@nestjs/config';

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
      name: 'health-factor-updates',
    }),
  ],
  exports: [BullModule],
})
export class QueueModule {}
