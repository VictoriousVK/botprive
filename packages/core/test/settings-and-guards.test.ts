import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { eq } from "drizzle-orm";
import { payments } from "@vk/db";
import {
  createProviderRegistry,
  DEFAULT_SETTINGS,
  getCatalog,
  getSettings,
  getSubscriptionForMember,
  loadEnv,
  previewImport,
  reconcile,
  seedSettingsFromEnv,
  startCheckout,
  telegramLinkFor,
  updatePlans,
  updateSetting,
  validatePricing,
} from "../src";
import { createTestDatabase } from "../src/testing";
import { discordId, ROLE_MEMBER, setup, TEST_PRICES, type TestCtx } from "./helpers";

describe("Réglages par défaut (aucun montant fixé dans le code)", () => {
  it("prix FCFA vides, tarifs non validés, Telegram public, Discord en observation", async () => {
    const db = await createTestDatabase();
    try {
      const s = await getSettings(db.db);
      expect(Object.values(s.plans).map((p) => p.priceXof)).toEqual([null, null, null]);
      expect(Object.values(s.plans).map((p) => p.priceUsd)).toEqual([85, 200, 900]);
      expect(s.pricing.validated).toBe(false);
      expect(s.telegram).toEqual({ url: null, visibility: "public" });
      expect(s.discordSync.mode).toBe("observe");
      expect(s.schedule.days.map((d) => d.day)).toEqual(["MAR", "MER", "VEN"]);
      const catalog = await getCatalog(db.db);
      expect(catalog.list.every((p) => !p.purchasable)).toBe(true);
    } finally {
      await db.destroy();
    }
  });

  it("lien Telegram initial repris de l'environnement une seule fois, sans écraser le tableau de bord", async () => {
    const db = await createTestDatabase();
    try {
      await seedSettingsFromEnv(db.db, { TELEGRAM_INVITE_URL: "https://t.me/+lienInitialTest" });
      expect((await getSettings(db.db)).telegram).toEqual({ url: "https://t.me/+lienInitialTest", visibility: "public" });
      await updateSetting(db.db, "telegram", { url: "https://t.me/+lienModifie", visibility: "members" }, "admin");
      await seedSettingsFromEnv(db.db, { TELEGRAM_INVITE_URL: "https://t.me/+lienInitialTest" });
      expect((await getSettings(db.db)).telegram).toEqual({ url: "https://t.me/+lienModifie", visibility: "members" });
    } finally {
      await db.destroy();
    }
  });

  it("lien Telegram : public pour tous, ou réservé aux membres actifs", () => {
    const pub = { ...structuredClone(DEFAULT_SETTINGS), telegram: { url: "https://t.me/+groupeTest", visibility: "public" as const } };
    expect(telegramLinkFor(pub, { hasAccess: false })).toBe("https://t.me/+groupeTest");
    const members = { ...pub, telegram: { ...pub.telegram, visibility: "members" as const } };
    expect(telegramLinkFor(members, { hasAccess: false })).toBeNull();
    expect(telegramLinkFor(members, { hasAccess: true })).toBe("https://t.me/+groupeTest");
  });
});

