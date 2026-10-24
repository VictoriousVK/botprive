import { describe, expect, it } from "vitest";
import { addMonthsAnchored, computeGrantedPeriod, computePaidPeriod, formatDate, reminderDueAt } from "../src/dates";

const d = (iso: string) => new Date(iso);
const iso = (date: Date) => date.toISOString();

describe("Calcul des dates (test 1)", () => {
  it("mensuel : activé le 12 novembre → fin le 12 décembre", () => {
    const p = computePaidPeriod({ status: "pending_payment", currentPeriodEnd: null, anchorDay: null }, 1, d("2026-11-12T14:30:00Z"));
    expect(iso(p.start)).toBe("2026-11-12T14:30:00.000Z");
    expect(iso(p.end)).toBe("2026-12-12T14:30:00.000Z");
    expect(p.anchorDay).toBe(12);
    expect(p.continued).toBe(false);
  });

  it("trimestriel : 3 mois calendaires, changement d'année", () => {
    const p = computePaidPeriod({ status: "pending_payment", currentPeriodEnd: null, anchorDay: null }, 3, d("2026-11-30T08:00:00Z"));
    expect(iso(p.end)).toBe("2027-02-28T08:00:00.000Z");
  });

  it("annuel : 12 mois, y compris depuis un 29 février", () => {
    const p = computePaidPeriod({ status: "pending_payment", currentPeriodEnd: null, anchorDay: null }, 12, d("2028-02-29T10:00:00Z"));
    expect(iso(p.end)).toBe("2029-02-28T10:00:00.000Z");
    const q = computePaidPeriod({ status: "pending_payment", currentPeriodEnd: null, anchorDay: null }, 12, d("2026-10-26T18:00:00Z"));
    expect(iso(q.end)).toBe("2027-10-26T18:00:00.000Z");
  });

  it("fin de mois : 31 janv. → 28 févr. → 31 mars (ancrage retrouvé)", () => {
    const jan = computePaidPeriod({ status: "pending_payment", currentPeriodEnd: null, anchorDay: null }, 1, d("2027-01-31T09:00:00Z"));
    expect(iso(jan.end)).toBe("2027-02-28T09:00:00.000Z");
    expect(jan.anchorDay).toBe(31);
    // Renouvellement le 27 février (anticipé) : part de la fin de période, ancrage 31 conservé.
    const feb = computePaidPeriod({ status: "renewal_due", currentPeriodEnd: jan.end, anchorDay: jan.anchorDay }, 1, d("2027-02-27T09:00:00Z"));
    expect(iso(feb.start)).toBe("2027-02-28T09:00:00.000Z");
    expect(iso(feb.end)).toBe("2027-03-31T09:00:00.000Z");
    const mar = computePaidPeriod({ status: "active", currentPeriodEnd: feb.end, anchorDay: 31 }, 1, d("2027-03-30T09:00:00Z"));
    expect(iso(mar.end)).toBe("2027-04-30T09:00:00.000Z");
    const apr = computePaidPeriod({ status: "active", currentPeriodEnd: mar.end, anchorDay: 31 }, 1, d("2027-04-29T09:00:00Z"));
    expect(iso(apr.end)).toBe("2027-05-31T09:00:00.000Z");
  });

  it("année bissextile : 31 janv. 2028 → 29 févr. 2028", () => {
    expect(iso(addMonthsAnchored(d("2028-01-31T00:00:00Z"), 1, 31))).toBe("2028-02-29T00:00:00.000Z");
  });

  it("renouvellement anticipé : la nouvelle période part de la fin de la période en cours (aucun jour perdu)", () => {
    const ctx = { status: "active", currentPeriodEnd: d("2026-12-12T14:30:00Z"), anchorDay: 12 };
    const p = computePaidPeriod(ctx, 1, d("2026-12-01T10:00:00Z"));
    expect(iso(p.start)).toBe("2026-12-12T14:30:00.000Z");
    expect(iso(p.end)).toBe("2027-01-12T14:30:00.000Z");
    expect(p.continued).toBe(true);
  });

  it("paiement pendant la grâce : part de la fin échue (ancrage conservé)", () => {
    const ctx = { status: "grace_period", currentPeriodEnd: d("2026-12-12T14:30:00Z"), anchorDay: 12 };
    const p = computePaidPeriod(ctx, 1, d("2026-12-14T10:00:00Z"));
    expect(iso(p.start)).toBe("2026-12-12T14:30:00.000Z");
    expect(iso(p.end)).toBe("2027-01-12T14:30:00.000Z");
  });

  it("paiement après expiration : nouvelle période à partir du paiement, nouvel ancrage", () => {
    const ctx = { status: "expired", currentPeriodEnd: d("2026-12-12T14:30:00Z"), anchorDay: 12 };
    const p = computePaidPeriod(ctx, 1, d("2027-01-20T10:00:00Z"));
    expect(iso(p.start)).toBe("2027-01-20T10:00:00.000Z");
    expect(iso(p.end)).toBe("2027-02-20T10:00:00.000Z");
    expect(p.anchorDay).toBe(20);
  });

  it("jours offerts par l'admin : prolonge la période et déplace l'ancrage", () => {
    const ctx = { status: "active", currentPeriodEnd: d("2026-12-12T14:30:00Z"), anchorDay: 12 };
    const p = computeGrantedPeriod(ctx, 7, d("2026-12-01T10:00:00Z"));
    expect(iso(p.end)).toBe("2026-12-19T14:30:00.000Z");
    expect(p.anchorDay).toBe(19);
  });

  it("rappels : J-3 et J-1 à 9 h (Dakar), J0 au plus tard 1 h avant l'échéance", () => {
    const end = d("2026-12-12T14:30:00Z");
    expect(iso(reminderDueAt(end, 3))).toBe("2026-12-09T09:00:00.000Z");
    expect(iso(reminderDueAt(end, 1))).toBe("2026-12-11T09:00:00.000Z");
    expect(iso(reminderDueAt(end, 0))).toBe("2026-12-12T09:00:00.000Z");
    expect(iso(reminderDueAt(d("2026-12-12T06:00:00Z"), 0))).toBe("2026-12-12T05:00:00.000Z");
  });

  it("affichage en Africa/Dakar", () => {
    expect(formatDate(d("2026-12-12T23:30:00Z"))).toBe("12 décembre 2026");
  });
});
