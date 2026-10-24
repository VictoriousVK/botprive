import { getCatalog, getSettings, isPlanId, updatePlans } from "@vk/core";
import { flashRedirect, requireAdmin } from "@/lib/admin";
import { getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";

/** Crée chez Flutterwave le plan récurrent d'une formule, au prix actuel, et l'y rattache. */
export async function POST(request: Request) {
  const admin = await requireAdmin(request);
  if (admin instanceof Response) return admin;
  const form = await request.formData();
  const planId = String(form.get("plan") ?? "");
  const deps = getDeps();
  if (!isPlanId(planId)) return flashRedirect("/admin/tarifs", "error", "Formule inconnue");
  if (!deps.providers.has("flutterwave")) return flashRedirect("/admin/tarifs", "error", "Flutterwave n'est pas configuré (clés dans .env).");
  const plan = (await getCatalog(deps.db)).plans[planId];
  if (plan.priceXof === null) return flashRedirect("/admin/tarifs", "error", "Définis d'abord le prix FCFA de cette formule.");
  try {
    const provider = deps.providers.get("flutterwave");
    const id = await provider.createRecurringPlan!({ name: `V_ICT_ORIOUS Live Club · ${plan.label}`, amount: plan.priceXof, months: plan.months, currency: "XOF" });
    const plans = (await getSettings(deps.db)).plans;
    await updatePlans(deps.db, { ...plans, [planId]: { ...plans[planId], flutterwavePlanId: id } }, admin.discordUserId, deps.now());
    return flashRedirect("/admin/tarifs", "ok", `Plan Flutterwave ${id} créé pour ${plan.label} (${plan.priceXof} FCFA${provider.testMode ? ", mode test" : ""}).`);
  } catch (error) {
    deps.logger.error(`Création du plan Flutterwave : ${error instanceof Error ? error.message : String(error)}`);
    return flashRedirect("/admin/tarifs", "error", `Flutterwave a refusé la création du plan : ${error instanceof Error ? error.message : "erreur"}`);
  }
}
