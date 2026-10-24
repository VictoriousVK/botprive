import { InvalidTransitionError } from "./errors";

/*
 * Machine à états des abonnements.
 *
 *   pending_payment ──payment_confirmed──▶ active ──renewal_window_reached──▶ renewal_due
 *                                            │  ▲                                 │
 *                                            │  └──────payment_confirmed──────────┤
 *                                            └──────────period_ended──────────────┴──▶ grace_period ──grace_ended──▶ expired
 *                                                                                         │                          │
 *                                                                                         └────payment_confirmed─────┴──▶ active
 *
 *   canceled  : renouvellement annulé, accès conservé jusqu'à la fin de la période payée, puis expired (sans grâce).
 *   refunded  : paiement remboursé, accès retiré.
 *   suspended : suspension par l'admin (/retirer), accès retiré.
 *
 * Toute transition absente de la table ci-dessous est refusée (InvalidTransitionError).
 */

export const SUBSCRIPTION_STATUSES = [
  "pending_payment",
  "active",
  "renewal_due",
  "grace_period",
  "expired",
  "canceled",
  "refunded",
  "suspended",
] as const;

export type SubscriptionStatus = (typeof SUBSCRIPTION_STATUSES)[number];

export type SubscriptionEvent =
  | "payment_confirmed"
  | "admin_granted"
  | "renewal_window_reached"
  | "period_ended"
  | "grace_ended"
  | "renewal_canceled"
  | "payment_refunded"
  | "admin_suspended"
  | "admin_reactivated";

type TransitionTable = Record<SubscriptionStatus, Partial<Record<SubscriptionEvent, readonly SubscriptionStatus[]>>>;

export const TRANSITIONS: TransitionTable = {
  pending_payment: {
    payment_confirmed: ["active"],
    admin_granted: ["active"],
    admin_suspended: ["suspended"],
  },
  active: {
    payment_confirmed: ["active"],
    admin_granted: ["active"],
    renewal_window_reached: ["renewal_due"],
    period_ended: ["grace_period"],
    renewal_canceled: ["canceled"],
    payment_refunded: ["refunded"],
    admin_suspended: ["suspended"],
  },
  renewal_due: {
    payment_confirmed: ["active"],
    admin_granted: ["active"],
    period_ended: ["grace_period"],
    renewal_canceled: ["canceled"],
    payment_refunded: ["refunded"],
    admin_suspended: ["suspended"],
  },
  grace_period: {
    payment_confirmed: ["active"],
    admin_granted: ["active"],
    grace_ended: ["expired"],
    payment_refunded: ["refunded"],
    admin_suspended: ["suspended"],
  },
  expired: {
    payment_confirmed: ["active"],
    admin_granted: ["active"],
    payment_refunded: ["refunded"],
    admin_suspended: ["suspended"],
  },
  canceled: {
    // Un prélèvement carte arrivé après l'annulation (événements dans le désordre) prolonge
    // la période sans réactiver le renouvellement : le statut reste « canceled ».
    payment_confirmed: ["active", "canceled"],
    admin_granted: ["active"],
    period_ended: ["expired"],
    payment_refunded: ["refunded"],
    admin_suspended: ["suspended"],
  },
  refunded: {
    payment_confirmed: ["active"],
    admin_granted: ["active"],
    admin_suspended: ["suspended"],
  },
  suspended: {
    admin_granted: ["active"],
    admin_reactivated: ["active", "renewal_due", "grace_period", "expired"],
  },
};

export function canTransition(from: SubscriptionStatus, event: SubscriptionEvent, to: SubscriptionStatus): boolean {
  return TRANSITIONS[from]?.[event]?.includes(to) ?? false;
}

export function assertTransition(from: SubscriptionStatus, event: SubscriptionEvent, to: SubscriptionStatus): void {
  if (!canTransition(from, event, to)) throw new InvalidTransitionError(from, event, to);
}

/** Statuts qui donnent accès aux salons privés (rôle Discord). */
export const ACCESS_STATUSES: readonly SubscriptionStatus[] = ["active", "renewal_due", "grace_period", "canceled"];

export function hasAccess(status: SubscriptionStatus | null | undefined): boolean {
  return status != null && ACCESS_STATUSES.includes(status);
}

export const STATUS_LABELS: Record<SubscriptionStatus, string> = {
  pending_payment: "En attente de paiement",
  active: "Actif",
  renewal_due: "Renouvellement proche",
  grace_period: "Période de grâce",
  expired: "Expiré",
  canceled: "Renouvellement annulé",
  refunded: "Remboursé",
  suspended: "Suspendu",
};

export interface TimeContext {
  status: SubscriptionStatus;
  currentPeriodEnd: Date | null;
  graceEndsAt: Date | null;
}

/**
 * Prochaine transition liée au temps (exécutée par le worker), ou null.
 * renewalWindowDays : nombre de jours avant l'échéance où l'abonnement passe en « renewal_due ».
 */
export function nextTimeTransition(
  sub: TimeContext,
  now: Date,
  renewalWindowDays: number,
): { event: SubscriptionEvent; to: SubscriptionStatus } | null {
  const end = sub.currentPeriodEnd?.getTime();
  const t = now.getTime();
  if (end === undefined) return null;
  switch (sub.status) {
    case "active":
      if (t >= end) return { event: "period_ended", to: "grace_period" };
      if (t >= end - renewalWindowDays * 86_400_000) return { event: "renewal_window_reached", to: "renewal_due" };
      return null;
    case "renewal_due":
      return t >= end ? { event: "period_ended", to: "grace_period" } : null;
    case "canceled":
      return t >= end ? { event: "period_ended", to: "expired" } : null;
    case "grace_period": {
      const grace = sub.graceEndsAt?.getTime() ?? end;
      return t >= grace ? { event: "grace_ended", to: "expired" } : null;
    }
    default:
      return null;
  }
}

/** Statut à appliquer quand l'admin lève une suspension, selon les dates de la période payée. */
export function statusAfterReactivation(sub: TimeContext, now: Date, renewalWindowDays: number): SubscriptionStatus {
  const end = sub.currentPeriodEnd?.getTime();
  if (end === undefined) return "expired";
  const t = now.getTime();
  if (t < end - renewalWindowDays * 86_400_000) return "active";
  if (t < end) return "renewal_due";
  if (t < (sub.graceEndsAt?.getTime() ?? end)) return "grace_period";
  return "expired";
}
