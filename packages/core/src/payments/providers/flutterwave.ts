import type { PlanId } from "../../config/club";
import { safeEqual, sha256Hex } from "../../crypto";
import { InvalidSignatureError } from "../../errors";
import { requestJson, type FetchLike } from "../../http";
import type {
  CheckoutRequest,
  CheckoutSession,
  NormalizedWebhookEvent,
  PaymentMethod,
  PaymentProvider,
  ProviderSubscriptionStatus,
  RefundRequest,
  VerifiedPayment,
  VerifiedStatus,
  VerifyRequest,
  WebhookRequest,
} from "../types";

/*
 * Flutterwave, API v3 (hosted checkout « Flutterwave Standard » + payment plans).
 * - Carte avec renouvellement auto : `payment_plan` joint au paiement (le moyen est alors forcé sur carte).
 * - Mobile Money (Orange Money, Wave) : option `mobilemoneyfranco` (configurable, à confirmer en sandbox).
 * - Webhook : en-tête `verif-hash` = secret choisi dans le dashboard (comparaison, pas de HMAC en v3).
 *   Comme ce n'est pas une signature du contenu, chaque événement est re-vérifié par l'API.
 */

export interface FlutterwaveConfig {
  secretKey: string;
  webhookHash: string;
  baseUrl: string;
  mobileMoneyOption: string;
  planIds: Partial<Record<PlanId, string>>;
  fetch?: FetchLike;
}

interface FlwTransaction {
  id: number | string;
  tx_ref?: string;
  status?: string;
  amount?: number | string;
  currency?: string;
  payment_type?: string;
  plan?: number | string | null;
  customer?: { email?: string };
  [key: string]: unknown;
}

interface FlwSubscription {
  id: number | string;
  status?: string;
  plan?: number | string;
  customer?: { customer_email?: string; email?: string };
}

function mapStatus(status: string | undefined): VerifiedStatus {
  const s = (status ?? "").toLowerCase();
  if (s === "successful" || s === "succeeded" || s === "completed") return "succeeded";
  if (s === "failed" || s === "cancelled" || s === "canceled" || s === "error") return "failed";
  return "pending";
}

function mapMethod(paymentType: string | undefined): PaymentMethod | undefined {
  if (!paymentType) return undefined;
  if (paymentType.toLowerCase().includes("card")) return "card";
  if (paymentType.toLowerCase().includes("mobilemoney")) return "mobile_money";
  return undefined;
}

export class FlutterwaveProvider implements PaymentProvider {
  readonly id = "flutterwave" as const;
  readonly capabilities = { card: true, mobileMoney: true, recurring: true, refund: true };
  private readonly fetchImpl: FetchLike;

  constructor(private readonly config: FlutterwaveConfig) {
    this.fetchImpl = config.fetch ?? fetch;
  }

  private call<T>(path: string, init: { method?: "GET" | "POST" | "PUT"; body?: unknown } = {}) {
    return requestJson<{ status?: string; message?: string; data?: T }>(
      "Flutterwave",
      `${this.config.baseUrl}${path}`,
      { ...init, headers: { authorization: `Bearer ${this.config.secretKey}` } },
      this.fetchImpl,
    );
  }

  providerPlanIdFor(planId: PlanId): string | undefined {
    return this.config.planIds[planId];
  }

  planIdForProviderPlan(providerPlanId: string): PlanId | undefined {
    const entry = Object.entries(this.config.planIds).find(([, id]) => id === providerPlanId);
    return entry?.[0] as PlanId | undefined;
  }

  async createCheckout(request: CheckoutRequest): Promise<CheckoutSession> {
    if (!request.customer.email) throw new Error("Flutterwave exige l'email du client");
    let paymentOptions = request.method === "card" ? "card" : this.config.mobileMoneyOption;
    let paymentPlan: string | undefined;
    if (request.autoRenew) {
      if (request.method !== "card") throw new Error("Le renouvellement automatique n'existe que par carte");
      paymentPlan = this.providerPlanIdFor(request.plan.id);
      if (!paymentPlan) {
        throw new Error(`Plan récurrent Flutterwave non configuré pour « ${request.plan.id} » (FLW_PLAN_ID_${request.plan.id.toUpperCase()})`);
      }
      paymentOptions = "card";
    }
    const { data } = await this.call<{ link?: string }>("/v3/payments", {
      method: "POST",
      body: {
        tx_ref: request.reference,
        amount: request.amount,
        currency: request.currency,
        redirect_url: request.returnUrl,
        payment_options: paymentOptions,
        ...(paymentPlan ? { payment_plan: paymentPlan } : {}),
        customer: {
          email: request.customer.email,
          name: request.customer.name ?? undefined,
          phonenumber: request.customer.phone ?? undefined,
        },
        customizations: {
          title: "V_ICT_ORIOUS Live Club",
          description: `Formule ${request.plan.label}${request.autoRenew ? " (renouvellement automatique)" : ""}`,
        },
        meta: { reference: request.reference, plan_id: request.plan.id, discord_user_id: request.customer.discordUserId },
      },
    });
    const link = data.data?.link;
    if (!link) throw new Error(`Flutterwave n'a pas renvoyé de lien de paiement (${data.message ?? "réponse vide"})`);
    return { redirectUrl: link };
  }

