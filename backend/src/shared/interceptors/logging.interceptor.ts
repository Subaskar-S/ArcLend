import { Injectable, NestInterceptor, ExecutionContext, CallHandler, Logger } from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';
import { v4 as uuidv4 } from 'uuid';

@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  private readonly logger = new Logger(LoggingInterceptor.name);

  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const req = context.switchToHttp().getRequest();
    const method = req.method;
    const url = req.url;
    const correlationId = req.headers['x-correlation-id'] || uuidv4();
    const now = Date.now();

    this.logger.log(`[${correlationId}] Incoming Request: ${method} ${url}`);

    return next
      .handle()
      .pipe(
        tap(() =>
          this.logger.log(`[${correlationId}] Outgoing Response: ${method} ${url} - ${Date.now() - now}ms`)
        ),
      );
  }
}
