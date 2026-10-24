import { importMembers } from "@vk/core";
import { requireAdmin } from "@/lib/admin";
import { getDeps } from "@/lib/server";
import { parseMembersCsv } from "@/lib/csv";

export const dynamic = "force-dynamic";

/** Import réel : le fichier est revérifié côté serveur (l'aperçu du navigateur n'est jamais pris pour acquis). */
export async function POST(request: Request) {
  const admin = await requireAdmin(request);
  if (admin instanceof Response) return admin;
  const { csv, confirm } = (await request.json()) as { csv?: string; confirm?: boolean };
  if (!csv || csv.length > 1_000_000 || confirm !== true) return Response.json({ error: "Confirmation manquante" }, { status: 400 });
  const report = await importMembers(getDeps(), parseMembersCsv(csv), { adminId: admin.discordUserId });
  return Response.json(report);
}
