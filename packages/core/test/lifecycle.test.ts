import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { eq } from "drizzle-orm";
import { jobs, reminders } from "@vk/db";
import {
  adminGrant,
  claimJobs,
  adminSuspend,
  cancelRenewal,
  getSubscriptionForMember,
  JobRunner,
  createJobHandlers,
  runScheduledTick,
  silentLogger,
} from "../src";
import { ADMIN_USER, ROLE_ADMIN, ROLE_MEMBER, setup, type TestCtx } from "./helpers";

let t: TestCtx;
beforeAll(async () => {
  t = await setup("2026-11-12T10:00:00Z");
});
afterAll(async () => {
  await t.teardown();
});

const tick = async () => {
  const report = await runScheduledTick(t.deps);
  await t.runner.drain();
  return report;
};

describe("Paiement confirmé pendant une panne Discord (test 4)", () => {
  it("le rôle est donné au retour de Discord grâce aux réessais", async () => {
    const m = await t.member();
    t.discord.down = true;
    await t.payWave(m.id);
    expect((await getSubscriptionForMember(t.db, m.id))?.status).toBe("active");
    expect(t.discord.rolesOf(m.discordUserId)).not.toContain(ROLE_MEMBER);
    const [pending] = await t.db.select().from(jobs).where(eq(jobs.type, "sync_access")).orderBy(jobs.id);
    expect(pending?.status).toBe("queued");
    expect(pending?.lastError).toContain("indisponible");

    // Discord revient ; on avance au-delà du délai de réessai.
    t.discord.down = false;
    t.clock.advanceMinutes(5);
    await t.runner.drain();
    expect(t.discord.rolesOf(m.discordUserId)).toContain(ROLE_MEMBER);
    t.clock.set("2026-11-12T10:00:00Z");
  });
});

