/**
 * Simulation du cycle complet, en local, SANS vrai paiement ni vrai Discord :
 * faux prestataires (Wave + Flutterwave), faux Discord, horloge accélérée, vraie base Postgres jetable.
 *
 *   docker compose up -d db
 *   pnpm simulate
 *
 * Variable utile : TEST_DATABASE_URL (défaut postgres://postgres:postgres@localhost:5432/postgres).
 */
import {
  adminGrant,
  cancelRenewal,
  createJobHandlers,
  createProviderRegistry,
  formatDate,
  getSubscriptionForMember,
  handleWebhook,
  JobRunner,
  loadEnv,
  reconcile,
  runScheduledTick,
  signWavePayload,
  silentLogger,
  startCheckout,
  STATUS_LABELS,
  upsertMember,
  updateSetting,
  type SubscriptionStatus,
  type WorkerDeps,
} from "@vk/core";
import { createTestDatabase, FakeDiscord, MemoryEmailSender, MockProviders, TestClock, type WebhookDelivery } from "@vk/core/testing";

const ROLE = "100000000000000001";
const step = (title: string) => console.log(`\n\x1b[35m▌ ${title}\x1b[0m`);
const ok = (text: string) => console.log(`  \x1b[32m✓\x1b[0m ${text}`);
const info = (text: string) => console.log(`  \x1b[90m${text}\x1b[0m`);
let failures = 0;
const check = (condition: boolean, text: string) => {
  if (condition) ok(text);
  else {
    failures++;
    console.log(`  \x1b[31m✗ ${text}\x1b[0m`);
  }
};

const testDb = await createTestDatabase();
const clock = new TestClock("2026-11-12T10:00:00Z");
const mock = new MockProviders({ flwSecretKey: "FLWSECK_TEST-sim", flwWebhookHash: "sim-hash", waveApiKey: "wave_sn_sim", waveWebhookSecret: "wave_sim_secret", now: clock.now });
await mock.start();
const env = loadEnv({
  NODE_ENV: "development",
  APP_URL: "http://localhost:3000",
  SESSION_SECRET: "simulation-secret-".repeat(3),
  PAYMENT_PROVIDER_CARD: "flutterwave",
  PAYMENT_PROVIDER_MOBILE_MONEY: "wave",
  FLW_SECRET_KEY: "FLWSECK_TEST-sim",
  FLW_WEBHOOK_HASH: "sim-hash",
  FLW_API_BASE_URL: mock.baseUrl,
  WAVE_API_KEY: "wave_sn_sim",
  WAVE_WEBHOOK_SECRET: "wave_sim_secret",
  WAVE_API_BASE_URL: mock.baseUrl,
});
const discord = new FakeDiscord((log) => info(`[#logs] ${log.split("\n")[0]}`));
const deps: WorkerDeps = {
  db: testDb.db,
  env,
  now: clock.now,
  logger: silentLogger,
  providers: createProviderRegistry(env),
  discord,
  email: new MemoryEmailSender(),
  policy: { memberRoleId: ROLE, exemptUserIds: [], exemptRoleIds: [], expiryAction: "remove_role" },
};
// Réglages du tableau de bord pour la simulation : prix FICTIFS (aucun montant réel n'est décidé ici),
// plans Flutterwave du faux serveur, rôles appliqués (faux Discord).
await updateSetting(testDb.db, "plans", {
  monthly: { priceUsd: 85, priceXof: 50_000, badge: null, tagline: "Simulation", enabled: true, flutterwavePlanId: "111" },
  quarterly: { priceUsd: 200, priceXof: 115_000, badge: "Le + avantageux", tagline: "Simulation", enabled: true, flutterwavePlanId: "222" },
  annual: { priceUsd: 900, priceXof: 520_000, badge: null, tagline: "Simulation", enabled: true, flutterwavePlanId: "333" },
}, "simulation", clock.now());
await updateSetting(testDb.db, "discordSync", { mode: "live", testUserIds: [] }, "simulation", clock.now());
info("Prix utilisés : montants fictifs de simulation (50 000 / 115 000 / 520 000 FCFA), à remplacer par les tiens dans /admin/tarifs.");

