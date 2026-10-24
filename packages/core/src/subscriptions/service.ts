import { and, eq, inArray, lte, or, sql } from "drizzle-orm";
import {
  members,
  payments,
  subscriptionPeriods,
  subscriptions,
  type Db,
  type Member,
  type Payment,
  type Subscription,
} from "@vk/db";
import { audit, type ActorType } from "../audit";
import { CLUB, getPlan, PLANS, type PlanId } from "../config/club";
import { addDays, computeGrantedPeriod, computePaidPeriod, formatDate, formatXof, graceEnd } from "../dates";
import type { CoreDeps } from "../deps";
import { DomainError } from "../errors";
import { notifyMember, postLog, requestAccessSync } from "../outbox";
import type { VerifiedPayment } from "../payments/types";
import {
  assertTransition,
  hasAccess,
  nextTimeTransition,
  STATUS_LABELS,
  type SubscriptionEvent,
  type SubscriptionStatus,
} from "../state-machine";

type Deps = Pick<CoreDeps, "db" | "now" | "logger">;

export const RENEWAL_WINDOW_DAYS = Math.max(0, ...CLUB.reminderOffsetsDays);

const mention = (discordUserId: string) => `<@${discordUserId}>`;

// ─── Membres ────────────────────────────────────────────────────────────────

export interface DiscordIdentity {
  discordUserId: string;
  username?: string | null;
  email?: string | null;
  emailVerified?: boolean;
  name?: string | null;
  phone?: string | null;
}

/** Crée ou met à jour un membre à partir de son identité Discord (n'efface jamais un email connu). */
export async function upsertMember(db: Db, input: DiscordIdentity, now: Date): Promise<Member> {
  const [row] = await db
    .insert(members)
    .values({
      discordUserId: input.discordUserId,
      discordUsername: input.username ?? null,
      email: input.email ?? null,
      emailVerified: input.emailVerified ?? false,
      name: input.name ?? null,
      phone: input.phone ?? null,
      createdAt: now,
      updatedAt: now,
    })
    .onConflictDoUpdate({
      target: members.discordUserId,
      set: {
        discordUsername: sql`coalesce(excluded.discord_username, ${members.discordUsername})`,
        email: sql`coalesce(excluded.email, ${members.email})`,
        emailVerified: sql`case when excluded.email is not null then excluded.email_verified else ${members.emailVerified} end`,
        name: sql`coalesce(excluded.name, ${members.name})`,
        phone: sql`coalesce(excluded.phone, ${members.phone})`,
        updatedAt: now,
      },
    })
    .returning();
  return row!;
}

export async function findMemberByDiscordId(db: Db, discordUserId: string): Promise<Member | null> {
  const [row] = await db.select().from(members).where(eq(members.discordUserId, discordUserId));
  return row ?? null;
}

export async function getMember(db: Db, memberId: string): Promise<Member | null> {
  const [row] = await db.select().from(members).where(eq(members.id, memberId));
  return row ?? null;
}

export async function getSubscriptionForMember(db: Db, memberId: string): Promise<Subscription | null> {
  const [row] = await db.select().from(subscriptions).where(eq(subscriptions.memberId, memberId));
  return row ?? null;
}

/** Retourne l'abonnement du membre, en le créant (pending_payment) s'il n'existe pas. */
export async function ensureSubscription(db: Db, memberId: string, planId: PlanId, now: Date): Promise<Subscription> {
  await db
    .insert(subscriptions)
    .values({ memberId, planId, status: "pending_payment", statusChangedAt: now, createdAt: now, updatedAt: now })
    .onConflictDoNothing({ target: subscriptions.memberId });
  return (await getSubscriptionForMember(db, memberId))!;
}

async function lockSubscription(tx: Db, subscriptionId: string): Promise<Subscription> {
  const [row] = await tx.select().from(subscriptions).where(eq(subscriptions.id, subscriptionId)).for("update");
  if (!row) throw new DomainError("not_found", "Abonnement introuvable");
  return row;
}

const status = (s: Subscription) => s.status as SubscriptionStatus;

