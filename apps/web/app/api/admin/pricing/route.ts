import { DomainError, updateSetting, validatePricing } from "@vk/core";
import { checked, flashRedirect, requireAdmin } from "@/lib/admin";
import { getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";

/** Valide (ou annule la validation) des tarifs. Obligatoire pour encaisser en mode réel. */
export async function POST(request: Request) {
  const admin = await requireAdmin(request);
  if (admin instanceof Response) return admin;
  const form = await request.formData();
  const deps = getDeps();
  try {
    if (form.get("action") === "unvalidate") {
      await updateSetting(deps.db, "pricing", { validated: false, validatedAt: null, validatedBy: null }, admin.discordUserId, deps.now());
      return flashRedirect("/admin/tarifs", "ok", "Validation des tarifs annulée.");
    }
    if (!checked(form, "confirm")) return flashRedirect("/admin/tarifs", "error", "Coche la case de confirmation pour valider les tarifs.");
    await validatePricing(deps.db, admin.discordUserId, deps.now());
    return flashRedirect("/admin/tarifs", "ok", "Tarifs validés.");
  } catch (error) {
    return flashRedirect("/admin/tarifs", "error", error instanceof DomainError ? error.message : "Validation impossible");
  }
}
