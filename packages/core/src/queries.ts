import { and, count, desc, eq, gte, inArray, lte, sum } from "drizzle-orm";
import { members, payments, subscriptionPeriods, subscriptions, type Db } from "@vk/db";
import { getPlan, isPlanId } from "./config/club";
import { addDays } from "./dates";
import { ACCESS_STATUSES, type SubscriptionStatus } from "./state-machine";

/** Fiche d'un membre (commande /abonne). */
export async function getMemberOverview(db: Db, discordUserId: string) {
  const [row] = await db
    .select({ member: members, subscription: subscriptions })
    .from(members)
    .leftJoin(subscriptions, eq(subscriptions.memberId, members.id))
    .where(eq(members.discordUserId, discordUserId));
  if (!row) return null;
  const lastPayments = await db
    .select()
    .from(payments)
    .where(eq(payments.memberId, row.member.id))
    .orderBy(desc(payments.createdAt))
    .limit(5);
  return { ...row, lastPayments };
}

/** Espace membre : uniquement les données du membre connecté. */
export async function getMemberDashboard(db: Db, memberId: string) {
  const [row] = await db
    .select({ member: members, subscription: subscriptions })
    .from(members)
    .leftJoin(subscriptions, eq(subscriptions.memberId, members.id))
    .where(eq(members.id, memberId));
  if (!row) return null;
  const history = await db
    .select()
    .from(payments)
    .where(and(eq(payments.memberId, memberId), inArray(payments.status, ["succeeded", "refunded", "pending"])))
    .orderBy(desc(payments.createdAt))
    .limit(50);
  const periods = row.subscription
    ? await db
        .select()
        .from(subscriptionPeriods)
        .where(eq(subscriptionPeriods.subscriptionId, row.subscription.id))
        .orderBy(desc(subscriptionPeriods.endsAt))
        .limit(50)
    : [];
  return { ...row, history, periods };
}

/** Abonnés dont l'accès se termine dans les `days` prochains jours (commande /expirations). */
export async function listExpiring(db: Db, now: Date, days: number) {
  return db
    .select({
      discordUserId: members.discordUserId,
      username: members.discordUsername,
      status: subscriptions.status,
      renewalMode: subscriptions.renewalMode,
      planId: subscriptions.planId,
      currentPeriodEnd: subscriptions.currentPeriodEnd,
    })
    .from(subscriptions)
    .innerJoin(members, eq(members.id, subscriptions.memberId))
    .where(
      and(
        inArray(subscriptions.status, [...ACCESS_STATUSES]),
        lte(subscriptions.currentPeriodEnd, addDays(now, days)),
      ),
    )
    .orderBy(subscriptions.currentPeriodEnd);
}

export interface ClubStats {
  byStatus: Partial<Record<SubscriptionStatus, number>>;
  withAccess: number;
  autoRenew: number;
  revenue30d: number;
  payments30d: number;
  /** Encaissement prévisionnel des 30 prochains jours (échéances × prix de la formule). */
  forecast30d: number;
}

/** Chiffres clés (commande /stats). Montants en XOF. */
export async function getStats(db: Db, now: Date): Promise<ClubStats> {
  const statusRows = await db.select({ status: subscriptions.status, n: count() }).from(subscriptions).groupBy(subscriptions.status);
  const byStatus: Partial<Record<SubscriptionStatus, number>> = {};
  for (const r of statusRows) byStatus[r.status as SubscriptionStatus] = Number(r.n);
  const withAccess = ACCESS_STATUSES.reduce((acc, s) => acc + (byStatus[s] ?? 0), 0);

  const [auto] = await db
    .select({ n: count() })
    .from(subscriptions)
    .where(and(eq(subscriptions.renewalMode, "auto_card"), inArray(subscriptions.status, ["active", "renewal_due", "grace_period"])));

  const [revenue] = await db
    .select({ total: sum(payments.amount), n: count() })
    .from(payments)
    .where(and(eq(payments.status, "succeeded"), gte(payments.confirmedAt, addDays(now, -30))));

  const upcoming = await db
    .select({ planId: subscriptions.planId })
    .from(subscriptions)
    .where(
      and(
        inArray(subscriptions.status, ["active", "renewal_due", "grace_period"]),
        lte(subscriptions.currentPeriodEnd, addDays(now, 30)),
        gte(subscriptions.currentPeriodEnd, addDays(now, -3)),
      ),
    );
  const forecast30d = upcoming.reduce((acc, r) => acc + (isPlanId(r.planId) ? getPlan(r.planId).priceXof : 0), 0);

  return {
    byStatus,
    withAccess,
    autoRenew: Number(auto?.n ?? 0),
    revenue30d: Number(revenue?.total ?? 0),
    payments30d: Number(revenue?.n ?? 0),
    forecast30d,
  };
}
