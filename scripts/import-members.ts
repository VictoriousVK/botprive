/**
 * Import des membres actuels sans leur faire repayer (même contrôle que /admin/import).
 *
 *   pnpm import:members chemin/membres.csv            → aperçu détaillé (rien n'est écrit)
 *   pnpm import:members chemin/membres.csv --apply    → import réel
 *
 * Colonnes : discord_user_id, nom, email, téléphone, formule, date_de_fin
 * (séparateur « , » ou « ; », dates AAAA-MM-JJ ou JJ/MM/AAAA, formules mensuel/trimestriel/annuel)
 * Les rôles Discord suivent ensuite le mode choisi dans le tableau de bord (observation par défaut).
 */
import { readFileSync } from "node:fs";
import { parse } from "csv-parse/sync";
import { consoleLogger, formatDate, importMembers, loadEnv, normalizeHeader, previewImport, required, type ImportRow } from "@vk/core";
import { createDb } from "@vk/db";

const file = process.argv[2];
const apply = process.argv.includes("--apply");
if (!file) {
  console.error("Usage : pnpm import:members <fichier.csv> [--apply]");
  process.exit(1);
}

const raw = readFileSync(file, "utf8");
const delimiter = (raw.split(/\r?\n/)[0] ?? "").includes(";") ? ";" : ",";
const rows = parse(raw, { columns: (headers: string[]) => headers.map(normalizeHeader), delimiter, bom: true, skip_empty_lines: true, trim: true }) as ImportRow[];

const env = loadEnv();
const { db, close } = createDb(required(env, "DATABASE_URL"), { max: 2 });
const deps = { db, now: () => new Date() };
try {
  const preview = await previewImport(deps, rows);
  const mark = { ok: "✓", warning: "!", error: "✗", skip: "·" } as const;
  for (const r of preview.rows) {
    console.log(
      `${mark[r.level]} ligne ${r.line} · ${r.discordUserId || "?"} · ${r.planId ?? "?"} · ${r.endDate ? formatDate(r.endDate) : "?"} → ${r.resultingStatus ?? "—"}${r.messages.length ? ` · ${r.messages.join(" ; ")}` : ""}`,
    );
  }
  const s = preview.summary;
  console.log(`\n${s.total} ligne(s) : ${s.importable} importable(s) (dont ${s.warnings} à vérifier), ${s.errors} rejetée(s), ${s.skipped} déjà enregistrée(s).`);
  if (!apply) {
    console.log("Rien n'a été écrit. Relance avec --apply pour importer.");
  } else {
    const report = await importMembers(deps, rows, { adminId: "import-csv" });
    console.log(`Import : ${report.created} membre(s) importé(s), ${report.skipped} ignoré(s).`);
  }
} catch (error) {
  consoleLogger.error(String(error));
  process.exitCode = 1;
} finally {
  await close();
}
