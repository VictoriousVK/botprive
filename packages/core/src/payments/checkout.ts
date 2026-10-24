import { and, eq } from "drizzle-orm";
import { members, payments, type Payment } from "@vk/db";
import { audit } from "../audit";
import { CLUB, type PlanId } from "../config/club";
import { newPaymentReference } from "../crypto";
import { addMinutes } from "../dates";
import type { CoreDeps } from "../deps";
import { DomainError } from "../errors";
import { enqueue } from "../jobs/queue";
import { getCatalog } from "../settings";
import { hasAccess, type SubscriptionStatus } from "../state-machine";
import { ensureSubscription, getSubscriptionForMember } from "../subscriptions/service";
import type { PaymentMethod } from "./types";

export interface StartCheckoutInput {
  memberId: string;
  planId: PlanId;
  method: PaymentMethod;
  autoRenew: boolean;
  /** Case « j'accepte le prélèvement automatique » cochée explicitement. */
  autoRenewConsent: boolean;
  /** Email saisi dans le tunnel (obligatoire pour la carte). */
  email?: string | null;
  phone?: string | null;
}

export interface StartCheckoutResult {
  redirectUrl: string;
  reference: string;
}

/** Un prélèvement carte actif existe : un paiement manuel créerait un double paiement. */
export async function hasActiveAutoRenewal(deps: Pick<CoreDeps, "db">, memberId: string): Promise<boolean> {
  const sub = await getSubscriptionForMember(deps.db, memberId);
  return !!sub && sub.renewalMode === "auto_card" && hasAccess(sub.status as SubscriptionStatus) && sub.status !== "canceled";
}

/**
 * Crée le paiement en attente puis la session chez le prestataire.
 * L'accès ne sera accordé qu'après webhook signé + vérification serveur à serveur.
 */
export async function startCheckout(deps: CoreDeps, input: StartCheckoutInput): Promise<StartCheckoutResult> {
  const now = deps.now();
  const catalog = await getCatalog(deps.db);
  const plan = catalog.plans[input.planId];
  if (!plan) throw new DomainError("unknown_plan", "Formule inconnue");
  if (!plan.purchasable || plan.priceXof === null) {
    throw new DomainError("plan_unavailable", `La formule ${plan.label} n'est pas encore disponible (tarif en cours de définition)`);
  }
  if (deps.env.PAYMENT_MODE === "live" && !catalog.pricesValidated) {
    throw new DomainError("prices_not_validated", "Les tarifs n'ont pas encore été validés : paiement réel impossible");
  }
  const amount = plan.priceXof;
  if (input.autoRenew && input.method !== "card") {
    throw new DomainError("auto_renew_card_only", "Le renouvellement automatique n'est possible que par carte bancaire");
  }
  if (input.autoRenew && !input.autoRenewConsent) {
    throw new DomainError("consent_required", "Coche la case d'accord pour le prélèvement automatique");
  }
  const provider = deps.providers.forMethod(input.method);
  if (!provider) {
    throw new DomainError("method_unavailable", input.method === "card" ? "Le paiement par carte n'est pas encore disponible" : "Le paiement Mobile Money n'est pas encore disponible");
  }
  if (input.autoRenew && !provider.capabilities.recurring) {
    throw new DomainError("auto_renew_unavailable", "Le renouvellement automatique n'est pas disponible avec ce moyen de paiement");
  }
  const providerPlanId = provider.id === "flutterwave" ? plan.flutterwavePlanId : null;
  if (input.autoRenew && !providerPlanId) {
    throw new DomainError("auto_renew_unavailable", `Le renouvellement automatique n'est pas encore configuré pour la formule ${plan.label}`);
  }
  if (await hasActiveAutoRenewal(deps, input.memberId)) {
    throw new DomainError(
      "auto_renewal_active",
      "Ton renouvellement par carte est actif : il sera prélevé automatiquement. Annule-le d'abord dans ton espace si tu veux payer autrement.",
    );
  }

  const [member] = await deps.db.select().from(members).where(eq(members.id, input.memberId));
  if (!member) throw new DomainError("not_found", "Membre introuvable");
  const email = input.email?.trim() || member.email;
  if (!email) throw new DomainError("email_required", "Ton adresse email est nécessaire pour le reçu et les rappels");
  if (input.email && input.email !== member.email) {
    await deps.db.update(members).set({ email: input.email.trim(), emailVerified: false, updatedAt: now }).where(eq(members.id, member.id));
  }
  if (input.phone) {
    await deps.db.update(members).set({ phone: input.phone.trim(), updatedAt: now }).where(eq(members.id, member.id));
  }

  const sub = await ensureSubscription(deps.db, member.id, plan.id, now);
  const reference = newPaymentReference(now);
  const [payment] = await deps.db
    .insert(payments)
    .values({
      reference,
      memberId: member.id,
      subscriptionId: sub.id,
      planId: plan.id,
      provider: provider.id,
      method: input.method,
      kind: hasAccess(sub.status as SubscriptionStatus) ? "renewal" : "initial",
      amount,
      currency: CLUB.currency,
      status: "pending",
      autoRenew: input.autoRenew,
      createdAt: now,
    })
    .returning();

  const appUrl = deps.env.APP_URL.replace(/\/$/, "");
  const session = await provider.createCheckout({
    reference,
    amount,
    currency: CLUB.currency,
    plan,
    method: input.method,
    autoRenew: input.autoRenew,
    providerPlanId,
    customer: { email, name: member.name ?? member.discordUsername, phone: input.phone ?? member.phone, discordUserId: member.discordUserId },
    returnUrl: `${appUrl}/paiement/retour?ref=${encodeURIComponent(reference)}`,
    cancelUrl: `${appUrl}/paiement/retour?ref=${encodeURIComponent(reference)}&annule=1`,
  });
  if (session.providerCheckoutId) {
    await deps.db.update(payments).set({ providerCheckoutId: session.providerCheckoutId }).where(eq(payments.id, payment!.id));
  }
  // Filet de sécurité si le webhook se perd : re-vérification serveur programmée.
  await enqueue(deps.db, "verify_pending_payment", { paymentId: payment!.id }, { runAt: addMinutes(now, CLUB.pendingPaymentReverifyAfterMinutes) });
  await audit(deps.db, {
    actorType: "member",
    actorId: member.discordUserId,
    action: "checkout.created",
    memberId: member.id,
    details: { reference, plan: plan.id, method: input.method, provider: provider.id, autoRenew: input.autoRenew, consent: input.autoRenewConsent },
  }, now);
  return { redirectUrl: session.redirectUrl, reference };
}

/** Lecture d'un paiement limitée à son propriétaire (un membre ne voit jamais les paiements d'un autre). */
export async function getPaymentForMember(deps: Pick<CoreDeps, "db">, memberId: string, reference: string): Promise<Payment | null> {
  const [row] = await deps.db
    .select()
    .from(payments)
    .where(and(eq(payments.reference, reference), eq(payments.memberId, memberId)));
  return row ?? null;
}