  async verifyPayment(request: VerifyRequest): Promise<VerifiedPayment> {
    const { data } = request.providerTransactionId
      ? await this.call<FlwTransaction>(`/v3/transactions/${encodeURIComponent(request.providerTransactionId)}/verify`)
      : await this.call<FlwTransaction>(`/v3/transactions/verify_by_reference?tx_ref=${encodeURIComponent(request.reference)}`);
    const tx = data.data;
    if (!tx) return { status: "pending", amount: 0, currency: "", raw: data };
    const verified: VerifiedPayment = {
      status: mapStatus(tx.status),
      reference: tx.tx_ref,
      amount: Number(tx.amount ?? 0),
      currency: String(tx.currency ?? ""),
      providerTransactionId: String(tx.id),
      method: mapMethod(tx.payment_type),
      customerEmail: tx.customer?.email,
      providerPlanId: tx.plan != null && tx.plan !== "" ? String(tx.plan) : undefined,
      raw: {
        id: tx.id,
        tx_ref: tx.tx_ref,
        status: tx.status,
        amount: tx.amount,
        currency: tx.currency,
        payment_type: tx.payment_type,
        plan: tx.plan ?? null,
      },
    };
    if (verified.status === "succeeded" && (request.expectSubscription || verified.providerPlanId)) {
      verified.providerSubscriptionId = await this.findSubscriptionId(verified.providerTransactionId!, verified.customerEmail ?? request.customerEmail ?? undefined, verified.providerPlanId);
    }
    return verified;
  }

  /** Retrouve l'abonnement créé par un paiement (par transaction, sinon par email + plan). */
  private async findSubscriptionId(transactionId: string, email?: string, planId?: string): Promise<string | undefined> {
    try {
      const byTx = await this.call<FlwSubscription[]>(`/v3/subscriptions?transaction_id=${encodeURIComponent(transactionId)}`);
      const first = byTx.data.data?.[0];
      if (first) return String(first.id);
      if (email) {
        const byEmail = await this.call<FlwSubscription[]>(`/v3/subscriptions?email=${encodeURIComponent(email)}`);
        const match = (byEmail.data.data ?? []).filter(
          (s) => (s.status ?? "").toLowerCase() === "active" && (!planId || String(s.plan) === planId),
        );
        if (match.length === 1) return String(match[0]!.id);
      }
    } catch {
      // Non bloquant : l'abonnement sera retrouvé par email lors d'une annulation.
    }
    return undefined;
  }

  async handleWebhook(request: WebhookRequest): Promise<NormalizedWebhookEvent> {
    const received = request.headers["verif-hash"];
    if (!received || !safeEqual(received, this.config.webhookHash)) {
      throw new InvalidSignatureError("En-tête verif-hash absent ou invalide");
    }
    let body: { event?: string; "event.type"?: string; data?: Record<string, unknown> };
    try {
      body = JSON.parse(request.rawBody);
    } catch {
      throw new InvalidSignatureError("Corps JSON illisible");
    }
    const eventType = String(body.event ?? body["event.type"] ?? "unknown");
    const data = (body.data ?? {}) as FlwTransaction & { status?: string };
    const fallbackKey = sha256Hex(request.rawBody);

    if (eventType === "charge.completed" || eventType === "CARD_TRANSACTION" || eventType === "MOBILEMONEY_TRANSACTION") {
      return {
        kind: "payment",
        eventType,
        eventKey: data.id != null ? `charge:${data.id}:${data.status ?? ""}` : fallbackKey,
        reference: data.tx_ref,
        providerTransactionId: data.id != null ? String(data.id) : undefined,
        hintedStatus: mapStatus(data.status),
        payload: body,
      };
    }
    if (eventType === "subscription.cancelled") {
      const customer = data.customer as { email?: string; customer_email?: string } | undefined;
      return {
        kind: "subscription_canceled",
        eventType,
        eventKey: data.id != null ? `subscription.cancelled:${data.id}` : fallbackKey,
        providerSubscriptionId: data.id != null ? String(data.id) : undefined,
        customerEmail: customer?.email ?? customer?.customer_email,
        payload: body,
      };
    }
    return { kind: "ignored", eventType, eventKey: fallbackKey, payload: body };
  }

  async cancelSubscription(providerSubscriptionId: string): Promise<void> {
    await this.call(`/v3/subscriptions/${encodeURIComponent(providerSubscriptionId)}/cancel`, { method: "PUT" });
  }

  async getSubscriptionStatus(providerSubscriptionId: string, hint?: { customerEmail?: string | null }): Promise<ProviderSubscriptionStatus> {
    if (!hint?.customerEmail) return "unknown";
    const { data } = await this.call<FlwSubscription[]>(`/v3/subscriptions?email=${encodeURIComponent(hint.customerEmail)}`);
    const sub = (data.data ?? []).find((s) => String(s.id) === providerSubscriptionId);
    if (!sub) return "unknown";
    return (sub.status ?? "").toLowerCase() === "active" ? "active" : "canceled";
  }

  async refund(request: RefundRequest): Promise<{ status: "succeeded" | "pending" }> {
    if (!request.providerTransactionId) throw new Error("Remboursement Flutterwave : identifiant de transaction requis");
    const { data } = await this.call<{ status?: string }>(`/v3/transactions/${encodeURIComponent(request.providerTransactionId)}/refund`, {
      method: "POST",
      body: request.amount ? { amount: request.amount } : {},
    });
    return { status: (data.data?.status ?? "").toLowerCase() === "completed" ? "succeeded" : "pending" };
  }
}
