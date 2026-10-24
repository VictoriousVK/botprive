// Copie les affiches de assets/affiches/ vers apps/web/public/affiches/ (lancé avant dev et build du site).
import { copyFileSync, existsSync, mkdirSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const source = path.join(root, "assets", "affiches");
const target = path.join(root, "apps", "web", "public", "affiches");
const ALLOWED = new Set([".jpg", ".jpeg", ".png", ".webp"]);
const MAX_BYTES = 5 * 1024 * 1024;

rmSync(target, { recursive: true, force: true });
mkdirSync(target, { recursive: true });
const files = existsSync(source)
  ? readdirSync(source)
      .filter((f) => ALLOWED.has(path.extname(f).toLowerCase()))
      .filter((f) => {
        const size = statSync(path.join(source, f)).size;
        if (size > MAX_BYTES) console.warn(`Affiche ignorée (plus de 5 Mo) : ${f}`);
        return size <= MAX_BYTES;
      })
      .sort()
  : [];
for (const f of files) copyFileSync(path.join(source, f), path.join(target, f));
writeFileSync(path.join(target, "manifest.json"), JSON.stringify(files));
console.log(files.length ? `Affiches : ${files.length} fichier(s) copié(s)` : "Affiches : aucun fichier dans assets/affiches/");
