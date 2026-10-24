import {
  createJobHandlers,
  createProviderRegistry,
  handleWebhook,
  JobRunner,
  loadEnv,
  silentLogger,
  startCheckout,
  upsertMember,
  type AccessPolicy,
  type PlanId,
  type WorkerDeps,
} from "../src";
import { createTestDatabase, FakeDiscord, MemoryEmailSender, MockProviders, TestClock, type WebhookDelivery } from "../src/testing";

export const ROLE_MEMBER = "100000000000000001";
export const ROLE_ADMIN = "100000000000000002";
export const ROLE_MOD = "100000000000000003";
export const ADMIN_USER = "200000000000000001";

let seq = 0;
/** Identifiant Discord factice unique (17+ chiffres). */
export function discordId(): string {
  seq++;
  return `3000000000000${String(seq).padStart(5, "0")}`;
}

export async function setup(start = "2026-11-12T10:00:00Z") {
  const testDb = await createTestDatabase();
  const clock = new TestClock(start);
  const mock = new MockProviders({
    flwSecretKey: "FLWSECK_TEST-mock",
    flwWebhookHash: "flw-webhook-hash-test",
    waveApiKey: "wave_sn_test_mock",
    waveWebhookSecret: "wave_sn_WHS_test",
    now: clock.now,
  });
  await mock.start();
  const env = loadEnv({
    NODE_ENV: "test",
    APP_URL: "https://club.test",
    SESSION_SECRET: "s".repeat(40),
    PAYMENT_PROVIDER_CARD: "flutterwave",
    PAYMENT_PROVIDER_MOBILE_MONEY: "wave",
    FLW_SECRET_KEY: "FLWSECK_TEST-mock",
    FLW_WEBHOOK_HASH: "flw-webhook-hash-test",
    FLW_API_BASE_URL: mock.baseUrl,
    FLW_PLAN_ID_MONTHLY: "111",
    FLW_PLAN_ID_QUARTERLY: "222",
    FLW_PLAN_ID_ANNUAL: "333",
    WAVE_API_KEY: "wave_sn_test_mock",
    WAVE_WEBHOOK_SECRET: "wave_sn_WHS_test",
    WAVE_API_BASE_URL: mock.baseUrl,
  });
  const discord = new FakeDiscord();
  const email = new MemoryEmailSender();
  const policy: AccessPolicy = {
    memberRoleId: ROLE_MEMBER,
    exemptUserIds: [ADMIN_USER],
    exemptRoleIds: [ROLE_ADMIN, ROLE_MOD],
    expiryAction: "remove_role",
  };
  const deps: WorkerDeps = {
    db: testDb.db,
    env,
    now: clock.now,
    logger: silentLogger,
    providers: createProviderRegistry(env),
    discord,
    email,
    policy,
  };
  const runner = new JobRunner(testDb.db, createJobHandlers(deps), { workerId: "test-worker", logger: silentLogger, now: clock.now, concurrency: 20 });

  const ctx = {
    db: testDb.db,
    deps,
    clock,
    mock,
    discord,
    email,
    runner,
    /** Livre un webhook à l'application (comme le ferait le prestataire). */
    deliver: (delivery: WebhookDelivery) => handleWebhook(deps, delivery.provider, { headers: delivery.headers, rawBody: delivery.rawBody }),
    /** Crée un membre (connexion Discord) et le place sur le serveur public. */
    async member(options: { email?: string; inGuild?: boolean } = {}) {
      const id = discordId();
      const m = await upsertMember(testDb.db, { discordUserId: id, username: `user${id.slice(-4)}`, email: options.email ?? `${id}@exemple.sn`, emailVerified: true }, clock.now());
      if (options.inGuild !== false) discord.join(id);
      return m;
    },
    /** Tunnel complet Mobile Money (Wave) : checkout → paiement → webhook → tâches. */
    async payWave(memberId: string, planId: PlanId = "monthly") {
      const checkout = await startCheckout(deps, { memberId, planId, method: "mobile_money", autoRenew: false, autoRenewConsent: false });
      const delivery = mock.pay("wave", checkout.reference);
      const res = await ctx.deliver(delivery);
      await runner.drain();
      return { checkout, delivery, res };
    },
    /** Tunnel carte avec renouvellement automatique (Flutterwave payment plan). */
    async payCardAuto(memberId: string, planId: PlanId = "monthly") {
      const checkout = await startCheckout(deps, { memberId, planId, method: "card", autoRenew: true, autoRenewConsent: true });
      const delivery = mock.pay("flutterwave", checkout.reference);
      const res = await ctx.deliver(delivery);
      await runner.drain();
      return { checkout, delivery, res };
    },
    async teardown() {
      await mock.stop();
      await testDb.destroy();
    },
  };
  return ctx;
}

export type TestCtx = Awaited<ReturnType<typeof setup>>;
