import { parse } from "csv-parse/sync";
import { normalizeHeader, type ImportRow } from "@vk/core";

/** CSV des membres : séparateur « , » ou « ; », en-têtes tolérants (accents, majuscules, espaces). */
export function parseMembersCsv(raw: string): ImportRow[] {
  const delimiter = (raw.split(/\r?\n/)[0] ?? "").includes(";") ? ";" : ",";
  return parse(raw, { columns: (headers: string[]) => headers.map(normalizeHeader), delimiter, bom: true, skip_empty_lines: true, trim: true }) as ImportRow[];
}
