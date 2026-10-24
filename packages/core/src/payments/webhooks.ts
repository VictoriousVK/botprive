import { and, eq, sql } from "drizzle-orm";
import { members, payments, subscriptions, webhookEvents, type Payment, type Subscription } from "@vk/db";
import { CLUB, getPlan } from "../config/club";
import type { CoreDeps } from "../deps";
import { InvalidSignatureError } from "../errors";
import { postLog } from "../outbox";
import { applyProviderCancellation, applyRefund, confirmPayment, markPaymentFailed } from "../subscriptions/service";
import type { NormalizedWebhookEvent, PaymentProvider, VerifiedPayment } from "./types";

/*
 * Traitement des webhooks, dans cet ordre :
 *   1. signature vérifiée (sinon 401, rien n'est écrit) ;
 *   2. idempotence : (prestataire, clé d'événement) unique en base, un doublon déjà traité répond 200 sans effet ;
 *   3. re-vérification serveur à serveur (montant, devise, référence, formule) : l'événement n'est qu'un signal ;
 *   4. application dans une transaction (une période par paiement, contrainte d'unicité).
 * En cas d'erreur interne, on répond 500 : le prestataire renverra l'événement.
 * L'ordre d'arrivée n'a pas d'importance : l'état final dépend de la vérification serveur.
 */

export interface WebhookHttpResult {
  httpStatus: number;
  body: Record<string, unknown>;
}

type ProcessStatus = "processed" | "ignored" | "unmatched";

export async function handleWebhook(
  deps: CoreDeps,
  providerId: string,
  request: { headers: Record<string, string>; rawBody: string },
): Promise<WebhookHttpResult> {
  if (!deps.providers.has(providerId)) return { httpStatus: 404, body: { error: "unknown_provider" } };
  const provider = deps.providers.get(providerId);
  const now = deps.now();

  let event: NormalizedWebhookEvent;
  try {
    event = await provider.handleWebhook({ headers: request.headers, rawBody: request.rawBody, now });
  } catch (error) {
    if (error instanceof InvalidSignatureError) {
      deps.logger.warn(`Webhook ${providerId} rejeté : ${error.message}`);
      return { httpStatus: 401, body: { error: "invalid_signature" } };
    }
    throw error;
  }

  const inserted = await deps.db
    .insert(webhookEvents)
    .values({ provider: provider.id, eventKey: event.eventKey, eventType: event.eventType, payload: event.payload as object, receivedAt: now })
    .onConflictDoNothing({ target: [webhookEvents.provider, webhookEvents.eventKey] })
    .returning({ id: webhookEvents.id });

  let eventId = inserted[0]?.id;
  if (!eventId) {
    const [existing] = await deps.db
      .select()
      .from(webhookEvents)
      .where(and(eq(webhookEvents.provider, provider.id), eq(webhookEvents.eventKey, event.eventKey)));
    if (existing && existing.status !== "received" && existing.status !== "error") {
      return { httpStatus: 200, body: { ok: true, duplicate: true } };
    }
    eventId = existing!.id;
    await deps.db.update(webhookEvents).set({ attempts: sql`${webhookEvents.attempts} + 1` }).where(eq(webhookEvents.id, eventId));
  }

  try {
    const result = await processEvent(deps, provider, event);
    await deps.db
      .update(webhookEvents)
      .set({ status: result.status, processedAt: deps.now(), error: result.note ?? null })
      .where(eq(webhookEvents.id, eventId));
    return { httpStatus: 200, body: { ok: true, result: result.status } };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await deps.db.update(webhookEvents).set({ status: "error", error: message }).where(eq(webhookEvents.id, eventId));
    deps.logger.error(`Webhook ${providerId} ${event.eventType} en erreur : ${message}`);
    return { httpStatus: 500, body: { error: "processing_failed" } };
  }
}

