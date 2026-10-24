import { fileURLToPath } from "node:url";
import path from "node:path";
import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";

export const migrationsFolder = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../drizzle",
);

/** Applique les migrations SQL versionnées (dossier packages/db/drizzle). */
export async function runMigrations(url: string, folder = migrationsFolder): Promise<void> {
  const client = postgres(url, { max: 1, onnotice: () => {} });
  try {
    await migrate(drizzle(client), { migrationsFolder: folder });
  } finally {
    await client.end({ timeout: 5 });
  }
}
