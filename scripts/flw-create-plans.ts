/**
 * Crée chez Flutterwave les plans récurrents (renouvellement automatique par carte) des 3 formules,
 * avec les prix XOF de packages/core/src/config/club.ts, puis affiche les lignes à copier dans .env.
 *
 *   pnpm flw:create-plans            → affiche ce qui serait créé
 *   pnpm flw:create-plans --apply    → crée les plans (clé de test = sandbox)
 *
 * ⚠️ Si tu changes un prix, crée de nouveaux plans : un plan existant garde son montant.
 */
import { loadEnv, PLANS, requestJson, required } from "@vk/core";

const INTERVAL: Record<number, string> = { 1: "monthly", 3: "quarterly", 12: "yearly" };
const apply = process.argv.includes("--apply");
const env = loadEnv();

for (const plan of Object.values(PLANS)) {
  const body = { name: `V_ICT_ORIOUS Live Club · ${plan.label}`, amount: plan.priceXof, currency: "XOF", interval: INTERVAL[plan.months] };
  if (!apply) {
    console.log("À créer :", JSON.stringify(body));
    continue;
  }
  const { data } = await requestJson<{ data?: { id: number } }>("Flutterwave", `${env.FLW_API_BASE_URL}/v3/payment-plans`, {
    method: "POST",
    headers: { authorization: `Bearer ${required(env, "FLW_SECRET_KEY")}` },
    body,
  });
  console.log(`FLW_PLAN_ID_${plan.id.toUpperCase()}=${data.data?.id}`);
}
if (!apply) console.log("\nRelance avec --apply pour créer les plans.");
