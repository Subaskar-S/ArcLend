import winston from "winston";

const { combine, timestamp, printf, colorize, errors } = winston.format;

const LOG_LEVEL = process.env.LOG_LEVEL || "info";

const logFormat = printf(({ level, message, timestamp: ts, service, stack }) => {
    const svc = service ? `[${service}]` : "";
    const err = stack ? `\n${stack}` : "";
    return `${ts} ${level} ${svc}: ${message}${err}`;
});

/**
 * Create a named winston logger for a service or module.
 *
 * @param service  Short name shown in log output, e.g. "LiquidationExecutor"
 */
export function createLogger(service: string): winston.Logger {
    return winston.createLogger({
        level: LOG_LEVEL,
        defaultMeta: { service },
        format: combine(
            errors({ stack: true }),
            timestamp({ format: "YYYY-MM-DD HH:mm:ss" }),
            colorize({ all: true }),
            logFormat,
        ),
        transports: [
            new winston.transports.Console(),
        ],
    });
}

/** Root logger for top-level main.ts use */
export const logger = createLogger("liquidation-bot");
