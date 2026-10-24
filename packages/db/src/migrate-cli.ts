import { runMigrations } from "./migrate";

const url = process.env.DATABASE_URL;
if (!url) {
  console.error("DATABASE_URL manquant");
  process.exit(1);
}
await runMigrations(url);
console.log("Migrations appliquées.");
