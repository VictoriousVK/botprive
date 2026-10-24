import { describe, expect, it } from "vitest";
import {
  assertTransition,
  canTransition,
  hasAccess,
  InvalidTransitionError,
  nextTimeTransition,
  statusAfterReactivation,
  SUBSCRIPTION_STATUSES,
  TRANSITIONS,
} from "../src";

describe("Machine à états (test 2)", () => {
  it("cycle nominal : pending_payment → active → renewal_due → grace_period → expired → active", () => {
    expect(canTransition("pending_payment", "payment_confirmed", "active")).toBe(true);
    expect(canTransition("active", "renewal_window_reached", "renewal_due")).toBe(true);
    expect(canTransition("renewal_due", "period_ended", "grace_period")).toBe(true);
    expect(canTransition("grace_period", "grace_ended", "expired")).toBe(true);
    expect(canTransition("expired", "payment_confirmed", "active")).toBe(true);
  });

  it("annulation : accès conservé puis expiration sans grâce", () => {
    expect(canTransition("active", "renewal_canceled", "canceled")).toBe(true);
    expect(canTransition("canceled", "period_ended", "expired")).toBe(true);
    expect(canTransition("canceled", "period_ended", "grace_period")).toBe(false);
  });

  it.each([
    ["pending_payment", "period_ended", "grace_period"],
    ["pending_payment", "grace_ended", "expired"],
    ["expired", "renewal_window_reached", "renewal_due"],
    ["expired", "grace_ended", "expired"],
    ["active", "grace_ended", "expired"],
    ["active", "period_ended", "expired"],
    ["refunded", "period_ended", "grace_period"],
    ["suspended", "payment_confirmed", "active"],
    ["suspended", "period_ended", "grace_period"],
    ["canceled", "renewal_window_reached", "renewal_due"],
    ["grace_period", "renewal_canceled", "canceled"],
  ] as const)("transition interdite refusée : %s --(%s)--> %s", (from, event, to) => {
    expect(canTransition(from, event, to)).toBe(false);
    expect(() => assertTransition(from, event, to)).toThrow(InvalidTransitionError);
  });

  it("la table ne référence que des statuts connus", () => {
    for (const [from, events] of Object.entries(TRANSITIONS)) {
      expect(SUBSCRIPTION_STATUSES).toContain(from);
      for (const targets of Object.values(events)) for (const t of targets) expect(SUBSCRIPTION_STATUSES).toContain(t);
    }
  });

  it("accès : actif, renouvellement proche, grâce et annulé gardent le rôle ; les autres non", () => {
    expect(SUBSCRIPTION_STATUSES.filter(hasAccess)).toEqual(["active", "renewal_due", "grace_period", "canceled"]);
  });

  it("transitions liées au temps", () => {
    const end = new Date("2026-12-12T14:30:00Z");
    const grace = new Date("2026-12-15T14:30:00Z");
    const at = (iso: string, status: "active" | "renewal_due" | "grace_period" | "canceled") =>
      nextTimeTransition({ status, currentPeriodEnd: end, graceEndsAt: grace }, new Date(iso), 3);
    expect(at("2026-12-01T00:00:00Z", "active")).toBeNull();
    expect(at("2026-12-10T00:00:00Z", "active")?.to).toBe("renewal_due");
    expect(at("2026-12-12T14:30:00Z", "renewal_due")?.to).toBe("grace_period");
    expect(at("2026-12-13T00:00:00Z", "active")?.to).toBe("grace_period");
    expect(at("2026-12-15T14:29:00Z", "grace_period")).toBeNull();
    expect(at("2026-12-15T14:30:00Z", "grace_period")?.to).toBe("expired");
    expect(at("2026-12-12T15:00:00Z", "canceled")?.to).toBe("expired");
  });

  it("levée de suspension : statut recalculé selon les dates", () => {
    const sub = { status: "suspended" as const, currentPeriodEnd: new Date("2026-12-12T00:00:00Z"), graceEndsAt: new Date("2026-12-15T00:00:00Z") };
    expect(statusAfterReactivation(sub, new Date("2026-12-01T00:00:00Z"), 3)).toBe("active");
    expect(statusAfterReactivation(sub, new Date("2026-12-10T00:00:00Z"), 3)).toBe("renewal_due");
    expect(statusAfterReactivation(sub, new Date("2026-12-13T00:00:00Z"), 3)).toBe("grace_period");
    expect(statusAfterReactivation(sub, new Date("2026-12-16T00:00:00Z"), 3)).toBe("expired");
  });
});
