import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import * as request from 'supertest';
import { AppModule } from './../src/app.module';

describe('AppController (e2e)', () => {
  let app: INestApplication;

  beforeEach(async () => {
    // Note: This relies on the DB being available via docker-compose
    // If running in CI without a DB, this setup would need DB mocking
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  it('/api/v1/health (GET)', () => {
    return request(app.getHttpServer())
      .get('/api/v1/health')
      .expect(200)
      .expect((res) => {
        expect(res.body).toHaveProperty('status', 'ok');
        expect(res.body).toHaveProperty('timestamp');
        expect(res.body).toHaveProperty('db', 'connected'); // Example, depending on actual HealthController return
      });
  });

  // Example of how e2e tests would hit the markets endpoint
  // it('/api/v1/markets (GET)', () => {
  //   return request(app.getHttpServer())
  //     .get('/api/v1/markets')
  //     .expect(200);
  // });
});