const runner = new JobRunner(testDb.db, createJobHandlers(deps), { workerId: "simulation", logger: silentLogger, now: clock.now, concurrency: 20 });
const deliver = (d: WebhookDelivery) => handleWebhook(deps, d.provider, { headers: d.headers, rawBody: d.rawBody });
const statusOf = async (memberId: string) => (await getSubscriptionForMember(testDb.db, memberId))?.status as SubscriptionStatus;
const tick = async () => {
  await runScheduledTick(deps);
  await runner.drain();
};
const at = async (iso: string, label: string) => {
  clock.set(iso);
  await tick();
  info(`⏱  ${label} (${formatDate(clock.now())})`);
};

try {
  step("1. Awa se connecte avec Discord et paie le Mensuel par Wave");
  const awa = await upsertMember(testDb.db, { discordUserId: "300000000000000001", username: "awa", email: "awa@exemple.sn", emailVerified: true }, clock.now());
  discord.join(awa.discordUserId);
  const c1 = await startCheckout(deps, { memberId: awa.id, planId: "monthly", method: "mobile_money", autoRenew: false, autoRenewConsent: false });
  info(`Session Wave créée, référence ${c1.reference}`);
  const paid = mock.pay("wave", c1.reference);
  check((await statusOf(awa.id)) === "pending_payment", "retour navigateur seul : aucun accès (pas encore de webhook)");
  const r1 = await deliver(paid);
  await runner.drain();
  check(r1.httpStatus === 200 && (await statusOf(awa.id)) === "active", "webhook signé + vérification serveur → abonnement actif");
  check(discord.rolesOf(awa.discordUserId).includes(ROLE), "rôle Discord attribué automatiquement");
  info(`Accès jusqu'au ${formatDate((await getSubscriptionForMember(testDb.db, awa.id))!.currentPeriodEnd!)}`);

  step("2. Sécurité des webhooks");
  check((await deliver(paid)).body.duplicate === true, "même webhook reçu deux fois → ignoré (une seule prolongation)");
  const forgedBody = paid.rawBody.replace("EV_", "EV_forge_");
  check((await deliver({ provider: "wave", headers: { "wave-signature": signWavePayload(forgedBody, "mauvais-secret", clock.now()) }, rawBody: forgedBody })).httpStatus === 401, "webhook falsifié → 401");

  step("3. Rappels, grâce, retrait puis restauration");
  await at("2026-12-09T09:05:00Z", "J-3");
  check(discord.dms.some((d) => d.userId === awa.discordUserId && d.content.includes("/r/")), "rappel J-3 en message privé avec lien de paiement en 1 clic");
  await at("2026-12-11T09:05:00Z", "J-1");
  await at("2026-12-12T09:05:00Z", "J0");
  await at("2026-12-12T10:05:00Z", "échéance passée");
  check((await statusOf(awa.id)) === "grace_period", "période de grâce, accès conservé");
  await at("2026-12-15T10:05:00Z", "fin de grâce");
  check((await statusOf(awa.id)) === "expired", "abonnement expiré");
  check(!discord.rolesOf(awa.discordUserId).includes(ROLE) && discord.members.has(awa.discordUserId), "rôle retiré, Awa reste sur le serveur public");
  clock.set("2026-12-18T19:00:00Z");
  const c2 = await startCheckout(deps, { memberId: awa.id, planId: "quarterly", method: "mobile_money", autoRenew: false, autoRenewConsent: false });
  await deliver(mock.pay("wave", c2.reference));
  await runner.drain();
  check((await statusOf(awa.id)) === "active" && discord.rolesOf(awa.discordUserId).includes(ROLE), "elle repaie (Trimestriel) → accès restauré automatiquement");

  step("4. Moussa : carte avec renouvellement automatique");
  clock.set("2027-01-31T08:00:00Z");
  const moussa = await upsertMember(testDb.db, { discordUserId: "300000000000000002", username: "moussa", email: "moussa@exemple.sn", emailVerified: true }, clock.now());
  discord.join(moussa.discordUserId);
  const c3 = await startCheckout(deps, { memberId: moussa.id, planId: "monthly", method: "card", autoRenew: true, autoRenewConsent: true });
  await deliver(mock.pay("flutterwave", c3.reference));
  await runner.drain();
  let sub = await getSubscriptionForMember(testDb.db, moussa.id);
  check(sub?.renewalMode === "auto_card" && sub.currentPeriodEnd?.toISOString() === "2027-02-28T08:00:00.000Z", "activé le 31 janvier → échéance le 28 février (fin de mois)");
  await at("2027-02-25T09:05:00Z", "J-3 de Moussa");
  const lastDm = discord.dms.filter((d) => d.userId === moussa.discordUserId).at(-1)?.content ?? "";
  check(lastDm.includes("automatiquement par carte") && !lastDm.includes("/r/"), "rappel = simple avis de prélèvement, sans lien de paiement");
  clock.set("2027-02-28T08:10:00Z");
  await deliver(mock.chargeRecurring(Number(sub!.providerSubscriptionId)));
  await runner.drain();
  sub = await getSubscriptionForMember(testDb.db, moussa.id);
  check(sub?.currentPeriodEnd?.toISOString() === "2027-03-31T08:00:00.000Z", "prélèvement automatique reçu → prolongé jusqu'au 31 mars (ancrage retrouvé)");
  await cancelRenewal(deps, moussa.id, { type: "member", id: moussa.discordUserId });
  await runner.drain();
  check((await statusOf(moussa.id)) === "canceled" && discord.rolesOf(moussa.discordUserId).includes(ROLE), "annulation : prélèvement annulé chez Flutterwave, accès conservé jusqu'au 31 mars");

  step("5. Panne Discord pendant un paiement");
  const fatou = await upsertMember(testDb.db, { discordUserId: "300000000000000003", username: "fatou", email: "fatou@exemple.sn" }, clock.now());
  discord.join(fatou.discordUserId);
  discord.down = true;
  const c4 = await startCheckout(deps, { memberId: fatou.id, planId: "monthly", method: "mobile_money", autoRenew: false, autoRenewConsent: false });
  await deliver(mock.pay("wave", c4.reference));
  await runner.drain();
  check((await statusOf(fatou.id)) === "active" && !discord.rolesOf(fatou.discordUserId).includes(ROLE), "paiement enregistré, rôle en attente (Discord indisponible)");
  discord.down = false;
  clock.advanceMinutes(5);
  await runner.drain();
  check(discord.rolesOf(fatou.discordUserId).includes(ROLE), "Discord revenu → rôle attribué par les réessais");

  step("6. Paiement manuel (Wave perso) validé par l'admin, puis réconciliation");
  const ibou = await upsertMember(testDb.db, { discordUserId: "300000000000000004", username: "ibou" }, clock.now());
  discord.join(ibou.discordUserId);
  await adminGrant(deps, { discordUserId: ibou.discordUserId, days: 30, adminId: "200000000000000001", note: "Wave perso 50 000 FCFA" });
  await runner.drain();
  check(discord.rolesOf(ibou.discordUserId).includes(ROLE), "/ajouter : accès donné et journalisé");
  discord.join("399999999999999999", [ROLE]);
  const report = await reconcile(deps);
  check(report.roleRemoved.includes("399999999999999999"), "réconciliation : rôle sans abonnement retiré");

  console.log(failures === 0 ? "\n\x1b[32mSimulation terminée : tout le cycle fonctionne.\x1b[0m" : `\n\x1b[31m${failures} vérification(s) en échec.\x1b[0m`);
  process.exitCode = failures === 0 ? 0 : 1;
} finally {
  await mock.stop();
  await testDb.destroy();
}
