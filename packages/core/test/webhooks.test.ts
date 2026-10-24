import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { eq } from "drizzle-orm";
import { payments, subscriptionPeriods, subscriptions, webhookEvents } from "@vk/db";
import { getSubscriptionForMember, signWavePayload, startCheckout } from "../src";
import { ROLE_MEMBER, setup, type TestCtx } from "./helpers";

let t: TestCtx;
beforeAll(async () => {
  t = await setup();
});
afterAll(async () => {
  await t.teardown();
});

async function periodsOf(subscriptionId: string) {
  return t.db.select().from(subscriptionPeriods).where(eq(subscriptionPeriods.subscriptionId, subscriptionId));
}

describe("Webhooks (test 3)", () => {
  it("webhook valide : accès accordé après vérification serveur à serveur", async () => {
    const m = await t.member();
    const { res } = await t.payWave(m.id, "monthly");
    expect(res.httpStatus).toBe(200);
    const sub = await getSubscriptionForMember(t.db, m.id);
    expect(sub?.status).toBe("active");
    expect(sub?.currentPeriodEnd?.toISOString()).toBe("2026-12-12T10:00:00.000Z");
    expect(t.discord.rolesOf(m.discordUserId)).toContain(ROLE_MEMBER);
    const [payment] = await t.db.select().from(payments).where(eq(payments.memberId, m.id));
    expect(payment?.status).toBe("succeeded");
    expect(payment?.amount).toBe(50_000);
  });

  it("le retour navigateur « paiement réussi » n'accorde rien sans webhook", async () => {
    const m = await t.member();
    const checkout = await startCheckout(t.deps, { memberId: m.id, planId: "monthly", method: "mobile_money", autoRenew: false, autoRenewConsent: false });
    t.mock.pay("wave", checkout.reference); // payé chez Wave, mais aucun webhook livré
    await t.runner.drain();
    expect((await getSubscriptionForMember(t.db, m.id))?.status).toBe("pending_payment");
    expect(t.discord.rolesOf(m.discordUserId)).not.toContain(ROLE_MEMBER);
  });

  it("webhook reçu deux fois : une seule prolongation", async () => {
    const m = await t.member();
    const { delivery } = await t.payWave(m.id, "monthly");
    const again = await t.deliver(delivery);
    expect(again.httpStatus).toBe(200);
    expect(again.body.duplicate).toBe(true);
    const sub = await getSubscriptionForMember(t.db, m.id);
    expect(await periodsOf(sub!.id)).toHaveLength(1);
    expect(sub?.currentPeriodEnd?.toISOString()).toBe("2026-12-12T10:00:00.000Z");
  });

  it("même paiement notifié par deux événements différents : une seule prolongation", async () => {
    const m = await t.member();
    const { checkout } = await t.payWave(m.id, "monthly");
    const session = [...t.mock.waveSessions.values()].find((s) => s.client_reference === checkout.reference)!;
    const other = t.mock.waveWebhook(session, "checkout.session.completed"); // nouvel identifiant d'événement
    expect((await t.deliver(other)).httpStatus).toBe(200);
    const sub = await getSubscriptionForMember(t.db, m.id);
    expect(await periodsOf(sub!.id)).toHaveLength(1);
  });

  it("webhook falsifié : signature invalide → 401, rien n'est écrit", async () => {
    const m = await t.member();
    const checkout = await startCheckout(t.deps, { memberId: m.id, planId: "annual", method: "mobile_money", autoRenew: false, autoRenewConsent: false });
    const session = [...t.mock.waveSessions.values()].find((s) => s.client_reference === checkout.reference)!;
    const forged = JSON.stringify({ id: "EV_forged", type: "checkout.session.completed", data: { ...session, payment_status: "succeeded" } });
    const before = await t.db.select().from(webhookEvents);

    const badSig = await t.deliver({ provider: "wave", headers: { "wave-signature": signWavePayload(forged, "mauvais-secret", t.clock.now()) }, rawBody: forged });
    expect(badSig.httpStatus).toBe(401);
    const noSig = await t.deliver({ provider: "wave", headers: {}, rawBody: forged });
    expect(noSig.httpStatus).toBe(401);
    const flw = await t.deliver({ provider: "flutterwave", headers: { "verif-hash": "devine" }, rawBody: forged });
    expect(flw.httpStatus).toBe(401);

    expect(await t.db.select().from(webhookEvents)).toHaveLength(before.length);
    expect((await getSubscriptionForMember(t.db, m.id))?.status).toBe("pending_payment");
  });

  it("webhook correctement signé mais rejoué hors délai (anti-rejeu > 5 min) → 401", async () => {
    const m = await t.member();
    const checkout = await startCheckout(t.deps, { memberId: m.id, planId: "monthly", method: "mobile_money", autoRenew: false, autoRenewConsent: false });
    const delivery = t.mock.pay("wave", checkout.reference);
    const tenMinutesAgo = new Date(t.clock.now().getTime() - 10 * 60_000);
    const stale = { ...delivery, headers: { "wave-signature": signWavePayload(delivery.rawBody, "wave_sn_WHS_test", tenMinutesAgo) } };
    expect((await t.deliver(stale)).httpStatus).toBe(401);
    expect((await getSubscriptionForMember(t.db, m.id))?.status).toBe("pending_payment");
    // Même corps, même secret, horodatage récent : accepté.
    expect((await t.deliver(delivery)).httpStatus).toBe(200);
    expect((await getSubscriptionForMember(t.db, m.id))?.status).toBe("active");
  });

  it("webhook signé mais paiement non confirmé par l'API (signature volée) : aucun accès", async () => {
    const m = await t.member();
    const checkout = await startCheckout(t.deps, { memberId: m.id, planId: "monthly", method: "mobile_money", autoRenew: false, autoRenewConsent: false });
    const session = [...t.mock.waveSessions.values()].find((s) => s.client_reference === checkout.reference)!;
    // Le corps annonce « succeeded » mais Wave (API) dit toujours « processing ».
    const lying = t.mock.waveWebhook({ ...session, payment_status: "succeeded", checkout_status: "complete" }, "checkout.session.completed");
    expect((await t.deliver(lying)).httpStatus).toBe(200);
    expect((await getSubscriptionForMember(t.db, m.id))?.status).toBe("pending_payment");
  });

  it("montant non conforme à la vérification serveur : refusé", async () => {
    const m = await t.member();
    const checkout = await startCheckout(t.deps, { memberId: m.id, planId: "monthly", method: "mobile_money", autoRenew: false, autoRenewConsent: false });
    const session = [...t.mock.waveSessions.values()].find((s) => s.client_reference === checkout.reference)!;
    session.amount = "100"; // fraude : montant modifié chez le prestataire
    const delivery = t.mock.pay("wave", checkout.reference);
    await t.deliver(delivery);
    const [payment] = await t.db.select().from(payments).where(eq(payments.reference, checkout.reference));
    expect(payment?.status).toBe("failed");
    expect(payment?.failureReason).toContain("montant");
    expect((await getSubscriptionForMember(t.db, m.id))?.status).toBe("pending_payment");
  });

  it("événements dans le désordre : un échec arrivé après le succès ne rétrograde rien", async () => {
    const m = await t.member();
    const checkout = await startCheckout(t.deps, { memberId: m.id, planId: "monthly", method: "card", autoRenew: false, autoRenewConsent: false });
    const success = t.mock.pay("flutterwave", checkout.reference);
    const tx = [...t.mock.flwTransactions.values()].find((x) => x.tx_ref === checkout.reference)!;
    const staleFailure = t.mock.flutterwaveChargeWebhook({ ...tx, status: "failed" });
    await t.deliver(success);
    await t.deliver(staleFailure);
    const [payment] = await t.db.select().from(payments).where(eq(payments.reference, checkout.reference));
    expect(payment?.status).toBe("succeeded");
    expect((await getSubscriptionForMember(t.db, m.id))?.status).toBe("active");
  });

  it("événements dans le désordre : deux renouvellements livrés à l'envers prolongent chacun une fois", async () => {
    const m = await t.member();
    await t.payWave(m.id, "monthly");
    const c1 = await startCheckout(t.deps, { memberId: m.id, planId: "monthly", method: "mobile_money", autoRenew: false, autoRenewConsent: false });
    const c2 = await startCheckout(t.deps, { memberId: m.id, planId: "quarterly", method: "mobile_money", autoRenew: false, autoRenewConsent: false });
    const d1 = t.mock.pay("wave", c1.reference);
    const d2 = t.mock.pay("wave", c2.reference);
    await t.deliver(d2);
    await t.deliver(d1);
    await t.deliver(d2);
    const sub = await getSubscriptionForMember(t.db, m.id);
    // 12 nov. + 1 mois (initial) + 3 mois + 1 mois = 12 avril 2027, quel que soit l'ordre.
    expect(sub?.currentPeriodEnd?.toISOString()).toBe("2027-04-12T10:00:00.000Z");
    expect(await periodsOf(sub!.id)).toHaveLength(3);
  });

  it("carte + renouvellement automatique : prélèvement récurrent rattaché, avis sans lien de paiement", async () => {
    const m = await t.member();
    await t.payCardAuto(m.id, "monthly");
    let sub = await getSubscriptionForMember(t.db, m.id);
    expect(sub?.renewalMode).toBe("auto_card");
    expect(sub?.providerSubscriptionId).toBeTruthy();

    // Le prestataire prélève automatiquement le mois suivant (même tx_ref, nouvelle transaction).
    const recurring = t.mock.chargeRecurring(Number(sub!.providerSubscriptionId));
    expect((await t.deliver(recurring)).httpStatus).toBe(200);
    expect((await t.deliver(recurring)).body.duplicate).toBe(true);
    sub = await getSubscriptionForMember(t.db, m.id);
    expect(sub?.currentPeriodEnd?.toISOString()).toBe("2027-01-12T10:00:00.000Z");
    const rows = await t.db.select().from(payments).where(eq(payments.memberId, m.id));
    expect(rows.filter((p) => p.status === "succeeded")).toHaveLength(2);
  });

  it("annulation du prélèvement par webhook prestataire : accès conservé jusqu'à la fin", async () => {
    const m = await t.member();
    await t.payCardAuto(m.id, "monthly");
    const sub = await getSubscriptionForMember(t.db, m.id);
    const res = await t.deliver(t.mock.cancelledSubscriptionWebhook(Number(sub!.providerSubscriptionId)));
    expect(res.httpStatus).toBe(200);
    const after = await t.db.select().from(subscriptions).where(eq(subscriptions.id, sub!.id));
    expect(after[0]?.status).toBe("canceled");
    expect(after[0]?.renewalMode).toBe("manual");
    expect(t.discord.rolesOf(m.discordUserId)).toContain(ROLE_MEMBER);
  });

  it("paiement manuel refusé quand un prélèvement carte est actif (évite le double paiement)", async () => {
    const m = await t.member();
    await t.payCardAuto(m.id);
    await expect(
      startCheckout(t.deps, { memberId: m.id, planId: "monthly", method: "mobile_money", autoRenew: false, autoRenewConsent: false }),
    ).rejects.toThrow(/renouvellement par carte est actif/);
  });

  it("renouvellement auto sans consentement explicite : refusé", async () => {
    const m = await t.member();
    await expect(
      startCheckout(t.deps, { memberId: m.id, planId: "monthly", method: "card", autoRenew: true, autoRenewConsent: false }),
    ).rejects.toThrow(/Coche la case/);
  });
});
