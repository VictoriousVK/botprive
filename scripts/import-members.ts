/**
 * Import des membres actuels sans leur faire repayer.
 *
 *   pnpm import:members chemin/membres.csv            → simulation (rien n'est écrit)
 *   pnpm import:members chemin/membres.csv --apply    → import réel
 *
 * Colonnes : discord_user_id, nom, email, téléphone, formule, date_de_fin
 * (séparateur « , » ou « ; », dates AAAA-MM-JJ ou JJ/MM/AAAA, formules mensuel/trimestriel/annuel)
 */
import { readFileSync } from "node:fs";
import { parse } from "csv-parse/sync";
import { consoleLogger, importMembers, loadEnv, required, type ImportRow } from "@vk/core";
import { createDb } from "@vk/db";

const file = process.argv[2];
const apply = process.argv.includes("--apply");
if (!file) {
  console.error("Usage : pnpm import:members <fichier.csv> [--apply]");
  process.exit(1);
}

const raw = readFileSync(file, "utf8");
const delimiter = (raw.split(/\r?\n/)[0] ?? "").includes(";") ? ";" : ",";
const normalizeHeader = (h: string) =>
  h.trim().toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/\s+/g, "_");
const rows = parse(raw, { columns: (headers: string[]) => headers.map(normalizeHeader), delimiter, bom: true, skip_empty_lines: true, trim: true }) as ImportRow[];

const env = loadEnv();
const { db, close } = createDb(required(env, "DATABASE_URL"), { max: 2 });
try {
  const report = await importMembers({ db, now: () => new Date() }, rows, { dryRun: !apply, adminId: "import-csv" });
  console.log(`${apply ? "Import" : "Simulation"} : ${rows.length} ligne(s) lue(s)`);
  console.log(`  ${apply ? "importé(s)" : "à importer"} : ${report.created}`);
  if (apply) console.log(`  déjà présent(s), ignoré(s) : ${report.skipped}`);
  for (const e of report.errors) console.log(`  ✗ ligne ${e.line} : ${e.message}`);
  if (!apply) console.log("\nRien n'a été écrit. Relance avec --apply pour importer.");
  else console.log("\nLe worker attribuera les rôles Discord dans les minutes qui suivent.");
} catch (error) {
  consoleLogger.error(String(error));
  process.exitCode = 1;
} finally {
  await close();
}