async function applyStatus(
  tx: Db,
  sub: Subscription,
  event: SubscriptionEvent,
  to: SubscriptionStatus,
  now: Date,
  changes: Partial<typeof subscriptions.$inferInsert> = {},
  reason?: string,
): Promise<Subscription> {
  assertTransition(status(sub), event, to);
  const statusChanged = sub.status !== to;
  const [updated] = await tx
    .update(subscriptions)
    .set({
      ...changes,
      status: to,
      statusReason: reason ?? event,
      ...(statusChanged ? { statusChangedAt: now } : {}),
      updatedAt: now,
    })
    .where(eq(subscriptions.id, sub.id))
    .returning();
  return updated!;
}

// ─── Paiements ──────────────────────────────────────────────────────────────

/** Compare la vérification serveur à serveur avec le paiement attendu. null = conforme. */
export function verificationMismatch(payment: Payment, verified: VerifiedPayment): string | null {
  if (verified.status !== "succeeded") return `statut chez le prestataire : ${verified.status}`;
  if (payment.kind !== "recurring" && verified.reference && verified.reference !== payment.reference) {
    return `référence ${verified.reference} ≠ ${payment.reference}`;
  }
  if (verified.amount !== payment.amount) return `montant ${verified.amount} ≠ ${payment.amount} attendu`;
  if (verified.currency.toUpperCase() !== payment.currency.toUpperCase()) {
    return `devise ${verified.currency} ≠ ${payment.currency}`;
  }
  return null;
}

export interface ConfirmPaymentResult {
  applied: boolean;
  reason?: "already_applied" | "mismatch";
  detail?: string;
  subscription?: Subscription;
  firstActivation?: boolean;
}

/**
 * Applique un paiement vérifié : prolonge la période (une seule fois grâce à la contrainte
 * d'unicité sur payment_id), fait évoluer la machine à états, puis programme rôle,
 * notifications et log dans la même transaction.
 */
