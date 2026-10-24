import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { eq } from "drizzle-orm";
import { payments, subscriptions } from "@vk/db";
import {
  adminGrant,
  createRenewalToken,
  createSession,
  getMemberDashboard,
  getPaymentForMember,
  getSessionMember,
  getSubscriptionForMember,
  importMembers,
  reconcile,
  startCheckout,
  verifyRenewalToken,
  verifyState,
  signState,
} from "../src";
import { ADMIN_USER, discordId, ROLE_ADMIN, ROLE_MEMBER, ROLE_MOD, setup, type TestCtx } from "./helpers";

let t: TestCtx;
beforeAll(async () => {
  t = await setup("2026-11-12T10:00:00Z");
});
afterAll(async () => {
  await t.teardown();
});

describe("Accès à l'espace d'un autre membre refusé (test 7)", () => {
  it("un membre ne peut pas lire le paiement ni le tableau de bord d'un autre", async () => {
    const alice = await t.member();
    const bob = await t.member();
    const { checkout } = await t.payWave(alice.id);

    expect(await getPaymentForMember(t.deps, alice.id, checkout.reference)).not.toBeNull();
    expect(await getPaymentForMember(t.deps, bob.id, checkout.reference)).toBeNull();

    const bobView = await getMemberDashboard(t.db, bob.id);
    expect(bobView?.history.map((p) => p.reference)).not.toContain(checkout.reference);
  });

  it("session : jeton inconnu, falsifié ou expiré refusé", async () => {
    const alice = await t.member();
    const { token } = await createSession(t.db, alice.id, t.clock.now());
    expect((await getSessionMember(t.db, token, t.clock.now()))?.id).toBe(alice.id);
    expect(await getSessionMember(t.db, token.slice(0, -2) + "xx", t.clock.now())).toBeNull();
    expect(await getSessionMember(t.db, undefined, t.clock.now())).toBeNull();
    expect(await getSessionMember(t.db, token, new Date("2027-01-01T00:00:00Z"))).toBeNull();
  });

  it("lien de renouvellement : signé, limité dans le temps, non modifiable", () => {
    const secret = "x".repeat(40);
    const now = new Date("2026-11-12T10:00:00Z");
    const token = createRenewalToken(secret, "member-1", "monthly", now, 10);
    expect(verifyRenewalToken(secret, token, now)).toEqual({ memberId: "member-1", planId: "monthly" });
    expect(verifyRenewalToken(secret, token, new Date("2026-11-23T10:00:00Z"))).toBeNull();
    expect(verifyRenewalToken("autre-secret".repeat(4), token, now)).toBeNull();
    const [payload, sig] = token.split(".");
    const tampered = Buffer.from(Buffer.from(payload!, "base64url").toString().replace("member-1", "member-2")).toString("base64url");
    expect(verifyRenewalToken(secret, `${tampered}.${sig}`, now)).toBeNull();
  });

  it("state OAuth : refuse un nonce différent et les redirections externes", () => {
    const secret = "x".repeat(40);
    expect(verifyState(secret, signState(secret, "n1", "/inscription?plan=annual"), "n1")).toEqual({ next: "/inscription?plan=annual" });
    expect(verifyState(secret, signState(secret, "n1", "/espace"), "n2")).toBeNull();
    expect(verifyState(secret, signState(secret, "n1", "//evil.example"), "n1")).toEqual({ next: "/espace" });
    expect(verifyState(secret, signState(secret, "n1", "https://evil.example"), "n1")).toEqual({ next: "/espace" });
  });
});

