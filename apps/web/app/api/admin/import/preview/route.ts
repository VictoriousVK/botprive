import { previewImport, type ImportRow } from "@vk/core";
import { parseMembersCsv } from "@/lib/csv";
import { requireAdmin } from "@/lib/admin";
import { createDiscordPresenceCheck } from "@/lib/discord-check";
import { getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";

const MAX_BYTES = 1_000_000;

/** Aperçu : vérifie le fichier sans rien écrire (présence Discord en lecture seule). */
export async function POST(request: Request) {
  const admin = await requireAdmin(request);
  if (admin instanceof Response) return admin;
  const { csv } = (await request.json()) as { csv?: string };
  if (!csv || csv.length > MAX_BYTES) return Response.json({ error: "Fichier vide ou trop volumineux (1 Mo max)" }, { status: 400 });
  let rows: ImportRow[];
  try {
    rows = parseMembersCsv(csv);
  } catch (error) {
    return Response.json({ error: `CSV illisible : ${error instanceof Error ? error.message : String(error)}` }, { status: 400 });
  }
  if (rows.length > 2000) return Response.json({ error: "2 000 lignes maximum par import" }, { status: 400 });
  const missing = ["discord_user_id", "formule", "date_de_fin"].filter((h) => rows.length && !(h in rows[0]!));
  if (missing.length) return Response.json({ error: `Colonnes manquantes : ${missing.join(", ")}` }, { status: 400 });
  const preview = await previewImport(getDeps(), rows, { checkDiscord: createDiscordPresenceCheck() });
  return Response.json(preview);
}
