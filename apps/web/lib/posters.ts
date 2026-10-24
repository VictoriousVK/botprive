import { readFileSync } from "node:fs";
import path from "node:path";

export interface Poster {
  src: string;
  alt: string;
}

/** Affiches copiées depuis assets/affiches/ au build (voir scripts/sync-posters.mjs). */
export function listPosters(): Poster[] {
  try {
    const files = JSON.parse(readFileSync(path.join(process.cwd(), "public", "affiches", "manifest.json"), "utf8")) as string[];
    return files.map((f) => ({
      src: `/affiches/${encodeURIComponent(f)}`,
      alt: `Affiche : ${f.replace(/\.[a-z]+$/i, "").replace(/^\d+[-_ ]*/, "").replace(/[-_]+/g, " ") || "V_ICT_ORIOUS Live Club"}`,
    }));
  } catch {
    return [];
  }
}