export async function confirmPayment(deps: Deps, paymentId: string, verified: VerifiedPayment): Promise<ConfirmPaymentResult> {
  const now = deps.now();
  return deps.db.transaction(async (tx) => {
    const [payment] = await tx.select().from(payments).where(eq(payments.id, paymentId)).for("update");
    if (!payment) throw new DomainError("not_found", "Paiement introuvable");
    if (payment.status === "succeeded" || payment.status === "refunded") {
      return { applied: false, reason: "already_applied" as const };
    }

    const mismatch = verificationMismatch(payment, verified);
    if (mismatch) {
      await tx
        .update(payments)
        .set({ status: "failed", failureReason: `Vérification refusée : ${mismatch}`, verification: verified.raw as object })
        .where(eq(payments.id, payment.id));
      await audit(tx, {
        actorType: "provider",
        actorId: payment.provider,
        action: "payment.verification_mismatch",
        memberId: payment.memberId,
        details: { reference: payment.reference, mismatch },
      }, now);
      await postLog(tx, `⚠️ Paiement refusé à la vérification (${payment.reference}) : ${mismatch}`);
      return { applied: false, reason: "mismatch" as const, detail: mismatch };
    }

    const sub = await lockSubscription(tx, payment.subscriptionId);
    const plan = getPlan(payment.planId);
    const from = status(sub);
    const period = computePaidPeriod(sub, plan.months, now);

    await tx.insert(subscriptionPeriods).values({
      subscriptionId: sub.id,
      planId: plan.id,
      startsAt: period.start,
      endsAt: period.end,
      source: "payment",
      paymentId: payment.id,
      createdAt: now,
    });

    const isRecurring = payment.kind === "recurring";
    const changes: Partial<typeof subscriptions.$inferInsert> = {
      planId: plan.id,
      currentPeriodStart: period.start,
      currentPeriodEnd: period.end,
      graceEndsAt: graceEnd(period.end),
      anchorDay: period.anchorDay,
    };
    if (payment.autoRenew) {
      changes.renewalMode = "auto_card";
      changes.provider = payment.provider;
      changes.providerSubscriptionId = verified.providerSubscriptionId ?? sub.providerSubscriptionId;
      changes.providerPlanId = verified.providerPlanId ?? sub.providerPlanId;
    }

    let updated: Subscription;
    if (from === "suspended") {
      // Membre suspendu par l'admin : on enregistre la période payée sans rendre l'accès.
      [updated] = (await tx
        .update(subscriptions)
        .set({ ...changes, updatedAt: now })
        .where(eq(subscriptions.id, sub.id))
        .returning()) as [Subscription];
      await postLog(tx, `⚠️ Paiement reçu d'un membre suspendu (${payment.reference}) : accès non rétabli, à traiter.`);
    } else {
      // Prélèvement carte arrivé après une annulation : la période est prolongée, l'annulation reste.
      const keepCanceled = from === "canceled" && isRecurring;
      const to: SubscriptionStatus = keepCanceled ? "canceled" : "active";
      if (!keepCanceled) changes.renewalCanceledAt = null;
      updated = await applyStatus(tx, sub, "payment_confirmed", to, now, changes, `paiement ${payment.reference}`);
    }

    await tx
      .update(payments)
      .set({
        status: "succeeded",
        confirmedAt: now,
        providerTransactionId: verified.providerTransactionId ?? payment.providerTransactionId,
        verification: verified.raw as object,
      })
      .where(eq(payments.id, payment.id));

    const [member] = await tx.select().from(members).where(eq(members.id, payment.memberId));
    const firstActivation = !period.continued;
    await audit(tx, {
      actorType: "provider",
      actorId: payment.provider,
      action: "payment.confirmed",
      memberId: payment.memberId,
      details: {
        reference: payment.reference,
        amount: payment.amount,
        currency: payment.currency,
        plan: plan.id,
        from,
        to: updated.status,
        periodStart: period.start.toISOString(),
        periodEnd: period.end.toISOString(),
      },
    }, now);
    await requestAccessSync(tx, payment.memberId);
    await notifyMember(tx, payment.memberId, firstActivation ? "welcome" : "renewed", {
      periodEnd: period.end.toISOString(),
      planId: plan.id,
    });
    const icon = firstActivation ? "✅ Nouvel abonné" : "🔁 Renouvellement";
    await postLog(
      tx,
      `${icon} : ${mention(member!.discordUserId)} · ${plan.label} · ${formatXof(payment.amount)} (${payment.provider}, ${payment.method}${payment.autoRenew ? ", prélèvement auto" : ""}) · accès jusqu'au ${formatDate(period.end)}`,
    );
    return { applied: true, subscription: updated, firstActivation };
  });
}

/** Marque un paiement en attente comme échoué. Ne rétrograde jamais un paiement réussi. */
export async function markPaymentFailed(db: Db, paymentId: string, reason: string, raw?: unknown): Promise<boolean> {
  const rows = await db
    .update(payments)
    .set({ status: "failed", failureReason: reason, ...(raw ? { verification: raw as object } : {}) })
    .where(and(eq(payments.id, paymentId), eq(payments.status, "pending")))
    .returning({ id: payments.id });
  return rows.length > 0;
}

// ─── Transitions liées au temps ─────────────────────────────────────────────

export interface TimeTransitionChange {
  subscriptionId: string;
  memberId: string;
  from: SubscriptionStatus;
  to: SubscriptionStatus;
}

