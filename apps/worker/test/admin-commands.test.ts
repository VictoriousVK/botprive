import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { commandDefinitions } from "../src/commands";
import { runAdminCommand } from "../src/admin-commands";
import { ADMIN_USER, ROLE_MEMBER, setup, type TestCtx } from "../../../packages/core/test/helpers";

let t: TestCtx;
beforeAll(async () => {
  t = await setup("2026-11-12T10:00:00Z");
});
afterAll(async () => {
  await t.teardown();
});

describe("Commandes admin Discord", () => {
  it("définitions : 5 commandes, masquées par défaut aux membres, utilisables uniquement sur le serveur", () => {
    expect(commandDefinitions.map((c) => c.name)).toEqual(["abonne", "ajouter", "retirer", "expirations", "stats"]);
    for (const c of commandDefinitions) {
      expect(c.default_member_permissions).toBe("268435456"); // Gérer les rôles
      expect(c.contexts).toEqual([0]); // serveur uniquement
    }
  });

  it("/ajouter jours, /abonne, /expirations, /stats, /retirer", async () => {
    const m = await t.member();
    const added = await runAdminCommand(t.deps, ADMIN_USER, { name: "ajouter", userId: m.discordUserId, days: 30, note: "Wave perso" });
    expect(added).toContain("12 décembre 2026");
    await t.runner.drain();
    expect(t.discord.rolesOf(m.discordUserId)).toContain(ROLE_MEMBER);

    const card = await runAdminCommand(t.deps, ADMIN_USER, { name: "abonne", userId: m.discordUserId });
    expect(card).toContain("Statut : **Actif**");
    expect(card).toContain("manuel");

    t.clock.set("2026-12-08T10:00:00Z");
    const exp = await runAdminCommand(t.deps, ADMIN_USER, { name: "expirations", days: 7 });
    expect(exp).toContain(`<@${m.discordUserId}>`);

    await t.payWave((await t.member()).id, "quarterly");
    const stats = await runAdminCommand(t.deps, ADMIN_USER, { name: "stats" });
    expect(stats).toContain("Membres avec accès : **2**");
    expect(stats).toContain("115 000 FCFA");

    const removed = await runAdminCommand(t.deps, ADMIN_USER, { name: "retirer", userId: m.discordUserId, reason: "test" });
    expect(removed).toContain("suspendu");
    await t.runner.drain();
    expect(t.discord.rolesOf(m.discordUserId)).not.toContain(ROLE_MEMBER);
  });

  it("/ajouter formule, membre inconnu, erreurs lisibles", async () => {
    t.clock.set("2026-11-12T10:00:00Z");
    const m = await t.member();
    const res = await runAdminCommand(t.deps, ADMIN_USER, { name: "ajouter", userId: m.discordUserId, planId: "quarterly" });
    expect(res).toContain("12 février 2027");
    expect(await runAdminCommand(t.deps, ADMIN_USER, { name: "abonne", userId: "399999999999999999" })).toContain("n'est pas enregistré");
    expect(await runAdminCommand(t.deps, ADMIN_USER, { name: "retirer", userId: "399999999999999999" })).toContain("⚠️");
    expect(await runAdminCommand(t.deps, ADMIN_USER, { name: "ajouter", userId: m.discordUserId })).toContain("Indique");
  });
});
