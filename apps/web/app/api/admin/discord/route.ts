import { DomainError, getSettings, postLog, updateSetting } from "@vk/core";
import { flashRedirect, requireAdmin, text } from "@/lib/admin";
import { getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";

/** Mode d'application des rôles Discord. Passer en réel demande une confirmation explicite. */
export async function POST(request: Request) {
  const admin = await requireAdmin(request);
  if (admin instanceof Response) return admin;
  const form = await request.formData();
  const deps = getDeps();
  const mode = form.get("mode") === "live" ? "live" : "observe";
  const testUserIds = (text(form, "testUserIds") ?? "")
    .split(/[\s,;]+/)
    .map((s) => s.trim())
    .filter(Boolean);
  const before = (await getSettings(deps.db)).discordSync;
  if (mode === "live" && before.mode !== "live" && text(form, "confirm") !== "ACTIVER") {
    return flashRedirect("/admin/discord", "error", "Pour appliquer réellement les rôles, tape ACTIVER dans la case de confirmation.");
  }
  try {
    await updateSetting(deps.db, "discordSync", { mode, testUserIds }, admin.discordUserId, deps.now());
    if (before.mode !== mode) {
      await postLog(
        deps.db,
        mode === "live"
          ? `🔓 <@${admin.discordUserId}> a activé l'application réelle des rôles Discord.`
          : `🧪 <@${admin.discordUserId}> a remis Discord en mode observation (aucun rôle modifié).`,
      );
    }
    return flashRedirect("/admin/discord", "ok", mode === "live" ? "Rôles appliqués réellement à partir de maintenant." : "Mode observation enregistré.");
  } catch (error) {
    return flashRedirect("/admin/discord", "error", error instanceof DomainError ? error.message : "Enregistrement impossible");
  }
}