/** Fait avancer tous les abonnements dont l'échéance est atteinte (idempotent, rattrape les retards). */
export async function applyTimeTransitions(deps: Deps): Promise<TimeTransitionChange[]> {
  const now = deps.now();
  const windowLimit = addDays(now, RENEWAL_WINDOW_DAYS);
  const candidates = await deps.db
    .select({ id: subscriptions.id })
    .from(subscriptions)
    .where(
      or(
        and(eq(subscriptions.status, "active"), lte(subscriptions.currentPeriodEnd, windowLimit)),
        and(inArray(subscriptions.status, ["renewal_due", "canceled"]), lte(subscriptions.currentPeriodEnd, now)),
        and(
          eq(subscriptions.status, "grace_period"),
          sql`coalesce(${subscriptions.graceEndsAt}, ${subscriptions.currentPeriodEnd}) <= ${now.toISOString()}::timestamptz`,
        ),
      ),
    );

  const changes: TimeTransitionChange[] = [];
  for (const { id } of candidates) {
    const change = await deps.db.transaction(async (tx) => {
      let sub = await lockSubscription(tx, id);
      const from = status(sub);
      const visited: SubscriptionStatus[] = [];
      for (let i = 0; i < 4; i++) {
        const next = nextTimeTransition(
          { status: status(sub), currentPeriodEnd: sub.currentPeriodEnd, graceEndsAt: sub.graceEndsAt },
          now,
          RENEWAL_WINDOW_DAYS,
        );
        if (!next) break;
        sub = await applyStatus(tx, sub, next.event, next.to, now);
        visited.push(next.to);
      }
      if (visited.length === 0) return null;
      const to = status(sub);
      const [member] = await tx.select().from(members).where(eq(members.id, sub.memberId));
      if (visited.includes("grace_period") && to === "grace_period") {
        await notifyMember(tx, sub.memberId, "grace_started", {
          periodEnd: sub.currentPeriodEnd?.toISOString(),
          graceEndsAt: sub.graceEndsAt?.toISOString(),
        });
        await postLog(tx, `⏳ Période de grâce : ${mention(member!.discordUserId)} · fin d'accès le ${formatDate(sub.graceEndsAt!)}`);
      }
      if (to === "expired") {
        await requestAccessSync(tx, sub.memberId);
        await notifyMember(tx, sub.memberId, "expired", { periodEnd: sub.currentPeriodEnd?.toISOString() });
        await postLog(tx, `⛔ Accès expiré : ${mention(member!.discordUserId)} (${from === "canceled" ? "renouvellement annulé" : "non renouvelé"}) · retrait du rôle programmé`);
      }
      await audit(tx, {
        actorType: "system",
        action: "subscription.time_transition",
        memberId: sub.memberId,
        details: { from, to, path: visited },
      }, now);
      return { subscriptionId: sub.id, memberId: sub.memberId, from, to };
    });
    if (change) changes.push(change);
  }
  return changes;
}

// ─── Annulation et remboursement ────────────────────────────────────────────

export interface Actor {
  type: ActorType;
  id?: string | null;
}

/**
 * Applique l'annulation du renouvellement (le prélèvement chez le prestataire doit déjà être annulé).
 * Actif → canceled (accès jusqu'à la fin de la période payée).
 * En grâce → reste en grâce, passe en renouvellement manuel (il peut encore payer par Mobile Money).
 */
export async function markRenewalCanceled(deps: Deps, subscriptionId: string, actor: Actor, source: string): Promise<Subscription> {
  const now = deps.now();
  return deps.db.transaction(async (tx) => {
    const sub = await lockSubscription(tx, subscriptionId);
    const from = status(sub);
    const changes = { renewalMode: "manual" as const, renewalCanceledAt: now };
    let updated: Subscription;
    if (from === "active" || from === "renewal_due") {
      updated = await applyStatus(tx, sub, "renewal_canceled", "canceled", now, changes, source);
    } else {
      [updated] = (await tx
        .update(subscriptions)
        .set({ ...changes, updatedAt: now })
        .where(eq(subscriptions.id, sub.id))
        .returning()) as [Subscription];
    }
    const [member] = await tx.select().from(members).where(eq(members.id, sub.memberId));
    await audit(tx, { actorType: actor.type, actorId: actor.id, action: "subscription.renewal_canceled", memberId: sub.memberId, details: { from, to: updated.status, source } }, now);
    await notifyMember(tx, sub.memberId, "renewal_canceled", { periodEnd: sub.currentPeriodEnd?.toISOString() });
    await postLog(tx, `🛑 Renouvellement annulé : ${mention(member!.discordUserId)} (${source}) · accès conservé jusqu'au ${sub.currentPeriodEnd ? formatDate(sub.currentPeriodEnd) : "—"}`);
    return updated;
  });
}

