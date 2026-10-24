import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { eq } from "drizzle-orm";
import { payments } from "@vk/db";
import { getSubscriptionForMember, startCheckout } from "../src";
import { ROLE_MEMBER, setup, TEST_PRICES, type TestCtx } from "./helpers";

let t: TestCtx;
beforeAll(async () => {
  t = await setup("2026-11-12T10:00:00Z", { card: "paydunya", mobileMoney: "paydunya" });
});
afterAll(async () => {
  await t.teardown();
});

describe("PayDunya (sandbox simulée) : renouvellement assisté", () => {
  it("facture Mobile Money → IPN → vérification serveur → accès", async () => {
    const m = await t.member();
    const checkout = await startCheckout(t.deps, { memberId: m.id, planId: "quarterly", method: "mobile_money", autoRenew: false, autoRenewConsent: false });
    const invoice = [...t.mock.paydunyaInvoices.values()].find((i) => i.custom_data.reference === checkout.reference)!;
    expect(invoice.total_amount).toBe(TEST_PRICES.quarterly);
    expect(invoice.channels).toEqual(["orange-money-senegal", "wave-senegal", "free-money-senegal"]);
    const res = await t.deliver(t.mock.pay("paydunya", checkout.reference));
    await t.runner.drain();
    expect(res.httpStatus).toBe(200);
    expect((await getSubscriptionForMember(t.db, m.id))?.status).toBe("active");
    expect(t.discord.rolesOf(m.discordUserId)).toContain(ROLE_MEMBER);
  });

  it("IPN reçu deux fois : une seule prolongation", async () => {
    const m = await t.member();
    const checkout = await startCheckout(t.deps, { memberId: m.id, planId: "monthly", method: "card", autoRenew: false, autoRenewConsent: false });
    const ipn = t.mock.pay("paydunya", checkout.reference);
    await t.deliver(ipn);
    expect((await t.deliver(ipn)).body.duplicate).toBe(true);
    expect((await getSubscriptionForMember(t.db, m.id))?.currentPeriodEnd?.toISOString()).toBe("2026-12-12T10:00:00.000Z");
  });

  it("hash falsifié → 401", async () => {
    const m = await t.member();
    const checkout = await startCheckout(t.deps, { memberId: m.id, planId: "monthly", method: "mobile_money", autoRenew: false, autoRenewConsent: false });
    const invoice = [...t.mock.paydunyaInvoices.values()].find((i) => i.custom_data.reference === checkout.reference)!;
    const forged = t.mock.paydunyaIpn(invoice, "completed", "mauvaise-cle");
    invoice.status = "pending";
    expect((await t.deliver(forged)).httpStatus).toBe(401);
    expect((await getSubscriptionForMember(t.db, m.id))?.status).toBe("pending_payment");
  });

  it("IPN « completed » mais facture non payée selon l'API : aucun accès", async () => {
    const m = await t.member();
    const checkout = await startCheckout(t.deps, { memberId: m.id, planId: "monthly", method: "mobile_money", autoRenew: false, autoRenewConsent: false });
    const invoice = [...t.mock.paydunyaInvoices.values()].find((i) => i.custom_data.reference === checkout.reference)!;
    const ipn = t.mock.paydunyaIpn(invoice, "completed");
    invoice.status = "pending"; // la confirmation serveur à serveur dit « en attente »
    await t.deliver(ipn);
    expect((await getSubscriptionForMember(t.db, m.id))?.status).toBe("pending_payment");
    const [p] = await t.db.select().from(payments).where(eq(payments.reference, checkout.reference));
    expect(p?.status).toBe("pending");
  });

  it("pas de prélèvement automatique chez PayDunya : refus explicite, jamais simulé", async () => {
    const m = await t.member();
    await expect(startCheckout(t.deps, { memberId: m.id, planId: "monthly", method: "card", autoRenew: true, autoRenewConsent: true })).rejects.toThrow(
      /renouvellement automatique n'est pas disponible/,
    );
  });
});
