import postgres from "postgres";
import { createDb, runMigrations, type Db } from "@vk/db";

export interface TestDatabase {
  db: Db;
  url: string;
  destroy(): Promise<void>;
}

/**
 * Base Postgres jetable : créée, migrée, puis supprimée.
 * TEST_DATABASE_URL pointe vers un serveur où l'on peut créer des bases (docker compose up -d db).
 */
export async function createTestDatabase(): Promise<TestDatabase> {
  const adminUrl = process.env.TEST_DATABASE_URL ?? "postgres://postgres:postgres@localhost:5432/postgres";
  const name = `vk_test_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
  const admin = postgres(adminUrl, { max: 1, onnotice: () => {} });
  await admin.unsafe(`CREATE DATABASE "${name}"`);
  const url = new URL(adminUrl);
  url.pathname = `/${name}`;
  await runMigrations(url.toString());
  const handle = createDb(url.toString(), { max: 5 });
  return {
    db: handle.db,
    url: url.toString(),
    async destroy() {
      await handle.close();
      await admin.unsafe(`DROP DATABASE IF EXISTS "${name}" WITH (FORCE)`);
      await admin.end({ timeout: 5 });
    },
  };
}
