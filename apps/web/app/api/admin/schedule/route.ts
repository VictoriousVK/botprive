import { DomainError, updateSetting, WEEK_DAYS } from "@vk/core";
import { checked, flashRedirect, requireAdmin, text } from "@/lib/admin";
import { getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const admin = await requireAdmin(request);
  if (admin instanceof Response) return admin;
  const form = await request.formData();
  const deps = getDeps();
  const days = WEEK_DAYS.filter((d) => checked(form, `${d.day}.enabled`)).map((d) => ({ day: d.day, time: text(form, `${d.day}.time`) }));
  try {
    await updateSetting(deps.db, "schedule", { days, format: text(form, "format") ?? "Live · Q&A · Débrief", note: text(form, "note") }, admin.discordUserId, deps.now());
    return flashRedirect("/admin/lives", "ok", "Horaires enregistrés : ils apparaissent sur le site et dans les messages.");
  } catch (error) {
    return flashRedirect("/admin/lives", "error", error instanceof DomainError ? error.message : "Enregistrement impossible");
  }
}
