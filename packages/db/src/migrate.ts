import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";

/**
 * Dossier des migrations SQL versionnées. MIGRATIONS_DIR permet de le forcer (image Docker) ;
 * sinon on le cherche à côté du code source ou depuis la racine du monorepo (code empaqueté).
 */
function findMigrationsFolder(): string {
  const candidates = [
    process.env.MIGRATIONS_DIR,
    path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../drizzle"),
    path.resolve(process.cwd(), "packages/db/drizzle"),
    path.resolve(process.cwd(), "../../packages/db/drizzle"),
  ].filter((c): c is string => !!c);
  return candidates.find((c) => existsSync(path.join(c, "meta/_journal.json"))) ?? candidates[0]!;
}

export const migrationsFolder = findMigrationsFolder();

// Verrou applicatif : deux instances qui démarrent en même temps ne migrent pas en parallèle.
const MIGRATION_LOCK_ID = 727_274_001;

/** Applique les migrations en attente (idempotent). */
export async function runMigrations(url: string, folder = migrationsFolder): Promise<void> {
  const client = postgres(url, { max: 1, onnotice: () => {} });
  try {
    await client`select pg_advisory_lock(${MIGRATION_LOCK_ID})`;
    await migrate(drizzle(client), { migrationsFolder: folder });
    await client`select pg_advisory_unlock(${MIGRATION_LOCK_ID})`;
  } finally {
    await client.end({ timeout: 5 });
  }
}