/** Annulation demandée par le membre (espace membre) ou l'admin. */
export async function cancelRenewal(deps: CoreDeps, memberId: string, actor: Actor): Promise<Subscription> {
  const sub = await getSubscriptionForMember(deps.db, memberId);
  if (!sub) throw new DomainError("no_subscription", "Aucun abonnement à annuler");
  if (!hasAccess(status(sub)) || sub.status === "canceled") {
    throw new DomainError("not_cancelable", `Abonnement « ${STATUS_LABELS[status(sub)]} » : rien à annuler`);
  }
  if (sub.renewalMode === "auto_card") {
    if (!sub.provider || !sub.providerSubscriptionId) {
      await postLog(deps.db, `⚠️ Annulation demandée sans identifiant d'abonnement prestataire (membre ${memberId}) : à annuler à la main dans le dashboard.`);
      throw new DomainError("provider_subscription_unknown", "Annulation automatique impossible pour le moment. Contacte le support : nous l'annulons manuellement.");
    }
    // Le prélèvement doit être annulé chez le prestataire AVANT de changer notre état.
    await deps.providers.get(sub.provider).cancelSubscription(sub.providerSubscriptionId);
  }
  return markRenewalCanceled(deps, sub.id, actor, actor.type === "admin" ? "admin" : "espace membre");
}

/** Webhook « abonnement annulé » reçu du prestataire. */
export async function applyProviderCancellation(
  deps: Deps,
  provider: string,
  ref: { providerSubscriptionId?: string; customerEmail?: string },
): Promise<Subscription | null> {
  let sub: Subscription | undefined;
  if (ref.providerSubscriptionId) {
    [sub] = await deps.db
      .select()
      .from(subscriptions)
      .where(and(eq(subscriptions.provider, provider), eq(subscriptions.providerSubscriptionId, ref.providerSubscriptionId)));
  }
  if (!sub && ref.customerEmail) {
    const rows = await deps.db
      .select({ sub: subscriptions })
      .from(subscriptions)
      .innerJoin(members, eq(members.id, subscriptions.memberId))
      .where(and(eq(subscriptions.provider, provider), eq(subscriptions.renewalMode, "auto_card"), sql`lower(${members.email}) = lower(${ref.customerEmail})`));
    if (rows.length === 1) sub = rows[0]!.sub;
  }
  if (!sub || sub.renewalMode !== "auto_card") return null;
  return markRenewalCanceled(deps, sub.id, { type: "provider", id: provider }, `annulé chez ${provider}`);
}

/** Remboursement confirmé : si le paiement couvre la période en cours, l'accès est retiré. */
export async function applyRefund(deps: Deps, paymentId: string, actor: Actor): Promise<Subscription | null> {
  const now = deps.now();
  return deps.db.transaction(async (tx) => {
    const [payment] = await tx.select().from(payments).where(eq(payments.id, paymentId)).for("update");
    if (!payment || payment.status === "refunded") return null;
    await tx.update(payments).set({ status: "refunded", refundedAt: now }).where(eq(payments.id, payment.id));
    const sub = await lockSubscription(tx, payment.subscriptionId);
    const [period] = await tx.select().from(subscriptionPeriods).where(eq(subscriptionPeriods.paymentId, payment.id));
    let updated = sub;
    const coversCurrent = period && sub.currentPeriodEnd && period.endsAt.getTime() === sub.currentPeriodEnd.getTime();
    if (coversCurrent && status(sub) !== "suspended" && status(sub) !== "refunded" && status(sub) !== "pending_payment") {
      updated = await applyStatus(tx, sub, "payment_refunded", "refunded", now, {
        currentPeriodEnd: period.startsAt,
        graceEndsAt: period.startsAt,
      });
      await requestAccessSync(tx, sub.memberId);
    }
    await audit(tx, { actorType: actor.type, actorId: actor.id, action: "payment.refunded", memberId: payment.memberId, details: { reference: payment.reference, amount: payment.amount } }, now);
    await postLog(tx, `↩️ Remboursement : ${payment.reference} (${formatXof(payment.amount)})${coversCurrent ? " · accès retiré" : ""}`);
    return updated;
  });
}

