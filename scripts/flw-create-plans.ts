/**
 * Crée chez Flutterwave les plans récurrents (renouvellement automatique par carte) des formules
 * dont le prix FCFA est défini dans le tableau de bord, puis les rattache aux formules.
 * Équivalent du bouton « Créer le plan » de /admin/tarifs.
 *
 *   pnpm flw:create-plans            → affiche ce qui serait créé
 *   pnpm flw:create-plans --apply    → crée les plans (clé de test = sandbox) et les enregistre
 */
import { createProviderRegistry, consoleLogger, getCatalog, getSettings, loadEnv, required, updatePlans } from "@vk/core";
import { createDb } from "@vk/db";

const apply = process.argv.includes("--apply");
const env = loadEnv();
const { db, close } = createDb(required(env, "DATABASE_URL"), { max: 1 });
try {
  const registry = createProviderRegistry(env, undefined, consoleLogger);
  if (!registry.has("flutterwave")) throw new Error("Flutterwave n'est pas configuré ou a été écarté (voir les avertissements ci-dessus)");
  const provider = registry.get("flutterwave");
  const catalog = await getCatalog(db);
  const todo = catalog.list.filter((p) => p.priceXof !== null && !p.flutterwavePlanId);
  if (todo.length === 0) console.log("Rien à créer : chaque formule a un prix et un plan, ou n'a pas encore de prix.");
  for (const plan of todo) {
    const label = `${plan.label} · ${plan.priceXof} FCFA · tous les ${plan.months} mois`;
    if (!apply) {
      console.log(`À créer : ${label}`);
      continue;
    }
    const id = await provider.createRecurringPlan!({ name: `V_ICT_ORIOUS Live Club · ${plan.label}`, amount: plan.priceXof!, months: plan.months, currency: "XOF" });
    const plans = (await getSettings(db)).plans;
    await updatePlans(db, { ...plans, [plan.id]: { ...plans[plan.id], flutterwavePlanId: id } }, "script-flw-create-plans");
    console.log(`Créé : ${label} → plan ${id}${provider.testMode ? " (test)" : ""}`);
  }
  if (!apply && todo.length) console.log("\nRelance avec --apply pour créer et rattacher les plans.");
} finally {
  await close();
}