describe("Réconciliation (test 8)", () => {
  it("rôle sans abonnement retiré, abonnement sans rôle réparé, exceptions respectées, paiement perdu récupéré", async () => {
    // Abonné légitime à qui le rôle a été retiré à la main.
    const legit = await t.member();
    await t.payWave(legit.id);
    t.discord.members.get(legit.discordUserId)!.roles = [];

    // Ancien membre expiré qui a encore le rôle.
    const stale = await t.member();
    await adminGrant(t.deps, { discordUserId: stale.discordUserId, days: 1, adminId: ADMIN_USER });
    await t.runner.drain();
    await t.db.update(subscriptions).set({ status: "expired" }).where(eq(subscriptions.memberId, stale.id));

    // Inconnu de la base avec le rôle (ajouté à la main sur Discord).
    const intruder = discordId();
    t.discord.join(intruder, [ROLE_MEMBER]);

    // Exceptions : admin, modérateur, invité spécial (par ID), bot.
    t.discord.join(ADMIN_USER, [ROLE_ADMIN, ROLE_MEMBER]);
    const mod = discordId();
    t.discord.join(mod, [ROLE_MOD, ROLE_MEMBER]);
    const guest = discordId();
    t.discord.join(guest, [ROLE_MEMBER]);
    t.deps.policy.exemptUserIds.push(guest);
    const bot = discordId();
    t.discord.join(bot, [ROLE_MEMBER], { isBot: true });

    // Abonné absent du serveur.
    const absent = await t.member({ inGuild: false });
    await adminGrant(t.deps, { discordUserId: absent.discordUserId, days: 30, adminId: ADMIN_USER });

    // Paiement validé chez Wave dont le webhook s'est perdu.
    const lost = await t.member();
    const checkout = await startCheckout(t.deps, { memberId: lost.id, planId: "quarterly", method: "mobile_money", autoRenew: false, autoRenewConsent: false });
    t.mock.pay("wave", checkout.reference);
    await t.runner.drain();
    t.clock.advanceMinutes(30);

    const report = await reconcile(t.deps);
    await t.runner.drain();

    expect(report.roleGranted).toContain(legit.discordUserId);
    expect(report.roleRemoved).toEqual(expect.arrayContaining([stale.discordUserId, intruder]));
    expect(report.notInGuild).toContain(absent.discordUserId);
    expect(report.paymentsRecovered).toContain(checkout.reference);
    expect(report.exemptSkipped).toBeGreaterThanOrEqual(4);

    expect(t.discord.rolesOf(legit.discordUserId)).toContain(ROLE_MEMBER);
    expect(t.discord.rolesOf(stale.discordUserId)).not.toContain(ROLE_MEMBER);
    expect(t.discord.rolesOf(intruder)).not.toContain(ROLE_MEMBER);
    for (const id of [ADMIN_USER, mod, guest, bot]) expect(t.discord.rolesOf(id)).toContain(ROLE_MEMBER);
    expect((await getSubscriptionForMember(t.db, lost.id))?.status).toBe("active");
    expect(t.discord.rolesOf(lost.discordUserId)).toContain(ROLE_MEMBER);
    expect(t.discord.logs.some((l) => l.includes("Réconciliation quotidienne"))).toBe(true);

    // Rejouer la réconciliation ne change plus rien (idempotence).
    const again = await reconcile(t.deps);
    expect(again.roleGranted).toHaveLength(0);
    expect(again.roleRemoved).toHaveLength(0);
  });
});

describe("Import CSV des membres actuels", () => {
  it("importe sans faire repayer, calcule le statut, ignore les doublons et signale les erreurs", async () => {
    t.clock.set("2026-11-20T10:00:00Z");
    const a = discordId();
    const b = discordId();
    const c = discordId();
    t.discord.join(a);
    t.discord.join(b);
    const rows = [
      { discord_user_id: a, nom: "Awa", email: "awa@exemple.sn", telephone: "+221770000000", formule: "Mensuel", date_de_fin: "2026-12-15" },
      { discord_user_id: b, nom: "Moussa", email: "", telephone: "", formule: "trimestriel", date_de_fin: "18/11/2026" },
      { discord_user_id: c, nom: "Ancien", email: "", telephone: "", formule: "annuel", date_de_fin: "2026-01-01" },
      { discord_user_id: "123", nom: "Erreur", email: "", telephone: "", formule: "mensuel", date_de_fin: "2026-12-01" },
      { discord_user_id: discordId(), nom: "Erreur", email: "", telephone: "", formule: "hebdo", date_de_fin: "2026-12-01" },
      { discord_user_id: discordId(), nom: "Erreur", email: "", telephone: "", formule: "mensuel", date_de_fin: "31/02/2026" },
    ];
    const dry = await importMembers(t.deps, rows, { dryRun: true });
    expect(dry.created).toBe(3);

    const report = await importMembers(t.deps, rows);
    await t.runner.drain();
    expect(report.created).toBe(3);
    expect(report.errors.map((e) => e.line)).toEqual([5, 6, 7]);

    const subOf = async (id: string) => {
      const m = (await t.db.query.members.findFirst({ where: (mm, { eq: e }) => e(mm.discordUserId, id) }))!;
      return getSubscriptionForMember(t.db, m.id);
    };
    expect((await subOf(a))?.status).toBe("active");
    expect((await subOf(a))?.currentPeriodEnd?.toISOString()).toBe("2026-12-15T23:59:59.000Z");
    expect((await subOf(b))?.status).toBe("grace_period");
    expect((await subOf(c))?.status).toBe("expired");
    expect(t.discord.rolesOf(a)).toContain(ROLE_MEMBER);
    expect(t.discord.rolesOf(b)).toContain(ROLE_MEMBER);
    // Aucun paiement demandé aux membres importés.
    const awa = (await t.db.query.members.findFirst({ where: (mm, { eq: e }) => e(mm.discordUserId, a) }))!;
    expect(await t.db.select().from(payments).where(eq(payments.memberId, awa.id))).toHaveLength(0);

    const second = await importMembers(t.deps, rows);
    expect(second.created).toBe(0);
    expect(second.skipped).toBe(3);
  });
});