describe("Expiration, grâce, retrait puis restauration (test 5)", () => {
  it("cycle complet avec rappels J-3 / J-1 / J0", async () => {
    t.clock.set("2026-11-12T10:00:00Z");
    const m = await t.member();
    await t.payWave(m.id, "monthly");
    expect(t.discord.rolesOf(m.discordUserId)).toContain(ROLE_MEMBER);
    const dmsBefore = t.discord.dms.filter((d) => d.userId === m.discordUserId).length;

    // J-3 à 9 h : rappel avec lien de paiement en 1 clic.
    t.clock.set("2026-12-09T09:05:00Z");
    await tick();
    let sub = await getSubscriptionForMember(t.db, m.id);
    expect(sub?.status).toBe("active"); // statut « renewal_due » à 72 h exactes de l'échéance (10 h)
    const myDms = () => t.discord.dms.filter((d) => d.userId === m.discordUserId);
    expect(myDms().length).toBe(dmsBefore + 1);
    expect(myDms().at(-1)?.content).toContain("https://club.test/r/");
    expect(t.email.sent.some((e) => e.to === m.email && e.subject.includes("se termine") && e.html.includes("/r/"))).toBe(true);

    // Un second passage le même jour n'envoie rien de plus.
    t.clock.set("2026-12-09T10:05:00Z");
    await tick();
    expect(myDms().length).toBe(dmsBefore + 1);
    expect((await getSubscriptionForMember(t.db, m.id))?.status).toBe("renewal_due");

    t.clock.set("2026-12-11T09:05:00Z");
    await tick();
    t.clock.set("2026-12-12T09:05:00Z");
    await tick();
    expect(myDms().length).toBe(dmsBefore + 3);
    const sent = await t.db.select().from(reminders).where(eq(reminders.subscriptionId, sub!.id));
    expect(sent.map((r) => r.offsetDays).sort()).toEqual([0, 1, 3]);

    // Échéance passée : période de grâce, accès conservé.
    t.clock.set("2026-12-12T10:01:00Z");
    await tick();
    sub = await getSubscriptionForMember(t.db, m.id);
    expect(sub?.status).toBe("grace_period");
    expect(t.discord.rolesOf(m.discordUserId)).toContain(ROLE_MEMBER);

    // Fin de grâce (3 jours) : expiré, rôle retiré, membre toujours sur le serveur.
    t.clock.set("2026-12-15T10:01:00Z");
    await tick();
    sub = await getSubscriptionForMember(t.db, m.id);
    expect(sub?.status).toBe("expired");
    expect(t.discord.rolesOf(m.discordUserId)).not.toContain(ROLE_MEMBER);
    expect(t.discord.members.has(m.discordUserId)).toBe(true);
    expect(t.discord.logs.some((l) => l.includes("Accès expiré"))).toBe(true);

    // Il repaie : rôle restauré automatiquement, nouvelle période depuis le paiement.
    t.clock.set("2026-12-20T18:00:00Z");
    await t.payWave(m.id, "monthly");
    sub = await getSubscriptionForMember(t.db, m.id);
    expect(sub?.status).toBe("active");
    expect(sub?.currentPeriodEnd?.toISOString()).toBe("2027-01-20T18:00:00.000Z");
    expect(t.discord.rolesOf(m.discordUserId)).toContain(ROLE_MEMBER);
  });

  it("paiement pendant la grâce : accès jamais coupé, ancrage conservé", async () => {
    t.clock.set("2027-03-01T08:00:00Z");
    const m = await t.member();
    await t.payWave(m.id);
    t.clock.set("2027-04-02T08:00:00Z");
    await tick();
    expect((await getSubscriptionForMember(t.db, m.id))?.status).toBe("grace_period");
    await t.payWave(m.id);
    const sub = await getSubscriptionForMember(t.db, m.id);
    expect(sub?.status).toBe("active");
    expect(sub?.currentPeriodEnd?.toISOString()).toBe("2027-05-01T08:00:00.000Z");
    expect(t.discord.rolesOf(m.discordUserId)).toContain(ROLE_MEMBER);
  });

  it("prélèvement carte actif : rappel = simple avis, jamais de lien de paiement", async () => {
    t.clock.set("2027-03-01T08:00:00Z");
    const m = await t.member();
    await t.payCardAuto(m.id);
    t.clock.set("2027-03-29T09:30:00Z");
    await tick();
    const dm = t.discord.dms.filter((d) => d.userId === m.discordUserId).at(-1);
    expect(dm?.content).toContain("automatiquement par carte");
    expect(dm?.content).not.toContain("/r/");
  });

  it("annulation par le membre : prélèvement annulé chez le prestataire, accès jusqu'à la fin, puis expiration sans grâce", async () => {
    t.clock.set("2027-03-01T08:00:00Z");
    const m = await t.member();
    await t.payCardAuto(m.id);
    const before = await getSubscriptionForMember(t.db, m.id);
    await cancelRenewal(t.deps, m.id, { type: "member", id: m.discordUserId });
    await t.runner.drain();
    expect(t.mock.flwSubscriptions.get(Number(before!.providerSubscriptionId))?.status).toBe("cancelled");
    expect((await getSubscriptionForMember(t.db, m.id))?.status).toBe("canceled");
    expect(t.discord.rolesOf(m.discordUserId)).toContain(ROLE_MEMBER);

    t.clock.set("2027-04-01T08:00:01Z");
    await tick();
    expect((await getSubscriptionForMember(t.db, m.id))?.status).toBe("expired");
    expect(t.discord.rolesOf(m.discordUserId)).not.toContain(ROLE_MEMBER);
  });

  it("commandes admin : /ajouter (paiement Wave perso) puis /retirer", async () => {
    t.clock.set("2027-03-01T08:00:00Z");
    const m = await t.member();
    await adminGrant(t.deps, { discordUserId: m.discordUserId, days: 30, adminId: ADMIN_USER, note: "Wave perso 50 000" });
    await t.runner.drain();
    let sub = await getSubscriptionForMember(t.db, m.id);
    expect(sub?.status).toBe("active");
    expect(sub?.currentPeriodEnd?.toISOString()).toBe("2027-03-31T08:00:00.000Z");
    expect(t.discord.rolesOf(m.discordUserId)).toContain(ROLE_MEMBER);
    expect(t.discord.logs.some((l) => l.includes("Wave perso"))).toBe(true);

    await adminSuspend(t.deps, { discordUserId: m.discordUserId, adminId: ADMIN_USER, reason: "test" });
    await t.runner.drain();
    sub = await getSubscriptionForMember(t.db, m.id);
    expect(sub?.status).toBe("suspended");
    expect(t.discord.rolesOf(m.discordUserId)).not.toContain(ROLE_MEMBER);
  });

  it("option d'expulsion : le membre expiré est expulsé au lieu de perdre seulement le rôle", async () => {
    t.clock.set("2027-03-01T08:00:00Z");
    const m = await t.member();
    await t.payWave(m.id);
    t.deps.policy.expiryAction = "kick";
    try {
      t.clock.set("2027-04-05T08:00:00Z");
      await tick();
      expect(t.discord.kicked).toContain(m.discordUserId);
    } finally {
      t.deps.policy.expiryAction = "remove_role";
    }
  });

  it("un admin exempté n'est jamais touché", async () => {
    t.discord.join(ADMIN_USER, [ROLE_ADMIN, ROLE_MEMBER]);
    await adminGrant(t.deps, { discordUserId: ADMIN_USER, days: 1, adminId: ADMIN_USER });
    t.clock.set("2027-06-01T08:00:00Z");
    await tick();
    expect(t.discord.rolesOf(ADMIN_USER)).toContain(ROLE_MEMBER);
  });
});

describe("Redémarrage du worker avec des échéances en attente (test 6)", () => {
  it("les tâches verrouillées par un worker arrêté sont relancées et les échéances rattrapées", async () => {
    t.clock.set("2027-07-01T08:00:00Z");
    const m = await t.member();
    t.discord.down = true;
    await t.payWave(m.id); // la tâche de rôle échoue et reste en file

    // Un worker « A » réserve les tâches puis meurt sans les terminer.
    t.discord.down = false;
    t.clock.advanceMinutes(2);
    const claimed = await claimJobs(t.db, "worker-A", 50, t.clock.now());
    expect(claimed.length).toBeGreaterThan(0);

    // Pendant l'arrêt, l'échéance et la grâce passent.
    t.clock.set("2027-08-10T08:00:00Z");

    // Redémarrage : un nouveau worker « B » démarre.
    const restarted = new JobRunner(t.db, createJobHandlers(t.deps), { workerId: "worker-B", logger: silentLogger, now: t.clock.now, concurrency: 20 });
    const report = await runScheduledTick(t.deps);
    expect(report.recoveredJobs).toBeGreaterThan(0);
    await restarted.drain();

    const sub = await getSubscriptionForMember(t.db, m.id);
    expect(sub?.status).toBe("expired"); // active → grâce → expiré, rattrapé en un passage
    expect(t.discord.rolesOf(m.discordUserId)).not.toContain(ROLE_MEMBER);
    const stuck = await t.db.select().from(jobs).where(eq(jobs.status, "running"));
    expect(stuck).toHaveLength(0);
  });
});