describe("Tarifs configurables depuis le tableau de bord", () => {
  let t: TestCtx;
  beforeAll(async () => {
    t = await setup("2026-11-12T10:00:00Z");
  });
  afterAll(async () => {
    await t.teardown();
  });

  it("une formule sans prix FCFA n'est pas achetable", async () => {
    const s = await getSettings(t.db);
    await updatePlans(t.db, { ...s.plans, annual: { ...s.plans.annual, priceXof: null } }, "admin");
    const m = await t.member();
    await expect(startCheckout(t.deps, { memberId: m.id, planId: "annual", method: "mobile_money", autoRenew: false, autoRenewConsent: false })).rejects.toThrow(/pas encore disponible/);
    await updatePlans(t.db, { ...s.plans }, "admin");
  });

  it("réglages invalides refusés avec un message clair", async () => {
    await expect(updateSetting(t.db, "telegram", { url: "https://evil.example/x", visibility: "public" }, "admin")).rejects.toThrow(/https:\/\/t\.me/);
    await expect(updateSetting(t.db, "discordSync", { mode: "live", testUserIds: ["123"] }, "admin")).rejects.toThrow();
  });

  it("validation : exige tous les prix, et un changement de prix annule la validation et détache le plan Flutterwave", async () => {
    await validatePricing(t.db, "admin");
    expect((await getSettings(t.db)).pricing.validated).toBe(true);
    const s = await getSettings(t.db);
    await updatePlans(t.db, { ...s.plans, monthly: { ...s.plans.monthly, priceXof: 60_000 } }, "admin");
    const after = await getSettings(t.db);
    expect(after.pricing.validated).toBe(false);
    expect(after.plans.monthly.flutterwavePlanId).toBeNull();
    expect(after.plans.quarterly.flutterwavePlanId).toBe("222");
    await updatePlans(t.db, { ...after.plans, monthly: { ...after.plans.monthly, priceXof: TEST_PRICES.monthly, flutterwavePlanId: "111" } }, "admin");
  });

  it("le prélèvement automatique garde le montant d'origine même si le prix change ensuite", async () => {
    const m = await t.member();
    await t.payCardAuto(m.id, "monthly");
    const sub = await getSubscriptionForMember(t.db, m.id);
    expect(sub?.recurringAmount).toBe(TEST_PRICES.monthly);
    const s = await getSettings(t.db);
    await updatePlans(t.db, { ...s.plans, monthly: { ...s.plans.monthly, priceXof: 70_000 } }, "admin");
    await t.deliver(t.mock.chargeRecurring(Number(sub!.providerSubscriptionId)));
    const rows = await t.db.select().from(payments).where(eq(payments.memberId, m.id));
    expect(rows.filter((p) => p.status === "succeeded").map((p) => p.amount)).toEqual([TEST_PRICES.monthly, TEST_PRICES.monthly]);
    await updatePlans(t.db, { ...s.plans }, "admin");
  });

  it("renouvellement auto refusé si aucun plan Flutterwave n'est rattaché à la formule", async () => {
    const s = await getSettings(t.db);
    await updatePlans(t.db, { ...s.plans, annual: { ...s.plans.annual, flutterwavePlanId: null } }, "admin");
    const m = await t.member();
    await expect(startCheckout(t.deps, { memberId: m.id, planId: "annual", method: "card", autoRenew: true, autoRenewConsent: true })).rejects.toThrow(/pas encore configuré/);
    await updatePlans(t.db, { ...s.plans }, "admin");
  });
});

describe("Mode test des paiements (aucun encaissement réel)", () => {
  it("en mode test, des clés ou adresses réelles sont écartées", () => {
    const env = loadEnv({
      NODE_ENV: "test",
      PAYMENT_MODE: "test",
      PAYMENT_PROVIDER_CARD: "flutterwave",
      PAYMENT_PROVIDER_MOBILE_MONEY: "wave",
      FLW_SECRET_KEY: "FLWSECK-0123456789abcdef-X",
      FLW_WEBHOOK_HASH: "h",
      WAVE_API_KEY: "wave_sn_prod_xxx",
      WAVE_WEBHOOK_SECRET: "s",
    });
    const registry = createProviderRegistry(env);
    expect(registry.forMethod("card")).toBeNull();
    expect(registry.forMethod("mobile_money")).toBeNull();
    expect(registry.disabled.map((d) => d.id).sort()).toEqual(["flutterwave", "wave"]);
  });

  it("en mode test, les clés de test Flutterwave sont acceptées", () => {
    const env = loadEnv({ NODE_ENV: "test", FLW_SECRET_KEY: "FLWSECK_TEST-abc-X", FLW_WEBHOOK_HASH: "h" });
    expect(createProviderRegistry(env).forMethod("card")?.id).toBe("flutterwave");
  });

  it("en mode live, un paiement est refusé tant que les tarifs ne sont pas validés", async () => {
    const t = await setup("2026-11-12T10:00:00Z");
    try {
      const m = await t.member();
      const liveDeps = { ...t.deps, env: { ...t.deps.env, PAYMENT_MODE: "live" as const } };
      await expect(startCheckout(liveDeps, { memberId: m.id, planId: "monthly", method: "mobile_money", autoRenew: false, autoRenewConsent: false })).rejects.toThrow(/pas encore été validés/);
      await validatePricing(t.db, "admin");
      await expect(startCheckout(liveDeps, { memberId: m.id, planId: "monthly", method: "mobile_money", autoRenew: false, autoRenewConsent: false })).resolves.toBeTruthy();
    } finally {
      await t.teardown();
    }
  });
});

