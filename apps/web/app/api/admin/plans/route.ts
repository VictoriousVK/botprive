import { DomainError, getSettings, PLAN_IDS, updatePlans } from "@vk/core";
import { checked, flashRedirect, int, requireAdmin, text } from "@/lib/admin";
import { getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";

/** Enregistre prix, textes et plans Flutterwave des 3 formules (sans les valider). */
export async function POST(request: Request) {
  const admin = await requireAdmin(request);
  if (admin instanceof Response) return admin;
  const form = await request.formData();
  const deps = getDeps();
  const current = (await getSettings(deps.db)).plans;
  const next = structuredClone(current);
  for (const id of PLAN_IDS) {
    next[id] = {
      enabled: checked(form, `${id}.enabled`),
      priceUsd: int(form, `${id}.priceUsd`),
      priceXof: int(form, `${id}.priceXof`),
      badge: text(form, `${id}.badge`),
      tagline: text(form, `${id}.tagline`) ?? "",
      flutterwavePlanId: text(form, `${id}.flutterwavePlanId`),
    };
  }
  try {
    await updatePlans(deps.db, next, admin.discordUserId, deps.now());
    return flashRedirect("/admin/tarifs", "ok", "Formules enregistrées. Pense à valider les tarifs avant tout encaissement réel.");
  } catch (error) {
    return flashRedirect("/admin/tarifs", "error", error instanceof DomainError ? error.message : "Enregistrement impossible");
  }
}
