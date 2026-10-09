// Copies the static export (out/) into the Python package, where the platform serves it.
import { cpSync, existsSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, "..", "out");
const dest = join(here, "..", "..", "..", "hedgefund", "web", "site");
if (!existsSync(join(out, "index.html"))) {
  console.error("out/index.html introuvable : lancez d'abord `npm run build`.");
  process.exit(1);
}
rmSync(dest, { recursive: true, force: true });
cpSync(out, dest, { recursive: true });
console.log(`Site publié dans ${dest}`);
