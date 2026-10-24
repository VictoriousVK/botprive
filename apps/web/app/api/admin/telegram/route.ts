import { DomainError, updateSetting } from "@vk/core";
import { flashRedirect, requireAdmin, text } from "@/lib/admin";
import { getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const admin = await requireAdmin(request);
  if (admin instanceof Response) return admin;
  const form = await request.formData();
  const deps = getDeps();
  try {
    await updateSetting(
      deps.db,
      "telegram",
      { url: text(form, "url"), visibility: form.get("visibility") === "members" ? "members" : "public" },
      admin.discordUserId,
      deps.now(),
    );
    return flashRedirect("/admin/telegram", "ok", "Lien Telegram enregistré.");
  } catch (error) {
    return flashRedirect("/admin/telegram", "error", error instanceof DomainError ? error.message : "Enregistrement impossible");
  }
}
