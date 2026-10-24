import { hmacSha256Hex, safeEqual } from "../../crypto";
import { InvalidSignatureError, UnsupportedOperationError } from "../../errors";
import { requestJson, type FetchLike } from "../../http";
import type {
  CheckoutRequest,
  CheckoutSession,
  NormalizedWebhookEvent,
  PaymentProvider,
  ProviderSubscriptionStatus,
  RefundRequest,
  VerifiedPayment,
  VerifiedStatus,
  VerifyRequest,
  WebhookRequest,
} from "../types";

/*
 * Wave Business : Checkout API (XOF, Mobile Money Wave uniquement, pas de prélèvement automatique).
 * Webhook en mode « Signing secret » : en-tête Wave-Signature « t=<timestamp>,v1=<hmac>[,v1=…] »,
 * HMAC-SHA256(secret, timestamp + corps brut). Requêtes de plus de 5 minutes refusées (anti-rejeu).
 */

export interface WaveConfig {
  apiKey: string;
  webhookSecret: string;
  baseUrl: string;
  fetch?: FetchLike;
  /** Tolérance d'horodatage du webhook, en secondes. */
  toleranceSeconds?: number;
}

interface WaveSession {
  id: string;
  amount?: string;
  currency?: string;
  client_reference?: string | null;
  checkout_status?: string;
  payment_status?: string;
  transaction_id?: string | null;
  wave_launch_url?: string;
  when_completed?: string | null;
}

function mapSession(session: WaveSession): VerifiedStatus {
  if (session.payment_status === "succeeded") return "succeeded";
  if (session.payment_status === "cancelled" || session.checkout_status === "expired") return "failed";
  return "pending";
}

/** Vérifie l'en-tête Wave-Signature. Exporté pour les tests et le script de simulation. */
export function verifyWaveSignature(header: string | undefined, rawBody: string, secret: string, now: Date, toleranceSeconds = 300): boolean {
  if (!header) return false;
  const parts = header.split(",").map((p) => p.trim());
  const timestamp = parts.find((p) => p.startsWith("t="))?.slice(2);
  const signatures = parts.filter((p) => p.startsWith("v1=")).map((p) => p.slice(3));
  if (!timestamp || signatures.length === 0 || !/^\d+$/.test(timestamp)) return false;
  if (Math.abs(now.getTime() / 1000 - Number(timestamp)) > toleranceSeconds) return false;
  const expected = hmacSha256Hex(secret, timestamp + rawBody);
  return signatures.some((sig) => safeEqual(sig, expected));
}

export function signWavePayload(rawBody: string, secret: string, now: Date): string {
  const timestamp = Math.floor(now.getTime() / 1000).toString();
  return `t=${timestamp},v1=${hmacSha256Hex(secret, timestamp + rawBody)}`;
}

export class WaveProvider implements PaymentProvider {
  readonly id = "wave" as const;
  readonly capabilities = { card: false, mobileMoney: true, recurring: false, refund: true };
  /** Wave n'a pas de sandbox documentée : seul le faux serveur local compte comme test. */
  readonly testMode: boolean;
  private readonly fetchImpl: FetchLike;

  constructor(private readonly config: WaveConfig) {
    this.fetchImpl = config.fetch ?? fetch;
    this.testMode = !config.baseUrl.startsWith("https://api.wave.com");
  }

  private call<T>(path: string, init: { method?: "GET" | "POST"; body?: unknown; idempotencyKey?: string } = {}) {
    return requestJson<T>(
      "Wave",
      `${this.config.baseUrl}${path}`,
      {
        method: init.method,
        body: init.body,
        headers: {
          authorization: `Bearer ${this.config.apiKey}`,
          ...(init.idempotencyKey ? { "idempotency-key": init.idempotencyKey } : {}),
        },
      },
      this.fetchImpl,
    );
  }

  async createCheckout(request: CheckoutRequest): Promise<CheckoutSession> {
    if (request.method !== "mobile_money") throw new UnsupportedOperationError("wave", "paiement par carte");
    if (request.autoRenew) throw new UnsupportedOperationError("wave", "renouvellement automatique");
    const { data } = await this.call<WaveSession>("/v1/checkout/sessions", {
      method: "POST",
      idempotencyKey: request.reference,
      body: {
        amount: String(request.amount),
        currency: request.currency,
        client_reference: request.reference,
        success_url: request.returnUrl,
        error_url: request.cancelUrl,
      },
    });
    if (!data.wave_launch_url) throw new Error("Wave n'a pas renvoyé de lien de paiement");
    return { redirectUrl: data.wave_launch_url, providerCheckoutId: data.id };
  }

  async verifyPayment(request: VerifyRequest): Promise<VerifiedPayment> {
    if (!request.providerCheckoutId) throw new Error("Vérification Wave : identifiant de session de paiement requis");
    const { data } = await this.call<WaveSession>(`/v1/checkout/sessions/${encodeURIComponent(request.providerCheckoutId)}`);
    return {
      status: mapSession(data),
      reference: data.client_reference ?? undefined,
      amount: Number(data.amount ?? 0),
      currency: String(data.currency ?? ""),
      providerTransactionId: data.transaction_id ?? undefined,
      method: "mobile_money",
      raw: {
        id: data.id,
        client_reference: data.client_reference,
        amount: data.amount,
        currency: data.currency,
        checkout_status: data.checkout_status,
        payment_status: data.payment_status,
        transaction_id: data.transaction_id,
      },
    };
  }

  async handleWebhook(request: WebhookRequest): Promise<NormalizedWebhookEvent> {
    const header = request.headers["wave-signature"];
    if (!verifyWaveSignature(header, request.rawBody, this.config.webhookSecret, request.now, this.config.toleranceSeconds)) {
      throw new InvalidSignatureError("Signature Wave invalide ou trop ancienne");
    }
    let body: { id?: string; type?: string; data?: WaveSession };
    try {
      body = JSON.parse(request.rawBody);
    } catch {
      throw new InvalidSignatureError("Corps JSON illisible");
    }
    const eventType = String(body.type ?? "unknown");
    const session = body.data;
    const eventKey = body.id ?? `${eventType}:${session?.id ?? ""}:${session?.payment_status ?? ""}`;
    if (eventType.startsWith("checkout.session.") && session) {
      return {
        kind: "payment",
        eventType,
        eventKey,
        reference: session.client_reference ?? undefined,
        providerCheckoutId: session.id,
        providerTransactionId: session.transaction_id ?? undefined,
        hintedStatus: mapSession(session),
        payload: body,
      };
    }
    return { kind: "ignored", eventType, eventKey, payload: body };
  }

  async cancelSubscription(): Promise<void> {
    throw new UnsupportedOperationError("wave", "annulation d'abonnement (pas d'abonnement chez Wave)");
  }

  async getSubscriptionStatus(): Promise<ProviderSubscriptionStatus> {
    throw new UnsupportedOperationError("wave", "statut d'abonnement (pas d'abonnement chez Wave)");
  }

  async refund(request: RefundRequest): Promise<{ status: "succeeded" | "pending" }> {
    if (!request.providerCheckoutId) throw new Error("Remboursement Wave : identifiant de session requis");
    if (request.amount) throw new UnsupportedOperationError("wave", "remboursement partiel via la session de paiement");
    await this.call(`/v1/checkout/sessions/${encodeURIComponent(request.providerCheckoutId)}/refund`, { method: "POST" });
    return { status: "succeeded" };
  }
}
