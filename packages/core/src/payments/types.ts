import type { Plan, PlanId } from "../config/club";

export type ProviderId = "flutterwave" | "wave";
export type PaymentMethod = "card" | "mobile_money";

export interface ProviderCapabilities {
  card: boolean;
  mobileMoney: boolean;
  /** Prélèvement automatique réel (abonnement chez le prestataire). */
  recurring: boolean;
  refund: boolean;
}

export interface CheckoutRequest {
  /** Notre référence unique, renvoyée par le prestataire (tx_ref / client_reference). */
  reference: string;
  amount: number;
  currency: "XOF";
  plan: Plan;
  method: PaymentMethod;
  autoRenew: boolean;
  customer: { email?: string | null; name?: string | null; phone?: string | null; discordUserId: string };
  /** URL de retour navigateur. Elle n'accorde JAMAIS l'accès à elle seule. */
  returnUrl: string;
  cancelUrl: string;
}

export interface CheckoutSession {
  redirectUrl: string;
  providerCheckoutId?: string;
}

export interface VerifyRequest {
  reference: string;
  providerTransactionId?: string | null;
  providerCheckoutId?: string | null;
  /** Le paiement devait créer un abonnement chez le prestataire (carte + renouvellement auto). */
  expectSubscription?: boolean;
  customerEmail?: string | null;
}

export type VerifiedStatus = "succeeded" | "failed" | "pending";

/** Résultat d'une vérification serveur à serveur auprès du prestataire. */
export interface VerifiedPayment {
  status: VerifiedStatus;
  reference?: string;
  amount: number;
  currency: string;
  providerTransactionId?: string;
  method?: PaymentMethod;
  customerEmail?: string;
  providerPlanId?: string;
  providerSubscriptionId?: string;
  /** Réponse brute (sans secret), conservée pour audit. */
  raw: unknown;
}

export interface WebhookRequest {
  /** En-têtes en minuscules. */
  headers: Record<string, string>;
  /** Corps brut exact, indispensable pour vérifier la signature. */
  rawBody: string;
  now: Date;
}

interface EventBase {
  /** Identifiant d'idempotence de l'événement chez ce prestataire. */
  eventKey: string;
  eventType: string;
  payload: unknown;
}

export type NormalizedWebhookEvent =
  | (EventBase & {
      kind: "payment";
      reference?: string;
      providerTransactionId?: string;
      providerCheckoutId?: string;
      /** Statut annoncé par l'événement : simple indice, la vérification serveur fait foi. */
      hintedStatus: VerifiedStatus;
    })
  | (EventBase & { kind: "subscription_canceled"; providerSubscriptionId?: string; customerEmail?: string })
  | (EventBase & { kind: "refund"; reference?: string; providerTransactionId?: string; providerCheckoutId?: string })
  | (EventBase & { kind: "ignored" });

export type ProviderSubscriptionStatus = "active" | "canceled" | "unknown";

export interface RefundRequest {
  providerTransactionId?: string | null;
  providerCheckoutId?: string | null;
  amount?: number;
}

/**
 * Contrat commun à tous les prestataires. Une opération non supportée lève
 * UnsupportedOperationError : elle n'est jamais simulée.
 */
export interface PaymentProvider {
  readonly id: ProviderId;
  readonly capabilities: ProviderCapabilities;
  createCheckout(request: CheckoutRequest): Promise<CheckoutSession>;
  verifyPayment(request: VerifyRequest): Promise<VerifiedPayment>;
  handleWebhook(request: WebhookRequest): Promise<NormalizedWebhookEvent>;
  cancelSubscription(providerSubscriptionId: string): Promise<void>;
  getSubscriptionStatus(providerSubscriptionId: string, hint?: { customerEmail?: string | null }): Promise<ProviderSubscriptionStatus>;
  refund(request: RefundRequest): Promise<{ status: "succeeded" | "pending" }>;
  /** Identifiant du plan récurrent chez le prestataire pour une formule. */
  providerPlanIdFor?(planId: PlanId): string | undefined;
  /** Formule correspondant à un plan récurrent du prestataire. */
  planIdForProviderPlan?(providerPlanId: string): PlanId | undefined;
}