async function processEvent(
  deps: CoreDeps,
  provider: PaymentProvider,
  event: NormalizedWebhookEvent,
): Promise<{ status: ProcessStatus; note?: string }> {
  switch (event.kind) {
    case "ignored":
      return { status: "ignored" };
    case "payment":
      return processPaymentEvent(deps, provider, event);
    case "subscription_canceled": {
      const sub = await applyProviderCancellation(deps, provider.id, {
        providerSubscriptionId: event.providerSubscriptionId,
        customerEmail: event.customerEmail,
      });
      return sub ? { status: "processed" } : { status: "unmatched", note: "abonnement introuvable ou déjà en manuel" };
    }
    case "refund": {
      const payment = await findPayment(deps, provider.id, event);
      if (!payment) return { status: "unmatched", note: "paiement remboursé introuvable" };
      await applyRefund(deps, payment.id, { type: "provider", id: provider.id });
      return { status: "processed" };
    }
  }
}

async function findPayment(
  deps: CoreDeps,
  providerId: string,
  ref: { providerTransactionId?: string; reference?: string; providerCheckoutId?: string },
): Promise<Payment | null> {
  if (ref.providerTransactionId) {
    const [row] = await deps.db
      .select()
      .from(payments)
      .where(and(eq(payments.provider, providerId), eq(payments.providerTransactionId, ref.providerTransactionId)));
    if (row) return row;
  }
  if (ref.reference) {
    const [row] = await deps.db
      .select()
      .from(payments)
      .where(and(eq(payments.provider, providerId), eq(payments.reference, ref.reference)));
    if (row) return row;
  }
  if (ref.providerCheckoutId) {
    const [row] = await deps.db
      .select()
      .from(payments)
      .where(and(eq(payments.provider, providerId), eq(payments.providerCheckoutId, ref.providerCheckoutId)));
    if (row) return row;
  }
  return null;
}

async function processPaymentEvent(
  deps: CoreDeps,
  provider: PaymentProvider,
  event: Extract<NormalizedWebhookEvent, { kind: "payment" }>,
): Promise<{ status: ProcessStatus; note?: string }> {
  let payment = await findPayment(deps, provider.id, event);

  // Un prélèvement récurrent peut porter la référence du premier paiement : nouvelle transaction = nouveau paiement.
  if (
    payment &&
    payment.autoRenew &&
    payment.status === "succeeded" &&
    event.providerTransactionId &&
    payment.providerTransactionId &&
    payment.providerTransactionId !== event.providerTransactionId
  ) {
    payment = null;
  }

  if (!payment) {
    if (provider.capabilities.recurring && event.providerTransactionId) {
      return processRecurringCharge(deps, provider, event.providerTransactionId, event.reference);
    }
    await postLog(deps.db, `⚠️ Webhook ${provider.id} sans paiement correspondant (réf. ${event.reference ?? "?"}) : à vérifier.`);
    return { status: "unmatched", note: "aucun paiement correspondant" };
  }
  if (payment.status !== "pending") return { status: "processed", note: `déjà ${payment.status}` };

  const verified = await verifyWithProvider(deps, provider, payment, event);
  return applyVerification(deps, payment, verified);
}

async function verifyWithProvider(
  deps: CoreDeps,
  provider: PaymentProvider,
  payment: Payment,
  hint: { providerTransactionId?: string; providerCheckoutId?: string } = {},
): Promise<VerifiedPayment> {
  const [member] = await deps.db.select({ email: members.email }).from(members).where(eq(members.id, payment.memberId));
  return provider.verifyPayment({
    reference: payment.reference,
    providerTransactionId: hint.providerTransactionId ?? payment.providerTransactionId,
    providerCheckoutId: hint.providerCheckoutId ?? payment.providerCheckoutId,
    expectSubscription: payment.autoRenew,
    customerEmail: member?.email,
  });
}

async function applyVerification(
  deps: CoreDeps,
  payment: Payment,
  verified: VerifiedPayment,
): Promise<{ status: ProcessStatus; note?: string }> {
  if (verified.status === "succeeded") {
    const result = await confirmPayment(deps, payment.id, verified);
    return { status: "processed", note: result.applied ? undefined : result.reason === "mismatch" ? `refusé : ${result.detail}` : result.reason };
  }
  if (verified.status === "failed") {
    await markPaymentFailed(deps.db, payment.id, "Échec confirmé par le prestataire", verified.raw);
    return { status: "processed", note: "échec confirmé" };
  }
  return { status: "processed", note: "toujours en attente chez le prestataire" };
}