// ─── Actions admin ──────────────────────────────────────────────────────────

export interface AdminGrantInput {
  discordUserId: string;
  username?: string | null;
  days?: number;
  planId?: PlanId;
  adminId: string;
  note?: string;
}

/** /ajouter : prolonge l'accès de N jours ou d'une formule (paiement manuel, geste commercial…). */
export async function adminGrant(deps: Deps, input: AdminGrantInput): Promise<Subscription> {
  const now = deps.now();
  if (!input.planId && (!input.days || input.days < 1 || input.days > 400)) {
    throw new DomainError("invalid_days", "Indique un nombre de jours entre 1 et 400, ou une formule");
  }
  const member = await upsertMember(deps.db, { discordUserId: input.discordUserId, username: input.username }, now);
  const sub0 = await ensureSubscription(deps.db, member.id, input.planId ?? "monthly", now);
  return deps.db.transaction(async (tx) => {
    const sub = await lockSubscription(tx, sub0.id);
    const from = status(sub);
    const plan = input.planId ? PLANS[input.planId] : null;
    const period = plan ? computePaidPeriod(sub, plan.months, now) : computeGrantedPeriod(sub, input.days!, now);
    await tx.insert(subscriptionPeriods).values({
      subscriptionId: sub.id,
      planId: plan?.id ?? null,
      startsAt: period.start,
      endsAt: period.end,
      source: "admin",
      days: plan ? null : input.days!,
      createdBy: input.adminId,
      note: input.note ?? null,
      createdAt: now,
    });
    const updated = await applyStatus(tx, sub, "admin_granted", "active", now, {
      ...(plan ? { planId: plan.id } : {}),
      currentPeriodStart: period.start,
      currentPeriodEnd: period.end,
      graceEndsAt: graceEnd(period.end),
      anchorDay: period.anchorDay,
      renewalCanceledAt: null,
    }, `ajout admin${input.note ? ` : ${input.note}` : ""}`);
    const what = plan ? `formule ${plan.label}` : `${input.days} jour(s)`;
    await audit(tx, { actorType: "admin", actorId: input.adminId, action: "subscription.admin_granted", memberId: member.id, details: { what, from, periodEnd: period.end.toISOString(), note: input.note } }, now);
    await requestAccessSync(tx, member.id);
    await notifyMember(tx, member.id, "admin_granted", { periodEnd: period.end.toISOString() });
    await postLog(tx, `➕ Accès ajouté par ${mention(input.adminId)} : ${mention(input.discordUserId)} · ${what} · jusqu'au ${formatDate(period.end)}${input.note ? ` · ${input.note}` : ""}`);
    return updated;
  });
}

/** /retirer : suspend l'accès immédiatement (rôle retiré). */
export async function adminSuspend(deps: Deps, input: { discordUserId: string; adminId: string; reason?: string }): Promise<Subscription> {
  const now = deps.now();
  const member = await findMemberByDiscordId(deps.db, input.discordUserId);
  const sub0 = member ? await getSubscriptionForMember(deps.db, member.id) : null;
  if (!member || !sub0) throw new DomainError("no_subscription", "Ce membre n'a pas d'abonnement enregistré");
  return deps.db.transaction(async (tx) => {
    const sub = await lockSubscription(tx, sub0.id);
    if (sub.status === "suspended") return sub;
    const updated = await applyStatus(tx, sub, "admin_suspended", "suspended", now, {}, input.reason ?? "retrait admin");
    await audit(tx, { actorType: "admin", actorId: input.adminId, action: "subscription.admin_suspended", memberId: member.id, details: { from: sub.status, reason: input.reason } }, now);
    await requestAccessSync(tx, member.id);
    await postLog(tx, `🚫 Accès retiré par ${mention(input.adminId)} : ${mention(input.discordUserId)}${input.reason ? ` · ${input.reason}` : ""}`);
    return updated;
  });
}