describe("Mode observation Discord : aucun accès réel modifié sans autorisation", () => {
  let t: TestCtx;
  beforeAll(async () => {
    t = await setup("2026-11-12T10:00:00Z", { discordMode: "observe" });
  });
  afterAll(async () => {
    await t.teardown();
  });

  it("un paiement de test ne donne pas de rôle réel et n'envoie aucun message au membre", async () => {
    const m = await t.member();
    await t.payWave(m.id);
    expect((await getSubscriptionForMember(t.db, m.id))?.status).toBe("active");
    expect(t.discord.rolesOf(m.discordUserId)).not.toContain(ROLE_MEMBER);
    expect(t.discord.dms.filter((d) => d.userId === m.discordUserId)).toHaveLength(0);
    expect(t.email.sent.filter((e) => e.to === m.email)).toHaveLength(0);
    expect(t.discord.logs.some((l) => l.includes("Mode observation") && l.includes(m.discordUserId))).toBe(true);
  });

  it("les comptes de test reçoivent les actions réelles", async () => {
    const tester = await t.member();
    await updateSetting(t.db, "discordSync", { mode: "observe", testUserIds: [tester.discordUserId] }, "admin");
    await t.payWave(tester.id);
    expect(t.discord.rolesOf(tester.discordUserId)).toContain(ROLE_MEMBER);
    expect(t.discord.dms.some((d) => d.userId === tester.discordUserId)).toBe(true);
  });

  it("la réconciliation ne retire aucun rôle existant : elle liste ce qu'elle aurait fait", async () => {
    const existingMember = discordId();
    t.discord.join(existingMember, [ROLE_MEMBER]); // membre actuel, pas encore importé
    const report = await reconcile(t.deps);
    await t.runner.drain();
    expect(report.mode).toBe("observe");
    expect(report.simulatedRemovals).toContain(existingMember);
    expect(report.roleRemoved).not.toContain(existingMember);
    expect(t.discord.rolesOf(existingMember)).toContain(ROLE_MEMBER);
    expect(t.discord.logs.some((l) => l.includes("mode observation") && l.includes("Retraits qui auraient eu lieu : "))).toBe(true);
  });

  it("après autorisation (mode live), la synchronisation s'applique", async () => {
    const m = await t.member();
    await t.payWave(m.id);
    expect(t.discord.rolesOf(m.discordUserId)).not.toContain(ROLE_MEMBER);
    await updateSetting(t.db, "discordSync", { mode: "live", testUserIds: [] }, "admin");
    const report = await reconcile(t.deps);
    await t.runner.drain();
    expect(report.roleGranted).toContain(m.discordUserId);
    expect(t.discord.rolesOf(m.discordUserId)).toContain(ROLE_MEMBER);
  });
});

describe("Aperçu de l'import CSV", () => {
  it("vérifie identifiants, formules, dates, doublons, présence Discord et membres déjà enregistrés", async () => {
    const t = await setup("2026-11-20T10:00:00Z");
    try {
      const present = discordId();
      const absent = discordId();
      const known = await t.member();
      await t.payWave(known.id);
      const preview = await previewImport(
        t.deps,
        [
          { discord_user_id: present, nom: "Awa", email: "awa@exemple.sn", telephone: "+221 77 000 00 01", formule: "Mensuel", date_de_fin: "2026-12-15" },
          { discord_user_id: absent, nom: "Moussa", email: "", telephone: "", formule: "Trimestriel", date_de_fin: "2026-11-01" },
          { discord_user_id: known.discordUserId, nom: "Déjà", email: "", telephone: "", formule: "Mensuel", date_de_fin: "2026-12-01" },
          { discord_user_id: present, nom: "Doublon", email: "", telephone: "", formule: "Mensuel", date_de_fin: "2026-12-01" },
          { discord_user_id: "12ab", nom: "Erreur", email: "pas-un-email", telephone: "", formule: "semaine", date_de_fin: "2026-13-01" },
        ],
        { checkDiscord: async (id) => (id === present ? "present" : "absent") },
      );
      const [a, b, c, d, e] = preview.rows;
      expect(a).toMatchObject({ level: "ok", discord: "present", resultingStatus: "active" });
      expect(b?.level).toBe("warning");
      expect(b?.resultingStatus).toBe("expired");
      expect(b?.messages.join(" ")).toMatch(/absent du serveur/);
      expect(b?.messages.join(" ")).toMatch(/pas d'email/);
      expect(c?.level).toBe("skip");
      expect(d?.level).toBe("error");
      expect(e?.level).toBe("error");
      expect(e?.messages).toHaveLength(4);
      expect(preview.summary).toEqual({ total: 5, importable: 2, warnings: 1, errors: 2, skipped: 1 });
    } finally {
      await t.teardown();
    }
  });
});