/** Prélèvement automatique (carte) : nouvelle transaction rattachée à un abonnement existant. */
async function processRecurringCharge(
  deps: CoreDeps,
  provider: PaymentProvider,
  providerTransactionId: string,
  reference?: string,
): Promise<{ status: ProcessStatus; note?: string }> {
  const verified = await provider.verifyPayment({ reference: reference ?? "", providerTransactionId, expectSubscription: true });
  if (verified.status !== "succeeded") return { status: "processed", note: `prélèvement ${verified.status}` };

  const planId = verified.providerPlanId ? provider.planIdForProviderPlan?.(verified.providerPlanId) : undefined;
  if (!planId) {
    await postLog(deps.db, `⚠️ Prélèvement ${provider.id} #${providerTransactionId} sans formule reconnue : à rattacher à la main.`);
    return { status: "unmatched", note: "plan prestataire inconnu" };
  }

  let sub: Subscription | undefined;
  if (verified.providerSubscriptionId) {
    [sub] = await deps.db
      .select()
      .from(subscriptions)
      .where(and(eq(subscriptions.provider, provider.id), eq(subscriptions.providerSubscriptionId, verified.providerSubscriptionId)));
  }
  if (!sub && verified.customerEmail) {
    const rows = await deps.db
      .select({ sub: subscriptions })
      .from(subscriptions)
      .innerJoin(members, eq(members.id, subscriptions.memberId))
      .where(and(eq(subscriptions.provider, provider.id), sql`lower(${members.email}) = lower(${verified.customerEmail})`));
    if (rows.length === 1) sub = rows[0]!.sub;
  }
  if (!sub) {
    await postLog(deps.db, `⚠️ Prélèvement ${provider.id} #${providerTransactionId} (${verified.customerEmail ?? "email inconnu"}) sans abonné correspondant : à rattacher à la main.`);
    return { status: "unmatched", note: "abonné introuvable" };
  }

  const plan = getPlan(planId);
  const [payment] = await deps.db
    .insert(payments)
    .values({
      reference: `${provider.id.toUpperCase()}-${providerTransactionId}`,
      memberId: sub.memberId,
      subscriptionId: sub.id,
      planId: plan.id,
      provider: provider.id,
      method: "card",
      kind: "recurring",
      amount: plan.priceXof,
      currency: CLUB.currency,
      status: "pending",
      autoRenew: true,
      providerTransactionId,
      createdAt: deps.now(),
    })
    .onConflictDoNothing()
    .returning();
  if (!payment) return { status: "processed", note: "prélèvement déjà enregistré" };
  const result = await confirmPayment(deps, payment.id, verified);
  return { status: "processed", note: result.applied ? undefined : result.detail };
}

/**
 * Re-vérifie un paiement resté en attente (webhook perdu ou en retard).
 * Utilisé par la tâche « verify_pending_payment » et la réconciliation quotidienne.
 */
export async function reverifyPendingPayment(deps: CoreDeps, paymentId: string): Promise<"succeeded" | "failed" | "pending" | "not_pending"> {
  const [payment] = await deps.db.select().from(payments).where(eq(payments.id, paymentId));
  if (!payment || payment.status !== "pending") return "not_pending";
  const provider = deps.providers.get(payment.provider);
  if (payment.provider === "wave" && !payment.providerCheckoutId) {
    await markPaymentFailed(deps.db, payment.id, "Session de paiement jamais créée");
    return "failed";
  }
  const verified = await verifyWithProvider(deps, provider, payment);
  await applyVerification(deps, payment, verified);
  if (verified.status === "pending") {
    const ageHours = (deps.now().getTime() - payment.createdAt.getTime()) / 3_600_000;
    if (ageHours >= CLUB.pendingPaymentAbandonAfterHours) {
      await markPaymentFailed(deps.db, payment.id, "Paiement abandonné (aucune confirmation)");
      return "failed";
    }
  }
  return verified.status;
}
