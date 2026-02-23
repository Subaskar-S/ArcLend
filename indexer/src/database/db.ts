import { Pool } from "pg";
import * as dotenv from "dotenv";

dotenv.config();

/**
 * Singleton database connection pool for the Indexer.
 */
class DatabaseConnection {
    private static instance: Pool;

    private constructor() {}

    public static getInstance(): Pool {
        if (!DatabaseConnection.instance) {
            DatabaseConnection.instance = new Pool({
                host: process.env.DB_HOST || "localhost",
                port: parseInt(process.env.DB_PORT || "5432"),
                user: process.env.DB_USER || "postgres",
                password: process.env.DB_PASSWORD || "postgres",
                database: process.env.DB_NAME || "aave_lending",
            });
        }
        return DatabaseConnection.instance;
    }
}

export const dbPool = DatabaseConnection.getInstance();
