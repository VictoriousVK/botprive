import postgres from "postgres";
import { runMigrations } from "./migrate";

const url = process.env.DATABASE_URL;
if (!url) {
  console.error("DATABASE_URL manquant : lance d'abord pnpm setup:demo (ou complète le fichier .env).");
  process.exit(1);
}

/** En local, crée la base si elle n'existe pas encore (PostgreSQL installé sans Docker). */
async function createDatabaseIfMissing(databaseUrl: string): Promise<void> {
  const target = postgres(databaseUrl, { max: 1, onnotice: () => {} });
  try {
    await target`select 1`;
    return;
  } catch (error) {
    if ((error as { code?: string }).code !== "3D000") throw error;
  } finally {
    await target.end({ timeout: 5 });
  }
  const name = decodeURIComponent(new URL(databaseUrl).pathname.slice(1));
  const serverUrl = new URL(databaseUrl);
  serverUrl.pathname = "/postgres";
  const server = postgres(serverUrl.toString(), { max: 1, onnotice: () => {} });
  try {
    await server`create database ${server(name)}`;
    console.log(`Base « ${name} » créée.`);
  } finally {
    await server.end({ timeout: 5 });
  }
}

function explain(error: unknown): string {
  const { code, message } = error as { code?: string; message?: string };
  const where = new URL(url!).host;
  if (code === "ECONNREFUSED")
    return `PostgreSQL ne répond pas sur ${where}. Démarre la base : « docker compose up -d db », ou le service PostgreSQL si tu l'as installé sans Docker.`;
  if (code === "28P01") return "Mot de passe PostgreSQL refusé : vérifie DATABASE_URL dans le fichier .env.";
  if (code === "28000") return "Utilisateur PostgreSQL inconnu : vérifie DATABASE_URL dans le fichier .env.";
  return message ?? String(error);
}

try {
  if (process.env.NODE_ENV !== "production") await createDatabaseIfMissing(url);
  await runMigrations(url);
  console.log("Migrations appliquées.");
} catch (error) {
  console.error(`Échec des migrations : ${explain(error)}`);
  process.exit(1);
}
